import CryptoKit
import Foundation

/// index.json of the asset packs (web-dev/tools/build_ios_packs.py): every part with its size and SHA-256, and the
/// files inside it in order. A file's place in its part is the sum of the sizes before it.
struct PackIndex: Decodable {
    struct File: Decodable {
        let p: String
        let s: Int64
    }
    struct Part: Decodable {
        let name: String
        let size: Int64
        let sha256: String
        let files: [File]
    }
    let format: Int
    let id: String
    let totalBytes: Int64
    let fileCount: Int
    let parts: [Part]
}

enum DownloadError: LocalizedError {
    case badSource(String)
    case http(Int, String)
    case badIndex(String)
    case badHash(String)
    case shortFile(String)
    case noSpace(need: Int64, free: Int64)
    case rangeIgnored

    var errorDescription: String? {
        switch self {
        case .badSource(let s): return "The source address is not usable: \(s)"
        case .http(let code, let name): return "The server answered \(code) for \(name)"
        case .badIndex(let why): return "index.json is not what this app reads: \(why)"
        case .badHash(let name): return "\(name) arrived damaged (its checksum is wrong)"
        case .shortFile(let name): return "\(name) is shorter than it should be"
        case .noSpace(let need, let free):
            return "Not enough free space: \(DeviceInfo.mb(need)) needed, \(DeviceInfo.mb(free)) free"
        case .rangeIgnored: return "The server restarted the file instead of continuing it"
        }
    }
}

/// Fetches the asset packs into Library/Application Support/assets. One part at a time: downloaded (continuing a
/// part that was cut short, with an HTTP Range), checked against its SHA-256, its files written out, then deleted;
/// so the phone needs room for the game and one part, not for the game twice. What is done is remembered
/// (AssetStore.State), so a download that is stopped, or an app that is closed, goes on from the last whole part.
final class AssetDownloader: NSObject, URLSessionDataDelegate {
    enum Phase: Equatable {
        case idle, index, downloading, verifying, extracting, waitingForNetwork, paused, done
        case failed(String)
    }

    struct Progress {
        var phase: Phase = .idle
        var part = 0
        var partCount = 0
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
        var bytesPerSecond: Double = 0
    }

    /// Called on the main thread.
    var onProgress: ((Progress) -> Void)?
    private(set) var progress = Progress()
    var isRunning: Bool { runTask != nil }

    private var runTask: Task<Void, Never>?
    private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "date.arcueid.tsukirebuild.download"
        return q
    }()
    private var session: URLSession?

    /// The transfer under way. Set before its task starts, then touched on the delegate queue only.
    private final class Transfer {
        let file: URL
        var offset: Int64
        let name: String
        var handle: FileHandle?
        var received: Int64 = 0
        var failure: Error?
        var continuation: CheckedContinuation<Void, Error>?
        init(file: URL, offset: Int64, name: String) { self.file = file; self.offset = offset; self.name = name }
    }
    private var transfer: Transfer?
    private let lock = NSLock()
    private var currentTask: URLSessionTask?

    // Progress bookkeeping (delegate queue and the run task; published to the main thread as a copy).
    private var bytesBefore: Int64 = 0     // the parts already done
    private var lastReport = Date.distantPast
    private var speedMark = (time: Date(), bytes: Int64(0))
    private var speed: Double = 0

    // MARK: - Control

    private func configuration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        let cellular = Config.allowCellular
        c.allowsCellularAccess = cellular
        c.allowsExpensiveNetworkAccess = cellular
        c.allowsConstrainedNetworkAccess = cellular
        c.waitsForConnectivity = true
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 24 * 3600
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpMaximumConnectionsPerHost = 2
        return c
    }

    static func sourceURL() throws -> URL {
        var s = Config.assetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw DownloadError.badSource("none is set") }
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s), let scheme = url.scheme, scheme == "https" || scheme == "http", url.host != nil else {
            throw DownloadError.badSource(s)
        }
        return url
    }

    func start() {
        guard runTask == nil else { return }
        tlog("download", "start: source \(Config.assetURL), mobile data \(Config.allowCellular ? "allowed" : "not allowed"), free \(DeviceInfo.freeDisk().map(DeviceInfo.mb) ?? "?")")
        session?.invalidateAndCancel()
        session = URLSession(configuration: configuration(), delegate: self, delegateQueue: delegateQueue)
        runTask = Task { [weak self] in
            await self?.run()
        }
    }

    func pause() {
        guard let task = runTask else { return }
        tlog("download", "pause asked for")
        task.cancel()
        lock.lock(); let t = currentTask; lock.unlock()
        t?.cancel()
    }

    /// Fetches index.json alone, to say how much there is to download before anything is.
    func peek(_ done: @escaping (Result<PackIndex, Error>) -> Void) {
        Task {
            let result: Result<PackIndex, Error>
            do { result = .success(try await self.fetchIndex(try AssetDownloader.sourceURL())) } catch { result = .failure(error) }
            DispatchQueue.main.async { done(result) }
        }
    }

    // MARK: - The run

    private func publish(_ change: @escaping (inout Progress) -> Void) {
        DispatchQueue.main.async {
            change(&self.progress)
            self.onProgress?(self.progress)
        }
    }

    private func run() async {
        var outcome = Phase.done
        do {
            try await download()
            tlog("download", "complete: \(AssetStore.summary())")
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
            if cancelled {
                outcome = .paused
                tlog("download", "paused")
            } else {
                outcome = .failed(error.localizedDescription)
                tlog("download", "failed: \(error.localizedDescription) [\(error)]")
            }
        }
        let phase = outcome
        DispatchQueue.main.async {
            self.runTask = nil
            self.progress.phase = phase
            self.progress.bytesPerSecond = 0
            self.onProgress?(self.progress)
        }
    }

    private func fetchIndex(_ base: URL) async throws -> PackIndex {
        let url = base.appendingPathComponent("index.json")
        let plain = URLSession(configuration: configuration())
        defer { plain.finishTasksAndInvalidate() }
        let (data, response) = try await plain.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw DownloadError.http(http.statusCode, "index.json") }
        let index: PackIndex
        do { index = try JSONDecoder().decode(PackIndex.self, from: data) } catch { throw DownloadError.badIndex("\(error)") }
        guard index.format == 1 else { throw DownloadError.badIndex("format \(index.format)") }
        guard !index.parts.isEmpty else { throw DownloadError.badIndex("no parts") }
        return index
    }

    private func download() async throws {
        let base = try AssetDownloader.sourceURL()
        AssetStore.prepareDirectories()
        publish { $0.phase = .index }
        let index = try await fetchIndex(base)
        tlog("download", "index \(index.id.prefix(12)): \(index.fileCount) files, \(index.totalBytes) bytes, \(index.parts.count) parts")

        var state = AssetStore.loadState() ?? AssetStore.State(indexID: index.id, doneParts: [], complete: false, totalBytes: 0, fileCount: 0, source: "", completedAt: nil)
        let known = Set(index.parts.map(\.sha256))
        if state.indexID != index.id {
            // Another build of the packs: the parts that are the same in both stay done.
            state.doneParts = state.doneParts.filter { known.contains($0) }
            state.indexID = index.id
            tlog("download", "the packs have changed: \(state.doneParts.count) parts are the same and stay")
        }
        state.complete = false
        state.completedAt = nil
        state.totalBytes = index.totalBytes
        state.fileCount = index.fileCount
        state.source = base.absoluteString
        AssetStore.save(state)

        var done = Set(state.doneParts)
        let todo = index.parts.filter { !done.contains($0.sha256) }
        bytesBefore = index.totalBytes - todo.reduce(0) { $0 + $1.size }
        let need = todo.reduce(0) { $0 + $1.size } + (todo.map(\.size).max() ?? 0) + 64 * 1_048_576
        if let free = DeviceInfo.freeDisk(), free < need { throw DownloadError.noSpace(need: need, free: free) }
        let before = bytesBefore
        publish { $0.partCount = index.parts.count; $0.bytesTotal = index.totalBytes; $0.bytesDone = before; $0.part = index.parts.count - todo.count }

        // A part left over from an index that no longer names it is only in the way.
        let wanted = Set(todo.map(\.name))
        for old in (try? FileManager.default.contentsOfDirectory(at: AssetStore.downloadsDir, includingPropertiesForKeys: nil)) ?? [] where !wanted.contains(old.lastPathComponent) {
            try? FileManager.default.removeItem(at: old)
        }

        for (i, part) in index.parts.enumerated() where !done.contains(part.sha256) {
            try Task.checkCancellation()
            let file = AssetStore.downloadsDir.appendingPathComponent(part.name)
            publish { $0.phase = .downloading; $0.part = i + 1 }
            try await fetch(part, from: base.appendingPathComponent(part.name), to: file)
            try Task.checkCancellation()
            publish { $0.phase = .extracting }
            try extract(part, from: file)
            done.insert(part.sha256)
            state.doneParts.append(part.sha256)
            AssetStore.save(state)
            try? FileManager.default.removeItem(at: file)
            bytesBefore += part.size
            let now = bytesBefore
            publish { $0.bytesDone = now }
            tlog("download", "part \(i + 1)/\(index.parts.count) in: \(part.name), \(part.files.count) files")
        }

        let removed = sweep(index)
        if removed > 0 { tlog("download", "removed \(removed) files the packs no longer have") }
        state.complete = true
        state.completedAt = Date()
        AssetStore.save(state)
        AssetStore.excludeFromBackup(AssetStore.assetsDir)
    }

    /// One part, whole and checked. A connection that drops is taken up again from where it stopped; a part whose
    /// checksum is wrong is thrown away and fetched once more.
    private func fetch(_ part: PackIndex.Part, from url: URL, to file: URL) async throws {
        var attempt = 0
        while true {
            do {
                try await transferFile(url, to: file, size: part.size, name: part.name)
                publish { $0.phase = .verifying }
                let sha = try AssetDownloader.sha256(of: file)
                if sha == part.sha256 { return }
                tlog("download", "\(part.name): checksum \(sha.prefix(16)) is not \(part.sha256.prefix(16)); fetching it again")
                try? FileManager.default.removeItem(at: file)
                throw DownloadError.badHash(part.name)
            } catch {
                if Task.isCancelled || error is CancellationError { throw error }
                if let e = error as? URLError, e.code == .cancelled { throw error }
                if case DownloadError.http(let code, _) = error, code == 404 || code == 403 || code == 401 { throw error }
                attempt += 1
                if attempt > 6 { throw error }
                let wait = min(60, 2 << attempt)
                tlog("download", "\(part.name): \(error.localizedDescription); trying again in \(wait) s (attempt \(attempt))")
                publish { $0.phase = .waitingForNetwork }
                try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                publish { $0.phase = .downloading }
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }

    private func transferFile(_ url: URL, to file: URL, size: Int64, name: String) async throws {
        let fm = FileManager.default
        var have = AssetDownloader.fileSize(file) ?? 0
        if have > size { try? fm.removeItem(at: file); have = 0 }
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        let start = have
        let base = bytesBefore
        publish { $0.bytesDone = base + start }
        if have == size { return }   // all here from an earlier run: the checksum decides

        var request = URLRequest(url: url)
        if have > 0 {
            request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range")
            tlog("download", "\(name): going on from byte \(have) of \(size)")
        }
        guard let session = self.session else { throw CancellationError() }
        let t = Transfer(file: file, offset: have, name: name)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                t.continuation = c
                let task = session.dataTask(with: request)
                self.lock.lock()
                self.transfer = t
                self.currentTask = task
                self.lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.lock.lock(); let task = self.currentTask; self.lock.unlock()
            task?.cancel()
        }
        guard AssetDownloader.fileSize(file) == size else { throw DownloadError.shortFile(name) }
    }

    // MARK: - URLSession delegate (the delegate queue)

    private var active: Transfer? {
        lock.lock(); defer { lock.unlock() }
        return transfer
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let t = active, let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        do {
            switch http.statusCode {
            case 206:
                break
            case 200:
                // The server sent the whole file: start it again from nothing.
                if t.offset > 0 { tlog("download", "\(t.name): the server ignored the range; starting the part again") }
                try Data().write(to: t.file)
                t.offset = 0
            case 416:
                try? FileManager.default.removeItem(at: t.file)
                throw DownloadError.rangeIgnored
            default:
                throw DownloadError.http(http.statusCode, t.name)
            }
            let handle = try FileHandle(forWritingTo: t.file)
            try handle.seek(toOffset: UInt64(t.offset))
            try handle.truncate(atOffset: UInt64(t.offset))
            t.handle = handle
            completionHandler(.allow)
        } catch {
            t.failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let t = active, let handle = t.handle else { return }
        do {
            try handle.write(contentsOf: data)
            t.received += Int64(data.count)
        } catch {
            t.failure = error
            dataTask.cancel()
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
        lastReport = now
        let total = bytesBefore + t.offset + t.received
        let span = now.timeIntervalSince(speedMark.time)
        if span >= 2 {
            speed = Double(total - speedMark.bytes) / span
            speedMark = (now, total)
        }
        let rate = speed
        publish { $0.phase = .downloading; $0.bytesDone = total; $0.bytesPerSecond = rate }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let t = transfer
        transfer = nil
        currentTask = nil
        lock.unlock()
        guard let t else { return }
        try? t.handle?.close()
        let c = t.continuation
        t.continuation = nil
        if let failure = t.failure ?? error { c?.resume(throwing: failure) } else { c?.resume() }
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        tlog("download", "waiting for a connection (mobile data \(Config.allowCellular ? "allowed" : "not allowed"))")
        publish { $0.phase = .waitingForNetwork; $0.bytesPerSecond = 0 }
    }

    // MARK: - Files

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let more: Bool = try autoreleasepool {
                guard let data = try handle.read(upToCount: 1 << 20), !data.isEmpty else { return false }
                hasher.update(data: data)
                return true
            }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func destination(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains(""), !parts.contains(".."), !parts.contains(".") else { throw DownloadError.badIndex("path \(path)") }
        return parts.reduce(AssetStore.assetsDir) { $0.appendingPathComponent($1) }
    }

    private func extract(_ part: PackIndex.Part, from file: URL) throws {
        let fm = FileManager.default
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var made = Set<String>()
        for f in part.files {
            let dest = try AssetDownloader.destination(f.p)
            let dir = dest.deletingLastPathComponent()
            if made.insert(dir.path).inserted { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            guard fm.createFile(atPath: dest.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let output = try FileHandle(forWritingTo: dest)
            var left = f.s
            do {
                while left > 0 {
                    let want = Int(min(left, 1 << 20))
                    let wrote: Int = try autoreleasepool {
                        guard let data = try input.read(upToCount: want), !data.isEmpty else { return 0 }
                        try output.write(contentsOf: data)
                        return data.count
                    }
                    if wrote == 0 { throw DownloadError.shortFile(part.name) }
                    left -= Int64(wrote)
                }
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
        }
    }

    /// Deletes what is in the assets folder and not in the index (files of an older build of the packs).
    private func sweep(_ index: PackIndex) -> Int {
        let fm = FileManager.default
        let root = AssetStore.assetsDir.standardizedFileURL.path
        var keep = Set<String>()
        for part in index.parts { for f in part.files { keep.insert(f.p) } }
        guard let walk = fm.enumerator(at: AssetStore.assetsDir, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var removed = 0
        for case let url as URL in walk {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root + "/") else { continue }
            if !keep.contains(String(path.dropFirst(root.count + 1))) {
                try? fm.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }
}
