import Foundation

/// Where the game's files live on the phone, and what is known about them.
///
/// Library/Application Support/assets holds web/assets as the page asks for it. It is excluded from iCloud and
/// computer backups (the files can be downloaded again), it is not shown in the Files app, and iOS keeps it across
/// updates and re-signing for as long as the bundle ID stays the same.
enum AssetStore {
    struct State: Codable {
        var indexID: String
        var doneParts: [String]      // SHA-256 of every part that has been verified and extracted
        var complete: Bool
        var totalBytes: Int64
        var fileCount: Int
        var source: String
        var completedAt: Date?
    }

    static let supportDir: URL = {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A launch can point the app at a folder of the Mac instead (the simulator in CI, with the repository's web/assets).
    static var isOverridden: Bool { Config.assetsDirOverride != nil }
    static var assetsDir: URL {
        if let dir = Config.assetsDirOverride { return URL(fileURLWithPath: dir, isDirectory: true) }
        return supportDir.appendingPathComponent("assets", isDirectory: true)
    }
    /// Parts on their way in. Beside the assets, so a finished part is moved, not copied.
    static var downloadsDir: URL { supportDir.appendingPathComponent("asset-downloads", isDirectory: true) }
    private static var stateURL: URL { supportDir.appendingPathComponent("assets-state.json") }

    static func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(State.self, from: data)
    }

    static func save(_ state: State) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// The game can start: every part is in, and the file the page reads first is there.
    static var isReady: Bool {
        let fm = FileManager.default
        if isOverridden { return fm.fileExists(atPath: assetsDir.appendingPathComponent("system.json").path) }
        guard let state = loadState(), state.complete else { return false }
        return fm.fileExists(atPath: assetsDir.appendingPathComponent("system.json").path)
    }

    static func prepareDirectories() {
        let fm = FileManager.default
        for dir in [assetsDir, downloadsDir] where !isOverridden || dir == downloadsDir {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            excludeFromBackup(dir)
        }
    }

    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do { try url.setResourceValues(values) } catch { tlog("assets", "could not exclude \(url.lastPathComponent) from backup: \(error.localizedDescription)") }
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }

    /// Removes the downloaded game (not the saves, which are the page's own storage and its mirror in Documents).
    static func removeAll() {
        guard !isOverridden else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: assetsDir)
        try? fm.removeItem(at: downloadsDir)
        try? fm.removeItem(at: stateURL)
        tlog("assets", "removed the downloaded assets")
    }

    static func summary() -> String {
        if isOverridden { return "assets from \(assetsDir.path) (launch argument), ready=\(isReady)" }
        guard let s = loadState() else { return "no assets installed" }
        return "assets index \(s.indexID.prefix(12)), parts done \(s.doneParts.count), complete=\(s.complete), files \(s.fileCount), bytes \(s.totalBytes), excluded from backup=\(isExcludedFromBackup(assetsDir))"
    }
}
