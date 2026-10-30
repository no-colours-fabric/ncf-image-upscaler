import AppKit

/// Explicit model installation UI. Inference never invokes a downloader.
final class ModelSetupController: NSWindowController, NSWindowDelegate {
    private let message = NSTextField(wrappingLabelWithString: "Preparing NCF Image Upscaler…")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let download = NSButton(title: "Download Models", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel Download", target: nil, action: nil)
    private var task: WorkerTask?
    private var session: TemporarySession?
    private var available: Set<String> = []
    private var checked = false
    private var preparing = false
    private var completions: [() -> Void] = []
    private var failure: String?
    var isPreparing: Bool { preparing }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "NCF Image Upscaler Setup"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        let heading = NSTextField(labelWithString: "Local engine and models")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        message.font = .systemFont(ofSize: 13)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        progress.style = .bar
        progress.isIndeterminate = true
        download.target = self
        download.action = #selector(downloadModels)
        cancel.target = self
        cancel.action = #selector(cancelDownload)
        cancel.isHidden = true
        let buttons = NSStackView(views: [download, cancel])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let stack = NSStackView(views: [heading, message, detail, progress, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        download.isEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func prepare() {
        guard !preparing, task == nil else { return }
        preparing = true
        download.isEnabled = false
        message.stringValue = "Preparing the local engine…"
        detail.stringValue = "One-time setup on this Mac. No downloads are needed for the engine."
        progress.isHidden = false
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        do {
            let installer = try PortableRuntimeInstaller.bundled(resources: Bundle.main.resourceURL, data: AppPaths.data)
            if let installer, !installer.isInstalled { showWindow(nil) }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = Result { try installer?.install() }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.preparing = false
                    let waiting = self.completions
                    self.completions.removeAll()
                    if !waiting.isEmpty { waiting.forEach { $0() }; return }
                    switch result {
                    case .success: self.checkModels()
                    case .failure(let error): self.showFailure(error.localizedDescription)
                    }
                }
            }
        } catch {
            preparing = false
            showFailure(error.localizedDescription)
        }
    }

    func waitForPreparation(_ completion: @escaping () -> Void) {
        if preparing { completions.append(completion) }
        else { completion() }
    }

    func showSetup() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if !preparing && task == nil { prepare() }
    }

    func canEnhance(preset: String, scale: Int) -> Bool {
        let key = preset == "photo" ? (scale == 4 ? "x4plus" : "x2plus") : preset
        if checked && available.contains(key) && !preparing { return true }
        showSetup()
        return false
    }

    private func checkModels() {
        do {
            message.stringValue = "Checking installed models…"
            try start(download: false)
        } catch { showFailure(error.localizedDescription) }
    }

    @objc private func downloadModels() {
        guard !preparing, task == nil else { return }
        if checked && available.count == 4 { checkModels(); return }
        do {
            message.stringValue = "Downloading models…"
            detail.stringValue = "The download is verified before installation. You can cancel and retry."
            progress.isHidden = false
            progress.isIndeterminate = false
            progress.doubleValue = 0
            try start(download: true)
        } catch { showFailure(error.localizedDescription) }
    }

    @objc private func cancelDownload() { task?.cancel() }

    private func start(download downloading: Bool) throws {
        if session == nil { session = try TemporarySession() }
        let worker = WorkerTask(session: session!)
        task = worker
        failure = nil
        download.isEnabled = false
        cancel.isHidden = !downloading
        worker.onEvent = { [weak self] event in
            guard let self else { return }
            switch event["event"] as? String {
            case "model": self.message.stringValue = "Downloading: " + (event["title"] as? String ?? "model")
            case "progress":
                let done = event["completed"] as? Double ?? 0
                let total = event["total"] as? Double ?? 1
                self.progress.doubleValue = min(100, done / max(1, total) * 100)
            case "status":
                let models = event["models"] as? [[String: Any]] ?? []
                self.available = Set(models.filter { $0["installed"] as? Bool == true }.compactMap { $0["id"] as? String })
                self.checked = true
                let missing = models.filter { $0["installed"] as? Bool != true }
                let bytes = missing.reduce(0) { $0 + ($1["size"] as? Int ?? 0) }
                self.message.stringValue = missing.isEmpty ? "Ready for offline image processing." : "Download models to start enhancing images."
                self.detail.stringValue = missing.isEmpty
                    ? "Models and the engine are stored on this Mac."
                    : "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) remaining. Downloads start only when you choose Download Models. Processing works offline afterward."
                self.download.title = missing.isEmpty ? "Verify Again" : "Download Models"
                if !missing.isEmpty { self.showWindow(nil) }
            case "error": self.failure = event["message"] as? String
            default: break
            }
        }
        worker.onExit = { [weak self] code, cancelled, diagnostics in
            guard let self else { return }
            self.task = nil
            self.cancel.isHidden = true
            self.progress.stopAnimation(nil)
            self.progress.isHidden = true
            self.download.isEnabled = true
            if cancelled {
                self.message.stringValue = "Download cancelled. Installed models are kept."
            } else if code != 0 {
                self.showFailure(self.failure ?? (diagnostics.isEmpty ? "Model setup failed. Please try again." : diagnostics))
            }
        }
        do {
            try worker.start(arguments: ["-m", "ncf_image_upscaler.setup_models", downloading ? "--download" : "--status"])
        } catch {
            task = nil
            throw error
        }
    }

    private func showFailure(_ text: String) {
        message.stringValue = "Setup could not finish."
        detail.stringValue = text
        progress.stopAnimation(nil)
        progress.isHidden = true
        download.isEnabled = FileManager.default.isExecutableFile(atPath: AppPaths.python.path)
        download.title = "Download Models"
        showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) { task?.cancel() }
}
