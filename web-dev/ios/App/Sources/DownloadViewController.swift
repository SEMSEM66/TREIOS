import UIKit

/// The first screen of a fresh install: the game's files are fetched once, then the game starts and needs no
/// connection again. Also where the source address is set, and a way to the debug log and the compat probe before
/// there is a game to open them from.
final class DownloadViewController: UIViewController {
    private let onReady: () -> Void
    private let downloader = AssetDownloader()

    private let titleLabel = UILabel()
    private let infoLabel = UILabel()
    private let bar = UIProgressView(progressViewStyle: .default)
    private let statusLabel = UILabel()
    private let mainButton = UIButton(configuration: .filled())
    private let cellularSwitch = UISwitch()
    private var indexBytes: Int64?
    private var autoStarted = false

    init(onReady: @escaping () -> Void) {
        self.onReady = onReady
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("no storyboard") }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    // MARK: - Layout

    private func button(_ title: String, _ action: Selector) -> UIButton {
        var c = UIButton.Configuration.gray()
        c.title = title
        c.buttonSize = .small
        let b = UIButton(configuration: c)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        titleLabel.text = "Tsukihime"
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .white

        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = UIColor(white: 0.8, alpha: 1)
        infoLabel.numberOfLines = 0

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 2
        statusLabel.accessibilityIdentifier = "download-status"

        mainButton.addTarget(self, action: #selector(mainTapped), for: .touchUpInside)
        mainButton.accessibilityIdentifier = "download-main"

        let cellularLabel = UILabel()
        cellularLabel.text = "Allow mobile data"
        cellularLabel.font = .systemFont(ofSize: 13)
        cellularLabel.textColor = UIColor(white: 0.8, alpha: 1)
        cellularSwitch.isOn = Config.allowCellular
        cellularSwitch.addTarget(self, action: #selector(cellularChanged), for: .valueChanged)
        let cellularRow = UIStackView(arrangedSubviews: [cellularLabel, cellularSwitch])
        cellularRow.spacing = 10
        cellularRow.alignment = .center

        let mainRow = UIStackView(arrangedSubviews: [mainButton, UIView(), cellularRow])
        mainRow.spacing = 12
        mainRow.alignment = .center

        let extras = UIStackView(arrangedSubviews: [button("Source", #selector(editSource)), button("Compat probe", #selector(openProbe)),
                                                    button("Debug log", #selector(openLog)), UIView()])
        if AssetStore.isReady {
            // Opened from the game's debug menu: the files are here, and the game can go on with them as they are.
            extras.insertArrangedSubview(button("Play", #selector(play)), at: 0)
            extras.addArrangedSubview(button("Delete the files", #selector(deleteFiles)))
        }
        extras.spacing = 10

        let column = UIStackView(arrangedSubviews: [titleLabel, infoLabel, bar, statusLabel, mainRow, extras])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        let guide = view.safeAreaLayoutGuide
        let width = column.widthAnchor.constraint(equalToConstant: 600)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -16),
            column.topAnchor.constraint(greaterThanOrEqualTo: guide.topAnchor, constant: 8),
            width,
        ])

        downloader.onProgress = { [weak self] p in self?.show(p) }
        show(downloader.progress)
        describe()
        peek()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true   // a long download must not be cut by the screen locking
        if Config.autoDownload, !autoStarted {
            autoStarted = true
            downloader.start()
        }
    }

    // MARK: - What is shown

    private static func size(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000 ? String(format: "%.2f GB", Double(bytes) / 1e9) : String(format: "%.0f MB", Double(bytes) / 1e6)
    }

    private func describe() {
        var lines = ["The game's files are downloaded once, over Wi-Fi. After that the game plays with no connection."]
        var facts: [String] = []
        if let bytes = indexBytes { facts.append("Download: \(DownloadViewController.size(bytes))") }
        if let free = DeviceInfo.freeDisk() { facts.append("Free on this iPhone: \(DownloadViewController.size(free))") }
        if !facts.isEmpty { lines.append(facts.joined(separator: "   ")) }
        lines.append("Source: \(Config.assetURL.isEmpty ? "not set" : Config.assetURL)")
        infoLabel.text = lines.joined(separator: "\n")
    }

    private func peek() {
        downloader.peek { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let index):
                self.indexBytes = index.totalBytes
                self.describe()
                if let state = AssetStore.loadState(), state.complete, !self.downloader.isRunning {
                    self.statusLabel.text = state.indexID == index.id ? "The game's files are installed and up to date."
                        : "A newer set of files is published. Download fetches only the parts that changed."
                }
            case .failure(let error):
                tlog("download", "index.json could not be read yet: \(error.localizedDescription)")
                if !self.downloader.isRunning, self.downloader.progress.phase == .idle {
                    self.statusLabel.text = "The source could not be reached: \(error.localizedDescription)"
                }
            }
        }
    }

    private func show(_ p: AssetDownloader.Progress) {
        let fraction = p.bytesTotal > 0 ? Float(Double(p.bytesDone) / Double(p.bytesTotal)) : 0
        bar.setProgress(fraction, animated: false)
        let amount = p.bytesTotal > 0 ? "\(DownloadViewController.size(p.bytesDone)) of \(DownloadViewController.size(p.bytesTotal))" : ""
        let part = p.partCount > 0 ? "Part \(p.part) of \(p.partCount)" : ""
        var title = "Download"
        switch p.phase {
        case .idle:
            statusLabel.text = AssetStore.loadState().map { "\($0.doneParts.count) parts are already here." } ?? " "
            if let s = AssetStore.loadState(), !s.doneParts.isEmpty { title = "Resume" }
        case .index:
            statusLabel.text = "Reading the list of files..."
            title = "Pause"
        case .downloading:
            let rate = p.bytesPerSecond > 0 ? String(format: "   %.1f MB/s", p.bytesPerSecond / 1e6) : ""
            statusLabel.text = "\(part)   \(amount)\(rate)"
            title = "Pause"
        case .verifying:
            statusLabel.text = "\(part)   \(amount)   checking"
            title = "Pause"
        case .extracting:
            statusLabel.text = "\(part)   \(amount)   writing files"
            title = "Pause"
        case .waitingForNetwork:
            statusLabel.text = "Waiting for \(Config.allowCellular ? "a connection" : "Wi-Fi")...   \(amount)"
            title = "Pause"
        case .paused:
            statusLabel.text = "Paused.   \(amount)"
            title = "Resume"
        case .failed(let why):
            statusLabel.text = "Stopped: \(why)"
            title = "Try again"
        case .done:
            bar.setProgress(1, animated: false)
            if Config.flag("TsukiStayOnDownload") {   // (CI looks at the finished download before the game takes the runner)
                statusLabel.text = "Done."
                title = "Start"
                break
            }
            statusLabel.text = "Done. Starting the game..."
            title = "Start"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                UIApplication.shared.isIdleTimerDisabled = false
                self?.onReady()
            }
        }
        var c = mainButton.configuration ?? .filled()
        c.title = title
        mainButton.configuration = c
        mainButton.isEnabled = p.phase != .done
    }

    // MARK: - Actions

    @objc private func mainTapped() {
        if downloader.isRunning { downloader.pause() } else { downloader.start() }
    }

    @objc private func cellularChanged() {
        Config.allowCellular = cellularSwitch.isOn
        tlog("download", "mobile data \(cellularSwitch.isOn ? "allowed" : "not allowed")")
        // The setting belongs to the connection: a download under way is stopped, and goes on with the new one.
        if downloader.isRunning {
            downloader.pause()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.downloader.isRunning else { return }
                self.downloader.start()
            }
        }
    }

    @objc private func editSource() {
        let alert = UIAlertController(title: "Asset source", message: "The address of the folder that holds index.json and the parts.", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = Config.assetURL
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .always
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            Config.assetURL = alert?.textFields?.first?.text ?? ""
            tlog("download", "source set to \(Config.assetURL)")
            self?.describe()
            self?.peek()
        })
        alert.addAction(UIAlertAction(title: "Use the built-in one", style: .default) { [weak self] _ in
            Config.assetURL = ""
            self?.describe()
            self?.peek()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func play() {
        if downloader.isRunning { downloader.pause() }
        onReady()
    }

    @objc private func deleteFiles() {
        let alert = UIAlertController(title: "Delete the game's files?", message: "The saves are kept. The files have to be downloaded again before the game can be played.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.downloader.pause()
            AssetStore.removeAll()
            AssetStore.prepareDirectories()
            (self?.parent as? RootViewController)?.route()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func openProbe() {
        if downloader.isRunning { downloader.pause() }
        (parent as? RootViewController)?.showProbe()
    }

    @objc private func openLog() {
        let viewer = UINavigationController(rootViewController: LogViewController())
        viewer.modalPresentationStyle = .fullScreen
        present(viewer, animated: true)
    }
}
