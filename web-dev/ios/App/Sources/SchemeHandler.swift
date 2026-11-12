import Foundation
import WebKit

/// Answers every request to app://tsukihime.ios/ from files, as the Android app's request interceptor and the
/// desktop app's protocol handler do:
///   /assets/...    the downloaded game files (Library/Application Support/assets)
///   /__native/...  this app's own pages (the compat probe and its test clips)
///   anything else  web/app, as it is in the repository (the bundle's www folder)
/// Byte ranges are answered with 206 and Content-Range, which a <video> needs before it will play or seek.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let www: URL
    private let native: URL
    private let assets: URL
    private let io = DispatchQueue(label: "date.arcueid.tsukirebuild.serve", qos: .userInitiated, attributes: .concurrent)
    /// The tasks WebKit has started and not stopped. Main thread only: WebKit starts and stops tasks there, and every
    /// call on a task is made there after looking here, because a call on a stopped task raises an exception.
    private var live = Set<ObjectIdentifier>()
    private static let chunk = 512 * 1024

    /// Counted for the log: requests answered, and those that failed.
    private(set) var served = 0
    private(set) var missing = 0

    override init() {
        let bundle = Bundle.main.bundleURL
        www = bundle.appendingPathComponent("www", isDirectory: true)
        native = bundle.appendingPathComponent("native", isDirectory: true)
        assets = AssetStore.assetsDir
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        live.insert(id)
        let request = urlSchemeTask.request
        io.async { [weak self] in self?.serve(urlSchemeTask, id: id, request: request) }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        live.remove(ObjectIdentifier(urlSchemeTask))
    }

    // MARK: - Movies in another format

    /// Whether this iPhone plays AV1, which every movie of the game is. VideoToolbox's answer until the page has asked
    /// WebKit itself (bridge.js, mediaCapabilities), whose answer is the one that counts.
    static var av1Plays = DeviceInfo.hardwareDecode("av01")
    /// Folders beside assets/movie that may hold the same movies in a format every iPhone decodes. None is published
    /// yet: they are only made if a device shows AV1 failing (NOTES.md). The page asks for assets/movie/NAME.mp4 either way.
    static let fallbackFolders = ["movie-h264", "movie-hevc"]
    private var announced = Set<String>()

    private func fallbackMovie(_ name: String) -> URL? {
        guard !SchemeHandler.av1Plays else { return nil }
        for folder in SchemeHandler.fallbackFolders {
            let file = assets.appendingPathComponent(folder).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            DispatchQueue.main.async {
                if self.announced.insert(name).inserted { tlog("serve", "movie \(name): AV1 does not play here, serving \(folder)/\(name)") }
            }
            return file
        }
        return nil
    }

    // MARK: - Files

    static let types: [String: String] = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8", "json": "application/json", "txt": "text/plain; charset=utf-8",
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "avif": "image/avif",
        "gif": "image/gif", "svg": "image/svg+xml", "ico": "image/x-icon",
        "ogg": "audio/ogg", "opus": "audio/ogg", "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav", "caf": "audio/x-caf",
        "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "webm": "video/webm",
        "otf": "font/otf", "ttf": "font/ttf", "woff": "font/woff", "woff2": "font/woff2", "wasm": "application/wasm",
    ]

    private func fileURL(for url: URL) -> URL? {
        var path = url.path   // percent-decoded
        if path.isEmpty || path == "/" { path = "/index.html" }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.isEmpty || parts.contains("..") || parts.contains(".") { return nil }
        let base: URL, rest: ArraySlice<String>
        switch parts[0] {
        case "assets":
            base = assets; rest = parts.dropFirst()
            if rest.count == 2, rest.first == "movie", let other = fallbackMovie(parts[2]) { return other }
        case "__native": base = native; rest = parts.dropFirst()
        default: base = www; rest = parts[...]
        }
        if rest.isEmpty { return nil }
        return rest.reduce(base) { $0.appendingPathComponent($1) }
    }

    /// `bytes=a-b`, `bytes=a-` or `bytes=-n` against a file of `size` bytes: the first and last byte to send, nil where
    /// there is no (usable) Range header, and (-1, -1) where the range starts past the end.
    static func range(_ header: String?, size: Int64) -> (Int64, Int64)? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), header.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst(6)
        if spec.contains(",") { return nil }   // several ranges: the whole file is a correct answer
        let ends = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard ends.count == 2 else { return nil }
        let a = ends[0].trimmingCharacters(in: .whitespaces), b = ends[1].trimmingCharacters(in: .whitespaces)
        if a.isEmpty {
            guard let n = Int64(b), n > 0 else { return nil }
            return size == 0 ? (-1, -1) : (max(0, size - n), size - 1)
        }
        guard let first = Int64(a), first >= 0 else { return nil }
        if first >= size { return (-1, -1) }
        if b.isEmpty { return (first, size - 1) }
        guard let last = Int64(b), last >= first else { return nil }
        return (first, min(last, size - 1))
    }

    // MARK: - Answering

    /// Runs `body` on the main thread if WebKit has not stopped the task; false if it has.
    private func onMain(_ id: ObjectIdentifier, _ body: () -> Void) -> Bool {
        var alive = false
        DispatchQueue.main.sync {
            if live.contains(id) { body(); alive = true }
        }
        return alive
    }

    private func finish(_ task: WKURLSchemeTask, _ id: ObjectIdentifier) {
        DispatchQueue.main.sync {
            if live.remove(id) != nil { task.didFinish() }
        }
    }

    private func answer(_ task: WKURLSchemeTask, _ id: ObjectIdentifier, url: URL, status: Int, headers: [String: String], body: Data?) {
        var all = headers
        all["Content-Length"] = String(body?.count ?? 0)
        all["Cache-Control"] = "no-cache"
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: all) else { return }
        guard onMain(id, { task.didReceive(response); if let body, !body.isEmpty { task.didReceive(body) } }) else { return }
        finish(task, id)
    }

    private func serve(_ task: WKURLSchemeTask, id: ObjectIdentifier, request: URLRequest) {
        guard let url = request.url else { return }
        let method = (request.httpMethod ?? "GET").uppercased()
        let text = ["Content-Type": "text/plain; charset=utf-8"]
        guard method == "GET" || method == "HEAD" else {
            answer(task, id, url: url, status: 405, headers: text, body: Data("method not allowed".utf8))
            return
        }
        guard let file = fileURL(for: url),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let fileSize = values.fileSize else {
            DispatchQueue.main.async { self.missing += 1 }
            tlog("serve", "404 \(url.path)")
            answer(task, id, url: url, status: 404, headers: text, body: method == "HEAD" ? nil : Data("not found".utf8))
            return
        }
        let size = Int64(fileSize)
        var headers = [
            "Content-Type": SchemeHandler.types[file.pathExtension.lowercased()] ?? "application/octet-stream",
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
        ]
        var first: Int64 = 0, last = size - 1, status = 200
        if let r = SchemeHandler.range(request.value(forHTTPHeaderField: "Range"), size: size) {
            if r.0 < 0 {
                answer(task, id, url: url, status: 416, headers: ["Content-Range": "bytes */\(size)"], body: nil)
                return
            }
            first = r.0; last = r.1; status = 206
            headers["Content-Range"] = "bytes \(first)-\(last)/\(size)"
        }
        let length = max(0, last - first + 1)
        headers["Content-Length"] = String(length)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        guard onMain(id, { task.didReceive(response) }) else { return }
        DispatchQueue.main.async { self.served += 1 }
        if method == "HEAD" || length == 0 { finish(task, id); return }

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            _ = onMain(id) { self.live.remove(id); task.didFailWithError(URLError(.cannotOpenFile)) }
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(first))
            var left = length
            while left > 0 {
                let want = Int(min(Int64(SchemeHandler.chunk), left))
                // (autoreleasepool: a movie is read in hundreds of chunks on one queue thread)
                let data: Data? = try autoreleasepool { try handle.read(upToCount: want) }
                guard let data, !data.isEmpty else { break }
                left -= Int64(data.count)
                guard onMain(id, { task.didReceive(data) }) else { return }   // stopped: a seek, or the page has gone
            }
            if left > 0 { throw URLError(.cannotLoadFromNetwork) }
            finish(task, id)
        } catch {
            tlog("serve", "read failed \(url.path): \(error.localizedDescription)")
            _ = onMain(id) { self.live.remove(id); task.didFailWithError(error) }
        }
    }
}
