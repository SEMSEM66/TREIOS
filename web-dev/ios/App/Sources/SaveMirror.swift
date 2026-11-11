import Foundation

/// A copy of the page's localStorage (the saves, settings, read marks and unlocks) in Documents/Saves, which the
/// Files app shows. The page reports every change through bridge.js; a page that starts with empty storage and
/// finds a mirror takes the mirror. So the saves outlive WebKit clearing its website data, and the file can be
/// copied off the phone and back.
final class SaveMirror {
    static let shared = SaveMirror()

    let fileURL: URL
    private var items: [String: String] = [:]
    private var dirty = false
    private var writeScheduled = false
    private let queue = DispatchQueue(label: "date.arcueid.tsukirebuild.saves")

    private init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Saves", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("localStorage.json")
        if let data = try? Data(contentsOf: fileURL),
           let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let stored = doc["items"] as? [String: String] {
            items = stored
        }
        tlog("saves", "mirror: \(items.count) keys, \(items.values.reduce(0) { $0 + $1.utf8.count }) bytes")
    }

    var hasItems: Bool { queue.sync { !items.isEmpty } }

    /// The mirror for a page to restore from, or nil when there is nothing to restore.
    func itemsForRestore() -> [String: String]? {
        queue.sync { items.isEmpty ? nil : items }
    }

    /// A message from the page: { op: "set", k, v } | { op: "remove", k } | { op: "clear" } | { op: "snapshot", items } |
    /// { op: "restored", count }.
    func handle(_ body: [String: Any]) {
        let op = body["op"] as? String ?? ""
        switch op {
        case "set":
            guard let k = body["k"] as? String, let v = body["v"] as? String else { return }
            queue.sync { items[k] = v; dirty = true }
        case "remove":
            guard let k = body["k"] as? String else { return }
            queue.sync { items[k] = nil; dirty = true }
        case "clear":
            queue.sync { items.removeAll(); dirty = true }
            tlog("saves", "the page cleared its storage")
        case "snapshot":
            guard let all = body["items"] as? [String: String] else { return }
            queue.sync { items = all; dirty = true }
            tlog("saves", "snapshot from the page: \(all.count) keys")
        case "restored":
            tlog("saves", "the page's storage was empty: restored \(body["count"] ?? 0) keys from the mirror")
            return
        default:
            return
        }
        scheduleWrite()
    }

    private func scheduleWrite() {
        queue.sync {
            guard !writeScheduled else { return }
            writeScheduled = true
            queue.asyncAfter(deadline: .now() + 1) { [self] in
                writeScheduled = false
                writeLocked()
            }
        }
    }

    /// Writes the file now if anything changed (going to the background).
    func flush() {
        queue.sync { writeLocked() }
    }

    private func writeLocked() {
        guard dirty else { return }
        let doc: [String: Any] = ["version": 1, "updated": ISO8601DateFormatter().string(from: Date()), "items": items]
        do {
            let data = try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            dirty = false
        } catch {
            tlog("saves", "mirror not written: \(error.localizedDescription)")
        }
    }
}
