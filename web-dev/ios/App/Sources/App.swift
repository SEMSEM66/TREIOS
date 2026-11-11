import AVFoundation
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        tlog("app", "launch, version \(Config.version), commit \(Config.gitCommit), debug UI \(Config.debugUI)")
        DeviceInfo.logHeader()
        AssetStore.prepareDirectories()
        tlog("assets", AssetStore.summary())
        AudioSession.configure()
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            tlog("memory", "memory warning: \(DeviceInfo.memorySummary())")
        }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            tlog("device", "thermal state \(ProcessInfo.processInfo.thermalState.rawValue) (0 nominal, 1 fair, 2 serious, 3 critical)")
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .landscape
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) { tlog("life", "active") }
    func sceneWillResignActive(_ scene: UIScene) { tlog("life", "will resign active") }
    func sceneDidEnterBackground(_ scene: UIScene) { tlog("life", "background"); DebugLog.shared.flush() }
    func sceneWillEnterForeground(_ scene: UIScene) { tlog("life", "foreground") }
}

/// The game's sound must not stop for the ring/silent switch, and must come back after a call or an alarm.
enum AudioSession {
    static let interruptionEnded = Notification.Name("TsukiAudioInterruptionEnded")

    static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            tlog("audio", "session category playback; sample rate \(session.sampleRate), output \(AudioSession.describeRoute(session))")
        } catch {
            tlog("audio", "could not set the playback category: \(error.localizedDescription)")
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            if AVAudioSession.InterruptionType(rawValue: raw) == .began {
                tlog("audio", "interruption began")
            } else {
                let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                tlog("audio", "interruption ended, should resume: \(options.contains(.shouldResume))")
                try? AVAudioSession.sharedInstance().setActive(true)
                nc.post(name: AudioSession.interruptionEnded, object: nil)
            }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            tlog("audio", "route change (reason \(reason)): \(AudioSession.describeRoute(AVAudioSession.sharedInstance()))")
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            tlog("audio", "media services were reset")
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            nc.post(name: AudioSession.interruptionEnded, object: nil)
        }
    }

    static func describeRoute(_ session: AVAudioSession) -> String {
        let outs = session.currentRoute.outputs.map { "\($0.portType.rawValue)" }
        return outs.isEmpty ? "none" : outs.joined(separator: "+")
    }
}

/// Holds whichever screen is up: the asset download, the game, or the compat probe.
final class RootViewController: UIViewController {
    private var current: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        route()
    }

    func route() {
        if Config.probeAtLaunch {
            show(GameViewController(mode: .probe))
        } else if AssetStore.isReady || Config.devURL != nil {
            show(GameViewController(mode: .game))
        } else {
            show(DownloadViewController { [weak self] in self?.route() })
        }
    }

    func show(_ controller: UIViewController) {
        if let old = current {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        current = controller
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        tlog("app", "showing \(type(of: controller))")
    }

    func showProbe() { show(GameViewController(mode: .probe)) }

    override var childForStatusBarHidden: UIViewController? { current }
    override var childForHomeIndicatorAutoHidden: UIViewController? { current }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { current }
    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}
