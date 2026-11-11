import Foundation

/// The in-app debug log: one text file in Documents/Logs, which the Files app shows (UIFileSharingEnabled) and the
/// log viewer reads. Everything worth knowing without a Mac goes here: the device, the page's console and errors,
/// the compat probe, memory warnings, ended content processes, the asset download.
final class DebugLog {
    static let shared = DebugLog()
    static let didAppend = Notification.Name("TsukiDebugLogDidAppend")

    let directory: URL
    let fileURL: URL
    let previousURL: URL
    private let queue = DispatchQueue(label: "date.arcueid.tsukirebuild.log")
    private var handle: FileHandle?
    private let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let maxBytes = 2_000_000

    private init() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("Logs", isDirectory: true)
        fileURL = directory.appendingPathComponent("debug.log")
        previousURL = directory.appendingPathComponent("debug.previous.log")
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // One file per stretch of use: past 2 MB the log becomes the "previous" one and a new one starts.
        if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > DebugLog.maxBytes {
            try? fm.removeItem(at: previousURL)
            try? fm.moveItem(at: fileURL, to: previousURL)
        }
        if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
    }

    func log(_ category: String, _ message: String) {
        let now = Date()
        queue.async {
            let line = "\(self.stamp.string(from: now)) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            try? self.handle?.write(contentsOf: data)
            FileHandle.standardError.write(data)   // `simctl launch --console` and CI see it too
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: DebugLog.didAppend, object: nil) }
    }

    /// Everything written so far is on disk when this returns.
    func flush() {
        queue.sync { try? self.handle?.synchronize() }
    }

    /// The end of the log, for the viewer.
    func tail(maxBytes: Int = 300_000) -> String {
        flush()
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return "" }
        let slice = data.count > maxBytes ? data.suffix(maxBytes) : data
        return String(decoding: slice, as: UTF8.self)
    }

    /// The files worth sharing: both logs and the probe's last result.
    func shareableFiles() -> [URL] {
        flush()
        let fm = FileManager.default
        return [fileURL, previousURL, ProbeStore.resultURL].filter { fm.fileExists(atPath: $0.path) }
    }
}

func tlog(_ category: String, _ message: String) {
    DebugLog.shared.log(category, message)
}

/// The compat probe's last result, kept beside the log so that it can be shared and CI can pick it up.
enum ProbeStore {
    static var resultURL: URL { DebugLog.shared.directory.appendingPathComponent("probe-result.json") }

    static func save(_ result: Any) {
        var doc: [String: Any] = ["device": DeviceInfo.snapshot(), "savedAt": ISO8601DateFormatter().string(from: Date())]
        doc["probe"] = result
        guard JSONSerialization.isValidJSONObject(doc),
              let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) else {
            tlog("probe", "result could not be written as JSON")
            return
        }
        do {
            try data.write(to: resultURL, options: .atomic)
            tlog("probe", "result saved: \(resultURL.lastPathComponent), \(data.count) bytes")
        } catch {
            tlog("probe", "result not saved: \(error.localizedDescription)")
        }
    }
}
