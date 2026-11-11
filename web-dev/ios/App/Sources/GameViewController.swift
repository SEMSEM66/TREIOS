import UIKit
import WebKit

/// The game: web/app in a full-screen WKWebView at app://tsukihime.ios/, as MainActivity.java is for Android.
/// The same class shows the compat probe (mode .probe), which is a page of this app served the same way.
final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    enum Mode { case game, probe }

    private let mode: Mode
    private let handler = SchemeHandler()
    private var webView: WKWebView!
    private var observers: [NSObjectProtocol] = []
    private var terminations: [Date] = []
    private var reloadWhenActive = false
    private var pageLoads = 0

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("no storyboard") }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // Landscape, nothing of the system on screen, and its edge swipes asked to wait for a second swipe: the game has
    // swipes of its own from the top and the bottom.
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        webView = makeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        // Edge to edge, under the Dynamic Island and the home indicator: the page reads the safe area itself
        // (viewport-fit=cover and env(safe-area-inset-*), touch.css).
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        if Config.debugUI {
            // Three fingers, two taps: the debug menu. (A shake opens it too.)
            let tap = UITapGestureRecognizer(target: self, action: #selector(openDebugMenu))
            tap.numberOfTouchesRequired = 3
            tap.numberOfTapsRequired = 2
            tap.cancelsTouchesInView = false
            tap.delegate = gestureDelegate
            webView.addGestureRecognizer(tap)
        }
        observeLifecycle()
        load()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true   // the screen stays on, as on Android
        becomeFirstResponder()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if parent == nil { UIApplication.shared.isIdleTimerDisabled = false }
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake, Config.debugUI { openDebugMenu() }
    }

    // MARK: - The web view

    private let gestureDelegate = SimultaneousGestures()

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: Config.scheme)
        config.websiteDataStore = .default()   // the saves are the page's localStorage, kept on disk
        // Movies play in the page, not in the system's player, and sound needs no first tap (the site's opening page
        // is that tap in a browser; the app has none, like the Android and desktop apps).
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        config.preferences.isTextInteractionEnabled = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.applicationNameForUserAgent = "TsukihimeiOS"

        let content = config.userContentController
        content.add(WeakScriptMessageHandler(self), name: "tsuki")
        content.addUserScript(WKUserScript(source: nativeScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let bridgeURL = Bundle.main.bundleURL.appendingPathComponent("native/bridge.js")
        if let bridge = try? String(contentsOf: bridgeURL, encoding: .utf8) {
            content.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        } else {
            tlog("app", "bridge.js is missing from the bundle")
        }

        let web = WKWebView(frame: view.bounds, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.isInspectable = Config.debugUI   // Safari's Web Inspector, for whoever has a Mac
        return web
    }

    /// What the page is told about the app before any of its own code runs (bridge.js reads it).
    private func nativeScript() -> String {
        var info: [String: Any] = [
            "platform": "ios",
            "mode": mode == .probe ? "probe" : "game",
            "debug": Config.debugUI,
            "autopilot": Config.autopilot,
            "assetsReady": AssetStore.isReady,
            "device": DeviceInfo.snapshot(),
        ]
        if mode == .game, let saved = SaveMirror.shared.itemsForRestore() { info["saveMirror"] = saved }
        info["hasSaveMirror"] = SaveMirror.shared.hasItems
        let json = (try? JSONSerialization.data(withJSONObject: info)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "window.__tsukiNative = \(json);"
    }

    private var startURL: URL {
        if mode == .probe { return URL(string: "\(Config.origin)/__native/probe.html")! }
        var address = Config.devURL ?? "\(Config.origin)/"
        var query: [String] = []
        if let q = Config.startQuery { query.append(q) }
        if resumeOnLoad { query.append("resume") }
        if !query.isEmpty { address += (address.contains("?") ? "&" : "?") + query.joined(separator: "&") }
        return URL(string: address) ?? URL(string: "\(Config.origin)/")!
    }
    /// Set for the load that follows an ended content process: the page goes straight to the newest save.
    private var resumeOnLoad = false

    private func load() {
        pageLoads += 1
        let url = startURL
        tlog("web", "loading \(url.absoluteString) (load #\(pageLoads))")
        // The user scripts are made once; the save mirror they carry is only read by a page whose storage is empty.
        webView.load(URLRequest(url: url))
    }

    // MARK: - Navigation

    private func isOwn(_ url: URL) -> Bool {
        if url.scheme == Config.scheme && url.host == Config.host { return true }
        if let scheme = url.scheme, ["about", "blob", "data"].contains(scheme) { return true }
        if let dev = Config.devURL, let d = URL(string: dev), d.host == url.host, d.port == url.port { return true }
        return false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if isOwn(url) { decisionHandler(.allow); return }
        // Nothing but the game loads here. A link the player tapped opens in the browser.
        tlog("web", "blocked navigation to \(url.absoluteString)")
        if navigationAction.navigationType == .linkActivated, url.scheme == "https" || url.scheme == "http" {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tlog("web", "page loaded: \(webView.url?.absoluteString ?? "?")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tlog("web", "navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        tlog("web", "page could not be loaded: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        tlog("web", "alert: \(message)")
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        tlog("web", "confirm: \(message)")
        completionHandler(true)
    }

    /// iOS ends the page's process when memory runs short (and WebKit itself can crash). The view is then blank:
    /// load the page again, and have it go straight to the newest save.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let now = Date()
        terminations = terminations.filter { now.timeIntervalSince($0) < 60 } + [now]
        tlog("webkit", "content process ended (\(terminations.count) in the last minute); \(DeviceInfo.memorySummary())")
        if terminations.count > 3 {
            tlog("webkit", "not reloading again: it keeps ending")
            showMessage("The game's page keeps being ended by iOS. Close other apps and open the game again.")
            return
        }
        if UIApplication.shared.applicationState == .active { reloadAfterTermination() } else { reloadWhenActive = true }
    }

    private func reloadAfterTermination() {
        reloadWhenActive = false
        resumeOnLoad = mode == .game
        load()
    }

    // MARK: - Lifecycle

    private func observeLifecycle() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend(background: false)
        })
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend(background: true)
        })
        observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        })
        observers.append(nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            // The warning often comes shortly before the page's process is ended: make the automatic save now.
            self?.run("globalThis.appSuspend && (globalThis.appSuspend(), 'saved')", label: "memory warning: appSuspend")
        })
        observers.append(nc.addObserver(forName: AudioSession.interruptionEnded, object: nil, queue: .main) { [weak self] _ in
            self?.run("globalThis.__tsukiBridge && __tsukiBridge.resumeAudio()", label: "audio resume")
        })
    }

    /// Leaving the foreground: the page makes the automatic save that `pagehide` would make (main.js appSuspend), as
    /// the Android app asks for it in onStop. iOS may end a backgrounded app without another word.
    private func suspend(background: Bool) {
        guard mode == .game else { return }
        var task = UIBackgroundTaskIdentifier.invalid
        if background {
            task = UIApplication.shared.beginBackgroundTask(withName: "autosave") {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
        }
        webView.evaluateJavaScript("globalThis.appSuspend ? (globalThis.appSuspend(), 'saved') : 'no appSuspend yet'") { result, error in
            tlog("life", "\(background ? "background" : "resign active"): appSuspend -> \(result.map { "\($0)" } ?? error?.localizedDescription ?? "nil")")
            // The save reaches the mirror as messages from the page; give them a moment, then write the file.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SaveMirror.shared.flush()
                DebugLog.shared.flush()
                if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
            }
        }
    }

    private func resume() {
        becomeFirstResponder()
        if reloadWhenActive { reloadAfterTermination(); return }
        run("globalThis.__tsukiBridge && __tsukiBridge.resumeAudio()", label: nil)
    }

    private func run(_ script: String, label: String?) {
        webView.evaluateJavaScript(script) { result, error in
            guard let label else { return }
            tlog("life", "\(label) -> \(result.map { "\($0)" } ?? error?.localizedDescription ?? "nil")")
        }
    }

    // MARK: - Messages from the page (bridge.js)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["t"] as? String else { return }
        switch type {
        case "log":
            tlog("js:\(body["level"] as? String ?? "log")", body["msg"] as? String ?? "")
        case "saves":
            SaveMirror.shared.handle(body)
        case "probe":
            if let result = body["result"] { ProbeStore.save(result) }
        case "action":
            handleAction(body["name"] as? String ?? "")
        default:
            tlog("js", "unknown message \(type)")
        }
    }

    private func handleAction(_ name: String) {
        switch name {
        case "share": shareLogs()
        case "log": showLog()
        case "menu": openDebugMenu()
        case "close-probe": (parent as? RootViewController)?.route()
        default: tlog("js", "unknown action \(name)")
        }
    }

    // MARK: - Debug menu

    @objc private func openDebugMenu() {
        guard presentedViewController == nil else { return }
        let menu = UIAlertController(title: "Tsukihime \(Config.version)", message: "\(DeviceInfo.modelName), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)", preferredStyle: .alert)
        menu.addAction(UIAlertAction(title: "Debug log", style: .default) { [weak self] _ in self?.showLog() })
        menu.addAction(UIAlertAction(title: "Share debug log", style: .default) { [weak self] _ in self?.shareLogs() })
        if mode == .game {
            menu.addAction(UIAlertAction(title: "Compat probe", style: .default) { [weak self] _ in (self?.parent as? RootViewController)?.showProbe() })
            menu.addAction(UIAlertAction(title: "Game files", style: .default) { [weak self] _ in (self?.parent as? RootViewController)?.showFiles() })
            menu.addAction(UIAlertAction(title: "Reload the game", style: .default) { [weak self] _ in
                tlog("app", "reload asked for from the debug menu")
                self?.load()
            })
        } else {
            menu.addAction(UIAlertAction(title: "Back to the game", style: .default) { [weak self] _ in (self?.parent as? RootViewController)?.route() })
        }
        menu.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(menu, animated: true)
    }

    private func showLog() {
        let viewer = UINavigationController(rootViewController: LogViewController())
        viewer.modalPresentationStyle = .fullScreen
        present(viewer, animated: true)
    }

    private func shareLogs() {
        let files = DebugLog.shared.shareableFiles()
        let sheet = UIActivityViewController(activityItems: files, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(sheet, animated: true)
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reload", style: .default) { [weak self] _ in
            self?.terminations.removeAll()
            self?.reloadAfterTermination()
        })
        alert.addAction(UIAlertAction(title: "Debug log", style: .default) { [weak self] _ in self?.showLog() })
        present(alert, animated: true)
    }
}

/// WKUserContentController keeps its message handlers alive; this keeps the view controller out of that.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Lets the debug menu's tap be recognised alongside the page's own touch handling.
final class SimultaneousGestures: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

/// The debug log on screen, with a button that shares the files.
final class LogViewController: UIViewController {
    private let text = UITextView()
    private var observer: NSObjectProtocol?
    private var pending = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Debug log"
        view.backgroundColor = .black
        text.isEditable = false
        text.backgroundColor = .black
        text.textColor = UIColor(white: 0.85, alpha: 1)
        text.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            text.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share)),
            UIBarButtonItem(title: "Copy", style: .plain, target: self, action: #selector(copyAll)),
        ]
        refresh()
        observer = NotificationCenter.default.addObserver(forName: DebugLog.didAppend, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.pending else { return }
            self.pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.pending = false; self.refresh() }
        }
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    private func refresh() {
        let atEnd = text.contentOffset.y >= text.contentSize.height - text.bounds.height - 40
        text.text = DebugLog.shared.tail()
        if atEnd || text.contentOffset.y == 0 {
            text.layoutIfNeeded()
            text.scrollRangeToVisible(NSRange(location: max(0, (text.text as NSString).length - 1), length: 1))
        }
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func copyAll() { UIPasteboard.general.string = DebugLog.shared.tail(maxBytes: 2_000_000) }
    @objc private func share() {
        let sheet = UIActivityViewController(activityItems: DebugLog.shared.shareableFiles(), applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(sheet, animated: true)
    }
}
