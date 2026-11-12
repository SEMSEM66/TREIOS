import Foundation

/// The app's fixed names, and the switches a launch can set. A launch argument `-TsukiName value` lands in
/// UserDefaults' argument domain, which is how CI and `simctl launch` set them; nothing here needs a rebuild.
enum Config {
    /// The page's address, as upstream's desktop app has `app://tsukihime.desktop/`. It never reaches the network: every request
    /// to it is answered by SchemeHandler. `web/app/js/home.js` knows the host, so the app opens on the game itself.
    static let scheme = "app"
    static let host = "tsukihime.ios"
    static var origin: String { "\(scheme)://\(host)" }
    static let bundleID = Bundle.main.bundleIdentifier ?? "date.arcueid.tsukirebuild"

    private static var defaults: UserDefaults { .standard }

    static func string(_ key: String) -> String? {
        guard let v = defaults.string(forKey: key), !v.isEmpty else { return nil }
        return v
    }
    static func flag(_ key: String) -> Bool { defaults.bool(forKey: key) }

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    /// The debug menu and log viewer: on when the build set TSUKI_DEBUG_UI=YES, or for one launch with `-TsukiDebugUI 1`.
    static var debugUI: Bool { info("TsukiDebugUI").uppercased() == "YES" || flag("TsukiDebugUI") }
    static var gitCommit: String { info("TsukiGitCommit") }
    static var version: String { "\(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))" }

    /// Where the asset packs are fetched from: the folder that holds `index.json` and the parts. The build writes a default
    /// into Info.plist; the download screen can change it, and `-TsukiAssetURL` overrides both for one launch.
    static var builtInAssetURL: String { info("TsukiAssetURL") }
    private static let assetURLKey = "TsukiAssetURL"
    static var assetURL: String {
        get { string(assetURLKey) ?? builtInAssetURL }
        set {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty || v == builtInAssetURL { defaults.removeObject(forKey: assetURLKey) } else { defaults.set(v, forKey: assetURLKey) }
        }
    }
    private static let cellularKey = "TsukiAllowCellular"
    static var allowCellular: Bool {
        get { flag(cellularKey) }
        set { defaults.set(newValue, forKey: cellularKey) }
    }

    // For CI and development (launch arguments only).
    /// Serve /assets from this folder instead of the downloaded one (a simulator can read the Mac's files).
    static var assetsDirOverride: String? { string("TsukiAssetsDir") }
    /// Load the page from this address instead of the bundled one (web/server.py on the Mac).
    static var devURL: String? { string("TsukiDevURL") }
    /// A query for the game's page, for example `script=00_02&mute`.
    static var startQuery: String? { string("TsukiStartQuery") }
    static var probeAtLaunch: Bool { flag("TsukiProbe") }
    static var autoDownload: Bool { flag("TsukiAutoDownload") }
    static var autopilot: Bool { flag("TsukiAutopilot") }
    /// A picture of the web view into Documents/Screens every so many seconds (CI: `simctl io screenshot` stalls while
    /// the game draws on a runner with no graphics card).
    static var snapshotEvery: Double? {
        let seconds = defaults.double(forKey: "TsukiSnapshotEvery")
        return seconds > 0 ? seconds : nil
    }
}
