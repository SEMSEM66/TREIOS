import UIKit
import WebKit

/// The game: web/app in a full-screen WKWebView at app://tsukihime.ios/, as upstream's MainActivity.java is for Android.
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
        installWebView()
        observeLifecycle()
        startSnapshots()
        scheduleTests()
        load()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true   // the screen stays on, as in upstream's Android app
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

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let i = view.safeAreaInsets
        tlog("layout", "view \(Int(view.bounds.width))x\(Int(view.bounds.height)), safe area top \(i.top) left \(i.left) bottom \(i.bottom) right \(i.right)")
        tellSafeArea()
    }

    /// The view's safe area, told to the page (bridge.js setSafeArea): WebKit's own env(safe-area-inset-*) reaches the
    /// page late now and then, and once in CI not at all. Points here are CSS pixels there.
    private func tellSafeArea() {
        guard isViewLoaded, webView != nil else { return }
        let i = view.safeAreaInsets
        webView.evaluateJavaScript("window.__tsukiBridge && __tsukiBridge.setSafeArea(\(i.top), \(i.right), \(i.bottom), \(i.left))", completionHandler: nil)
    }

    // MARK: - Tests of what cannot be asked for from outside

    /// Ends the page's WebKit process as iOS does when memory runs short, to try the recovery (the automatic save made
    /// at the memory warning, the reload, the way back to the newest save). From the debug menu, and in CI.
    private func endPageProcess() {
        let kill = Selector(("_killWebContentProcess"))
        guard webView.responds(to: kill) else {
            tlog("test", "this WebKit cannot end its page's process on request")
            return
        }
        tlog("test", "ending the page's process on purpose")
        webView.perform(kill)
    }

    /// CI: `-TsukiTestMemoryWarningAt`, `-TsukiTestEndPageAt` and `-TsukiQuitAfter`, seconds after the launch. A runner
    /// has no graphics card and is too busy to be asked for anything while the game draws, so the app does these itself.
    private func scheduleTests() {
        let after = { (key: String, action: @escaping () -> Void) in
            let seconds = UserDefaults.standard.double(forKey: key)
            if seconds > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action) }
        }
        after("TsukiTestMemoryWarningAt") {
            tlog("test", "sending the app a memory warning")
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
        }
        after("TsukiTestEndPageAt") { [weak self] in self?.endPageProcess() }
        if let script = Config.string("TsukiTestEndPageInScript") { endPage(inScript: script, giveUpAt: Date().addingTimeInterval(95)) }
        if let script = Config.string("TsukiTestLoseContextInScript") { endPage(inScript: script, giveUpAt: Date().addingTimeInterval(95), loseContext: true) }
        after("TsukiQuitAfter") {
            tlog("test", "quitting, as the launch asked")
            SaveMirror.shared.flush()
            DebugLog.shared.flush()
            exit(0)
        }
    }

    /// CI: once the story is well into `script` (so that there is a checkpoint to save), a memory warning, and 8 s
    /// later the page's process is ended, or (`loseContext`) the game's WebGL context is taken away instead. A runner's
    /// speed varies too much for a fixed number of seconds.
    private func endPage(inScript script: String, giveUpAt: Date, loseContext: Bool = false) {
        let ask = "(() => { const v = window.vm; return v && v.running && v.script ? v.script.name + ':' + v.pc : ''; })()"
        webView.evaluateJavaScript(ask) { [weak self] result, _ in
            guard let self else { return }
            let at = result as? String ?? ""
            let parts = at.split(separator: ":")
            let there = parts.count == 2 && parts[0] == script && (Int(parts[1]) ?? 0) >= 40
            guard there || Date() > giveUpAt else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.endPage(inScript: script, giveUpAt: giveUpAt, loseContext: loseContext) }
                return
            }
            if loseContext {
                tlog("test", there ? "the story is at \(at): taking the game's WebGL context away" : "the story did not reach \(script) in time (it is at '\(at)'): taking the WebGL context away anyway")
                let lose = "(() => { const gl = window.gfx && window.gfx.gl, x = gl && gl.getExtension('WEBGL_lose_context'); if (!x) return 'no WEBGL_lose_context'; x.loseContext(); return 'lost'; })()"
                self.webView.evaluateJavaScript(lose) { result, error in
                    tlog("test", "loseContext -> \(result.map { "\($0)" } ?? error?.localizedDescription ?? "nil")")
                }
                return
            }
            tlog("test", there ? "the story is at \(at): sending the app a memory warning" : "the story did not reach \(script) in time (it is at '\(at)'): sending the memory warning anyway")
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.endPageProcess() }
        }
    }

    // MARK: - Pictures for CI (-TsukiSnapshotEvery seconds)

    private var snapshotTimer: Timer?
    private var snapshots = 0

    private func startSnapshots() {
        guard let every = Config.snapshotEvery else { return }
        let dir = DebugLog.shared.directory.deletingLastPathComponent().appendingPathComponent("Screens", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in self?.snapshot(into: dir) }
    }

    private func snapshot(into dir: URL) {
        guard UIApplication.shared.applicationState == .active else { return }
        snapshots += 1
        let stamp = DateFormatter()
        stamp.dateFormat = "HHmmss"
        let name = "\(mode == .probe ? "probe" : "game")-\(stamp.string(from: Date()))"
        // The page as WebKit paints it, asked for without waiting. (Drawing the view's own layers with
        // drawHierarchy waits for the system's renderer: on a runner it once held the app for two minutes.)
        guard !snapshotUnderWay else { return }
        snapshotUnderWay = true
        webView.takeSnapshot(with: nil) { [weak self] image, error in
            self?.snapshotUnderWay = false
            if let data = image?.jpegData(compressionQuality: 0.8) {
                try? data.write(to: dir.appendingPathComponent("\(name)-web.jpg"))
            } else {
                tlog("snapshot", "\(name): \(error?.localizedDescription ?? "no picture")")
            }
        }
    }
    private var snapshotUnderWay = false

    // MARK: - The web view

    private let gestureDelegate = SimultaneousGestures()

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: Config.scheme)
        config.websiteDataStore = .default()   // the saves are the page's localStorage, kept on disk
        // Movies play in the page, not in the system's player, and sound needs no first tap (the site's opening page
        // is that tap in a browser; the app has none, like upstream's Android and desktop apps).
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
            "ci": Config.autopilot || Config.snapshotEvery != nil,
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
        let url = startURL
        resumeOnLoad = false   // (a later reload from the debug menu is a plain one)
        load(url, attempt: 1)
    }

    /// The load that has been asked for and has not finished: its address and which try this is.
    private var pending: (url: URL, attempt: Int, serial: Int)?

    /// Loads the page and makes sure it arrives. WebKit can drop a load without a word (seen in CI on iOS 18.6: the
    /// reload that follows an ended page process never came back, and no delegate method was called). A load that
    /// has not finished in 20 s is asked for again, the third time in a web view made new.
    private func load(_ url: URL, attempt: Int) {
        pageLoads += 1
        let serial = pageLoads
        pending = (url, attempt, serial)
        if attempt >= 3 {
            tlog("web", "making the web view again")
            installWebView()
        }
        tlog("web", "loading \(url.absoluteString) (load #\(serial)\(attempt > 1 ? ", try \(attempt)" : ""))")
        // The user scripts are made once per web view; the save mirror they carry is only read by a page whose storage is empty.
        webView.load(URLRequest(url: url))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let p = self.pending, p.serial == serial else { return }
            guard UIApplication.shared.applicationState == .active else { self.reloadWhenActive = true; return }
            if attempt >= 4 {
                tlog("web", "the page did not load after \(attempt) tries")
                self.pending = nil
                self.showMessage("The game's page did not load. Reload tries again.")
                return
            }
            tlog("web", "load #\(serial) has not finished after 20 s: asking again")
            self.load(p.url, attempt: attempt + 1)
        }
    }

    /// Puts a web view in the view, in place of the one before it if there was one.
    private func installWebView() {
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "tsuki")
        webView?.removeFromSuperview()
        webView = makeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(webView, at: 0)
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
        pending = nil
        tellSafeArea()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tlog("web", "page arriving: \(webView.url?.absoluteString ?? "?")")
        tellSafeArea()   // (the bridge is in the page from its first moment)
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
        // Not from inside this call: WebKit is still clearing the ended process away, and a load asked for now can be lost.
        if UIApplication.shared.applicationState == .active {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reloadAfterTermination() }
        } else {
            reloadWhenActive = true
        }
    }

    /// The page is alive but the game in it is not (bridge.js: its WebGL context was lost, or it never started). The
    /// automatic save is made if the game can still make one, and the page is loaded again at the newest save. Counted
    /// with the ended processes: three in a minute, and the app stops and says so.
    private func reloadBrokenPage() {
        let now = Date()
        terminations = terminations.filter { now.timeIntervalSince($0) < 60 } + [now]
        tlog("webkit", "the page asked to be loaded again (\(terminations.count) reloads in the last minute); \(DeviceInfo.memorySummary())")
        if terminations.count > 3 {
            tlog("webkit", "not reloading again: it keeps failing")
            showMessage("The game keeps stopping on this iPhone. Close other apps and open the game again; the debug log says what happened.")
            return
        }
        webView.evaluateJavaScript("globalThis.appSuspend ? (globalThis.appSuspend(), 'saved') : 'no appSuspend'") { [weak self] result, error in
            tlog("webkit", "before the reload: appSuspend -> \(result.map { "\($0)" } ?? error?.localizedDescription ?? "nil")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.reloadAfterTermination() }
        }
    }

    private func reloadAfterTermination() {
        reloadWhenActive = false
        if let p = pending { load(p.url, attempt: p.attempt + 1); return }   // a load was under way: that one again
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
    /// upstream's Android app asks for it in onStop. iOS may end a backgrounded app without another word.
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
        case "caps":
            if let av1 = body["av1"] as? Bool { SchemeHandler.av1Plays = av1 }
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
        case "broken": reloadBrokenPage()
        case "no-opus":
            let alert = UIAlertController(title: "No sound on this version of iOS",
                                          message: "This iPhone's iOS (\(UIDevice.current.systemVersion)) cannot decode Ogg Opus, which all of the game's voices, music and sounds are. The game will play silently. A newer iOS may decode it; the debug log has the details.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
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
            menu.addAction(UIAlertAction(title: "Test: end the page's process", style: .destructive) { [weak self] _ in self?.endPageProcess() })
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
