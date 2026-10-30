import AppKit
import UniformTypeIdentifiers

final class ImageWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let viewer = ComparisonView()
    private let sidebar = FolderSidebar()
    private var sidebarWidth: NSLayoutConstraint?
    private var sidebarBottom: NSLayoutConstraint?
    private var sidebarCollapsedHeight: NSLayoutConstraint?
    private let status = NSTextField(labelWithString: "Open an image or drag it into the window")
    private let progress = NSProgressIndicator()
    private let cancelButton = NSButton()
    private let modelPopup = NSPopUpButton()
    private let scaleControl = NSSegmentedControl(labels: ImageDocument.outputScales.map { "×\($0)" }, trackingMode: .selectOne,
                                                   target: nil, action: nil)
    private let enhanceButton = NSButton()
    private let saveButton = NSButton()
    private let saveAsButton = NSButton()
    private let zoomButton = NSButton()
    private let emptyState = NSStackView()
    private var worker: WorkerTask?
    private let imageQueue = OperationQueue()
    private let loadImage: (URL) throws -> ImageAsset
    private let fileQueue = DispatchQueue(label: "local.ncf-image-upscaler.files", qos: .userInitiated)
    private var directoryMonitor: DirectoryMonitor?
    private var refreshWork: DispatchWorkItem?
    private var afterFileWork: [() -> Void] = []
    var hasFileWork: Bool { isManagingFiles }
    func waitForFileWork(_ completion: @escaping () -> Void) {
        if isManagingFiles { afterFileWork.append(completion) }
        else { DispatchQueue.main.async(execute: completion) }
    }
    private var isManagingFiles = false {
        didSet {
            viewer.setLoading(isLoading || isManagingFiles)
            refreshControls()
            if !isManagingFiles {
                let completions = afterFileWork
                afterFileWork.removeAll()
                for completion in completions { DispatchQueue.main.async(execute: completion) }
            }
        }
    }
    private var session: TemporarySession?
    private var loadToken = UUID()
    private var folderToken = UUID()
    private var folder: FolderSession?
    private var openingDirectory: URL?
    private var sourceAsset: ImageAsset?
    private var processingDocument: ImageDocument?
    private var workerError: String?
    private var isBusy = false
    private var isLoading = false {
        didSet { viewer.setLoading(isLoading || isManagingFiles) }
    }
    private var closed = false
    private var waitingToClose = false
    private var processingStatus = ""
    private(set) var sourceURL: URL?
    var folderURL: URL? { folder?.directory ?? openingDirectory }
    var onOpen: (() -> Void)?
    var prepareEnhancement: ((String, Int) -> Bool)?
    var onDrop: ((URL) -> Void)?
    var onClosed: (() -> Void)?
    var hasUnsavedResult: Bool { folder?.documents.contains(where: { $0.hasUnsavedResult }) == true }

    init(loadImage: @escaping (URL) throws -> ImageAsset = ImageAsset.load) {
        self.loadImage = loadImage
        let window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        imageQueue.maxConcurrentOperationCount = 1
        imageQueue.qualityOfService = .userInitiated
        window.title = "NCF Image Upscaler"
        window.minSize = NSSize(width: 1040, height: 540)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()
        window.onBrowserAction = { [weak self] action in
            switch action {
            case .previous: self?.navigate(-1)
            case .next: self?.navigate(1)
            case .close: NSApp.terminate(nil)
            }
        }
        window.onFileNavigation = { [weak self] action, extend in
            guard let self, !self.closed, !self.waitingToClose else { return false }
            return self.sidebar.navigate(action, extendingSelection: extend)
        }
        window.onFileAction = { [weak self] action in self?.performFileAction(action) ?? false }
        window.canFileAction = { [weak self] action in self?.canPerformFileAction(action) ?? false }
        window.canUndoFiles = { [weak self] in self?.isManagingFiles == false && WorkerTask.activeTasks.isEmpty }
        setupContent()
        setupToolbar()
        refreshControls()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupContent() {
        guard let content = window?.contentView else { return }
        viewer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(viewer)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)
        sidebar.onSelect = { [weak self] url in self?.select(url) }
        sidebar.onSelectionChange = { [weak self] in self?.refreshStatus() }
        sidebar.fileMenu = { [weak self] documents in self?.makeFileMenu(documents) ?? NSMenu() }
        sidebar.onImport = { [weak self] urls in self?.importFiles(urls, moving: false) }
        viewer.fileMenu = { [weak self] in
            guard let self else { return NSMenu() }
            return self.makeFileMenu(self.folder?.selected.map { [$0] } ?? [])
        }
        sidebar.onListChange = { [weak self] in self?.refreshStatus() }
        sidebar.onWidthChange = { [weak self] requested in
            guard let self, let content = self.window?.contentView else { return }
            let width = SidebarPreferences.boundedWidth(requested, windowWidth: content.bounds.width,
                                                        thumbnailSize: self.sidebar.thumbnailSize)
            self.sidebar.rememberWidth(width)
            self.layoutSidebar()
        }
        sidebar.onCollapseChange = { [weak self] in self?.layoutSidebar() }
        viewer.onZoom = { [weak self] zoom in
            self?.zoomButton.title = "\(Int((zoom * 100).rounded()))%"
            self?.zoomButton.toolTip = "Zoom. Click for 100%"
        }
        viewer.onDrop = { [weak self] url in self?.onDrop?(url) }
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.isHidden = true
        progress.widthAnchor.constraint(equalToConstant: 150).isActive = true
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cancel")
        cancelButton.isBordered = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelProcessing)
        cancelButton.toolTip = "Cancel processing"
        cancelButton.isHidden = true
        let hint = NSTextField(labelWithString: "Z / X, Space — navigate · Scroll — zoom · Esc — close")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [status, progress, cancelButton, hint])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(stack)
        let width = sidebar.widthAnchor.constraint(equalToConstant:
            SidebarPreferences.boundedWidth(sidebar.preferredWidth, windowWidth: content.bounds.width,
                                             thumbnailSize: sidebar.thumbnailSize))
        sidebarWidth = width
        sidebarBottom = sidebar.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12)
        sidebarCollapsedHeight = sidebar.heightAnchor.constraint(equalToConstant: 44)
        viewer.leadingObstruction = width.constant + 24
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), width,
            sidebar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            sidebarBottom!,
            viewer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            viewer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            viewer.topAnchor.constraint(equalTo: content.topAnchor),
            viewer.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 34),
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        let icon = NSImageView(image: NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                             accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 58).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 58).isActive = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: "Open an Image")
        title.font = .systemFont(ofSize: 21, weight: .medium)
        let subtitle = NSTextField(labelWithString: "Drag a file here or press ⌘O")
        subtitle.textColor = .secondaryLabelColor
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 12
        [icon, title, subtitle].forEach { emptyState.addArrangedSubview($0) }
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        viewer.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: viewer.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: viewer.centerYAnchor)
        ])
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "NCFImageUpscalerToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
        modelPopup.addItems(withTitles: ["Photo", "Illustration", "Fast"])
        modelPopup.toolTip = "Enhancement model"
        modelPopup.setAccessibilityLabel("Enhancement model")
        modelPopup.widthAnchor.constraint(equalToConstant: 138).isActive = true
        scaleControl.selectedSegment = 2
        scaleControl.segmentStyle = .rounded
        scaleControl.toolTip = "×1 — enhance at original size; ×2 / ×4 — upscale"
        scaleControl.setAccessibilityLabel("Output size: ×1 at original size, ×2 or ×4")
        scaleControl.widthAnchor.constraint(equalToConstant: 118).isActive = true
        configureButton(enhanceButton, title: "Enhance", symbol: "sparkles",
                        action: #selector(enhance))
        enhanceButton.bezelStyle = .rounded
        enhanceButton.contentTintColor = .controlAccentColor
        configureButton(saveButton, title: "Save", symbol: "square.and.arrow.down",
                        action: #selector(saveResult))
        configureButton(saveAsButton, title: "Save As…", symbol: "square.and.arrow.down.on.square",
                        action: #selector(saveResultAs))
        zoomButton.title = "100%"
        zoomButton.bezelStyle = .rounded
        zoomButton.target = self
        zoomButton.action = #selector(actualSize)
        zoomButton.widthAnchor.constraint(equalToConstant: 65).isActive = true
        zoomButton.setAccessibilityLabel("View zoom")
    }

    private func configureButton(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.toolTip = title
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("open"), .flexibleSpace, .init("model"), .init("scale"), .init("enhance"),
         .flexibleSpace, .init("zoom"), .init("fit"), .init("save"), .init("saveAs")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id.rawValue {
        case "model": item.view = modelPopup; item.label = "Model"
        case "scale": item.view = scaleControl; item.label = "Output Size"
        case "enhance": item.view = enhanceButton; item.label = "Enhance"
        case "save": item.view = saveButton; item.label = "Save"
        case "saveAs": item.view = saveAsButton; item.label = "Save As…"
        case "zoom": item.view = zoomButton; item.label = "Zoom"
        case "open":
            item.label = "Open"
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open Image")
            item.toolTip = "Open Image… (⌘O)"
            item.target = self; item.action = #selector(openImage)
        case "fit":
            item.label = "Fit"
            item.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                 accessibilityDescription: "Fit image")
            item.toolTip = "Fit to Window (⌘0)"
            item.target = self; item.action = #selector(fitImage)
        default: return nil
        }
        return item
    }

    func load(_ url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let directory = (isDirectory ? url : url.deletingLastPathComponent())
            .standardizedFileURL.resolvingSymlinksInPath()
        let requested = isDirectory ? nil : directory.appendingPathComponent(url.lastPathComponent)
        if let folder, folder.directory == directory {
            if let requested {
                folder.include(requested)
                select(requested)
            }
            return
        }
        // ApplicationDelegate opens each folder in its own window, so pending results
        // never need to be discarded to browse a different folder.
        guard folder == nil else { onDrop?(url); return }
        openingDirectory = directory
        let token = UUID()
        folderToken = token
        status.stringValue = "Opening folder…"
        isLoading = true
        refreshControls()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try FolderSession.images(in: directory) }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed, self.folderToken == token else { return }
                self.isLoading = false
                switch result {
                case .success(let urls):
                    let folder = FolderSession(directory: directory, urls: urls)
                    self.folder = folder
                    self.directoryMonitor = DirectoryMonitor(directory) { [weak self] in self?.scheduleFolderRefresh() }
                    if let requested { folder.include(requested) }
                    self.sidebar.display(folder)
                    if let first = requested ?? folder.visibleDocuments.first?.url { self.select(first) }
                    else {
                        self.window?.title = directory.lastPathComponent
                        self.status.stringValue = "No supported images in this folder"
                        self.sidebar.display(folder)
                        self.refreshControls()
                    }
                case .failure(let error):
                    self.openingDirectory = nil
                    self.status.stringValue = "Could not open folder"
                    self.showError(error.localizedDescription)
                    self.refreshControls()
                }
            }
        }
    }

    private func rememberPosition() {
        guard sourceAsset != nil, let current = folder?.selected else { return }
        current.position = viewer.position()
        current.modelIndex = modelPopup.indexOfSelectedItem
        current.scaleIndex = scaleControl.selectedSegment
    }

    private func select(_ url: URL, reloading: Bool = false) {
        guard let folder else { return }
        if !reloading, folder.selected?.url == url { return }
        rememberPosition()
        guard let document = folder.select(url) else { return }
        sourceURL = document.url
        sourceAsset = nil
        // Keep the current frame and transparency background until the next
        // original and result can replace them together on the main queue.
        window?.title = document.url.lastPathComponent
        window?.representedURL = document.url
        modelPopup.selectItem(at: document.modelIndex)
        scaleControl.selectedSegment = document.scaleIndex
        sidebar.display(folder)
        emptyState.isHidden = true
        isLoading = true
        refreshStatus()
        refreshControls()
        let token = UUID()
        loadToken = token
        let resultURL = document.resultURL
        let loadImage = self.loadImage
        imageQueue.cancelAllOperations()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled == false else { return }
            let original = Result { try loadImage(document.url) }
            guard operation?.isCancelled == false else { return }
            let enhanced = resultURL.map { url in Result { try loadImage(url) } }
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed, self.loadToken == token else { return }
                self.isLoading = false
                switch original {
                case .success(let asset):
                    self.sourceAsset = asset
                    self.viewer.setOriginal(asset)
                    if case .success(let result) = enhanced { self.viewer.setEnhanced(result) }
                    if let position = document.position { self.viewer.restore(position) }
                    if case .failure(let error) = enhanced { self.showError(error.localizedDescription) }
                case .failure(let error):
                    self.viewer.clear()
                    self.showError(error.localizedDescription)
                }
                self.refreshStatus()
                self.refreshControls()
            }
        }
        imageQueue.addOperation(operation)
    }

    private func navigate(_ offset: Int) {
        guard !waitingToClose, let neighbor = folder?.neighbor(offset) else { return }
        select(neighbor.url)
    }

    private func refreshStatus() {
        if isManagingFiles { status.stringValue = "Working with files…"; return }
        if isBusy {
            let name = processingDocument?.url.lastPathComponent ?? ""
            status.stringValue = processingStatus + (processingDocument !== folder?.selected ? " · \(name)" : "")
            return
        }
        guard let folder, let document = folder.selected else { return }
        let visible = folder.visibleDocuments
        let prefix: String
        if let index = visible.firstIndex(where: { $0 === document }) {
            prefix = "\(index + 1) of \(visible.count)"
        } else { prefix = "Outside filter · Matches: \(visible.count)" }
        if isLoading { status.stringValue = prefix + " · Opening image…"; return }
        guard let sourceAsset else { status.stringValue = prefix + " · Could not open image"; return }
        var text = prefix + " · \(Int(sourceAsset.pixels.width)) × \(Int(sourceAsset.pixels.height))"
        if sidebar.selectedDocuments.count > 1 { text += " · Selected: \(sidebar.selectedDocuments.count)" }
        if sourceAsset.hasAlpha { text += " · Transparency" }
        if document.hasUnsavedResult { text += " · Result ×\(document.resultScale) unsaved" }
        else if let saved = document.savedURL { text += " · Saved: \(saved.lastPathComponent)" }
        status.stringValue = text
    }

    @objc func openImage() { onOpen?() }
    @objc func fitImage() { viewer.fit() }
    @objc func actualSize() { viewer.actualSize() }
    @objc func zoomIn() { viewer.zoomBy(1.25) }
    @objc func zoomOut() { viewer.zoomBy(0.8) }

    @objc func enhance() {
        guard !isBusy, !isLoading, !isManagingFiles, let document = folder?.selected, sourceAsset != nil else { return }
        let preset = ["photo", "anime", "fast"][modelPopup.indexOfSelectedItem]
        let scale = ImageDocument.outputScales[scaleControl.selectedSegment]
        guard prepareEnhancement?(preset, scale) ?? true else { return }
        if document.hasUnsavedResult {
            let alert = NSAlert()
            alert.messageText = "Replace the unsaved result?"
            alert.informativeText = "\(document.url.lastPathComponent)\nAfter processing succeeds, the previous temporary result will be replaced."
            alert.addButton(withTitle: "Enhance Again")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        document.modelIndex = modelPopup.indexOfSelectedItem
        document.scaleIndex = scaleControl.selectedSegment
        do {
            if session == nil { session = try TemporarySession() }
            guard let session else { return }
            let destination = session.nextResult()
            let scale = document.outputScale
            let model = ["photo", "anime", "fast"][document.modelIndex]
            let task = WorkerTask(session: session)
            worker = task
            processingDocument = document
            document.processing = .preparing
            sidebar.update(document)
            workerError = nil
            isBusy = true
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            processingStatus = "Preparing model…"
            refreshStatus()
            refreshControls()
            task.onEvent = { [weak self, weak task] event in
                guard let self, !self.closed, task?.cancelled != true else { return }
                switch event["event"] as? String {
                case "started":
                    document.processing = .processing(0)
                    self.progress.isIndeterminate = false
                    self.progress.doubleValue = 0
                    self.processingStatus = "Enhancing image…"
                case "progress":
                    let done = event["completed"] as? Double ?? 0
                    let total = event["total"] as? Double ?? 1
                    let percentage = min(100, done / max(1, total) * 100)
                    document.processing = .processing(percentage)
                    self.progress.doubleValue = percentage
                    self.processingStatus = "Enhancing image · \(Int(percentage))%"
                case "completed":
                    self.receiveResult(destination, scale: scale, document: document)
                case "error": self.workerError = event["message"] as? String
                default: break
                }
                self.sidebar.update(document)
                self.refreshStatus()
            }
            task.onExit = { [weak self] code, cancelled, diagnostics in
                guard let self, !self.closed else { return }
                self.worker = nil
                self.isBusy = false
                self.processingDocument = nil
                document.processing = nil
                self.sidebar.update(document)
                self.progress.stopAnimation(nil)
                if cancelled {
                    // A completed result already attached to a document must survive
                    // a late cancellation while the subprocess is winding down.
                    if document.resultURL != destination { try? FileManager.default.removeItem(at: destination) }
                } else if code != 0 || self.workerError != nil {
                    self.showError(self.workerError ?? (diagnostics.isEmpty
                        ? "The engine failed. Please try again." : diagnostics))
                }
                self.refreshStatus()
                self.refreshControls()
            }
            try task.start(input: document.url, output: destination, scale: scale, model: model)
        } catch {
            worker = nil
            processingDocument = nil
            document.processing = nil
            sidebar.update(document)
            isBusy = false
            progress.stopAnimation(nil)
            refreshStatus()
            refreshControls()
            showError(error.localizedDescription)
        }
    }

    private func receiveResult(_ url: URL, scale: Int, document: ImageDocument) {
        document.receive(url, scale: scale)
        if folder?.selected === document { select(document.url, reloading: true) }
        sidebar.update(document)
        refreshControls()
    }

    @objc func cancelProcessing() {
        worker?.cancel()
        processingDocument?.processing = .cancelling
        if let document = processingDocument { sidebar.update(document) }
        cancelButton.isEnabled = false
        processingStatus = "Cancelling…"
        refreshStatus()
    }

    @objc func saveResult() {
        guard !isLoading, let document = folder?.selected,
              processingDocument !== document else { return }
        do {
            if let saved = try document.save() { didSave(saved) }
        } catch { showError(error.localizedDescription) }
    }

    @objc func saveResultAs() {
        guard !isLoading, let document = folder?.selected, let resultURL = document.resultURL,
              processingDocument !== document, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = document.savedURL?.deletingLastPathComponent() ?? document.url.deletingLastPathComponent()
        panel.nameFieldStringValue = ResultExporter.suggestedURL(original: document.url, scale: document.resultScale).lastPathComponent
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            do {
                let saved = try ResultExporter.export(resultURL, original: document.url,
                    destination: destination, replacing: FileManager.default.fileExists(atPath: destination.path))
                document.didSave(saved)
                self.didSave(saved)
            } catch { self.showError(error.localizedDescription) }
        }
    }

    private func didSave(_ url: URL) {
        sidebar.invalidateThumbnail(url)
        if let folder { folder.include(url); sidebar.display(folder) }
        refreshStatus()
        refreshControls()
    }

    private func refreshSavedFiles() {
        guard let folder else { return }
        for saved in folder.documents.compactMap({ $0.savedURL }) { folder.include(saved) }
        sidebar.display(folder)
    }

    private func refreshControls() {
        let current = folder?.selected
        enhanceButton.isEnabled = sourceAsset != nil && !isBusy && !isLoading && !isManagingFiles && !waitingToClose
        scaleControl.isEnabled = processingDocument !== current
        modelPopup.isEnabled = processingDocument !== current
        saveButton.isEnabled = current?.resultURL != nil && !isLoading && processingDocument !== current
        saveAsButton.isEnabled = saveButton.isEnabled
        zoomButton.isEnabled = sourceAsset != nil
        progress.isHidden = !isBusy
        cancelButton.isHidden = !isBusy
        cancelButton.isEnabled = isBusy && worker?.cancelled != true
        window?.isDocumentEdited = hasUnsavedResult
    }

    private func showError(_ text: String) {
        guard let window, !closed else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "NCF Image Upscaler"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    func resolveUnsavedResults() -> Bool {
        guard let folder, hasUnsavedResult else { return true }
        do {
            let resolved = try UnsavedResults.resolve(folder.documents) { document, index, total in
                self.select(document.url)
                self.window?.makeKeyAndOrderFront(nil)
                let alert = NSAlert()
                alert.messageText = "Save the enhanced image?"
                alert.informativeText = "\(document.url.lastPathComponent)\nUnsaved result \(index) of \(total)."
                alert.addButton(withTitle: "Save")
                alert.addButton(withTitle: "Discard Result")
                alert.addButton(withTitle: "Cancel")
                switch alert.runModal() {
                case .alertFirstButtonReturn: return .save
                case .alertSecondButtonReturn: return .discard
                default: return .cancel
                }
            }
            // A cancelled close can have already saved/deleted earlier entries.
            if let current = folder.selected { select(current.url, reloading: true) }
            refreshSavedFiles()
            refreshControls()
            return resolved
        } catch {
            if let current = folder.selected { select(current.url, reloading: true) }
            refreshSavedFiles()
            refreshControls()
            showError(error.localizedDescription)
            return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isManagingFiles {
            if !waitingToClose {
                waitingToClose = true
                waitForFileWork { [weak self, weak sender] in
                    self?.waitingToClose = false
                    sender?.performClose(nil)
                }
            }
            return false
        }
        if let worker {
            guard !waitingToClose else { return false }
            waitingToClose = true
            worker.cancelAndWait { [weak self] in
                guard let self, !self.closed else { return }
                self.waitingToClose = false
                sender.performClose(nil)
            }
            return false
        }
        return resolveUnsavedResults()
    }

    func windowDidResize(_ notification: Notification) {
        layoutSidebar()
    }

    private func layoutSidebar() {
        guard let content = window?.contentView else { return }
        let width = SidebarPreferences.boundedWidth(sidebar.preferredWidth, windowWidth: content.bounds.width,
                                                    thumbnailSize: sidebar.thumbnailSize)
        if sidebar.isCollapsed {
            sidebarBottom?.isActive = false
            sidebarCollapsedHeight?.isActive = true
        } else {
            sidebarCollapsedHeight?.isActive = false
            sidebarBottom?.isActive = true
        }
        sidebarWidth?.constant = sidebar.isCollapsed ? sidebar.collapsedWidth : width
        viewer.leadingObstruction = sidebar.isCollapsed ? 0 : width + 24
        content.layoutSubtreeIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        closed = true
        isLoading = false
        directoryMonitor = nil
        sidebar.endThumbnailSession()
        refreshWork?.cancel()
        window?.undoManager?.removeAllActions()
        loadToken = UUID()
        folderToken = UUID()
        imageQueue.cancelAllOperations()
        worker?.cancel()
        worker?.onEvent = nil
        worker?.onExit = nil
        worker = nil
        folder = nil
        session = nil
        onClosed?()
    }

    private var fileTargets: [ImageDocument] {
        sidebar.hasFileFocus ? sidebar.selectedDocuments : (folder?.selected.map { [$0] } ?? [])
    }

    func canPerformFileAction(_ action: FileAction, documents: [ImageDocument]? = nil) -> Bool {
        let targets = documents ?? fileTargets
        let present = targets.filter { !$0.isMissing }
        let idle = !isManagingFiles && !waitingToClose
        let mutable = idle && !targets.isEmpty && targets.allSatisfy { $0.processing == nil }
        switch action {
        case .selectAll, .deselectAll: return folder != nil
        case .refresh: return folder != nil && idle
        case .paste: return folder != nil && idle && (!FileClipboard.files().isEmpty ||
            NSPasteboard.general.availableType(from: [.png, .tiff]) != nil)
        case .moveHere: return folder != nil && idle && WorkerTask.activeTasks.isEmpty && !FileClipboard.files().isEmpty
        case .copyFiles, .copyPaths, .reveal, .info: return !present.isEmpty
        case .copyImage: return targets.count == 1 && !present.isEmpty && idle
        case .copyResult: return targets.count == 1 && targets.first?.resultURL != nil && idle
        case .rename: return mutable && present.count == 1 && targets.count == 1
        case .duplicate: return idle && !present.isEmpty
        case .trash, .deletePermanently: return mutable && !present.isEmpty
        case .saveResults, .discardResults: return mutable && targets.contains { $0.hasUnsavedResult }
        }
    }

    private func makeFileMenu(_ documents: [ImageDocument]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let groups: [[FileAction]] = [
            [.copyFiles, .copyImage, .copyResult, .copyPaths], [.paste, .moveHere],
            [.rename, .duplicate], [.saveResults, .discardResults],
            [.reveal, .info], [.trash, .deletePermanently], [.selectAll, .deselectAll, .refresh]
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for action in group {
                if action == .copyResult && documents.first?.resultURL == nil { continue }
                if [.saveResults, .discardResults].contains(action) && !documents.contains(where: { $0.hasUnsavedResult }) { continue }
                let item = NSMenuItem(title: action.title, action: #selector(fileMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = action.rawValue
                item.representedObject = documents
                item.isEnabled = canPerformFileAction(action, documents: documents)
                menu.addItem(item)
            }
            if index == 4, let first = documents.first, !first.isMissing {
                let open = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                let applications = NSMenu()
                applications.autoenablesItems = false
                for application in NSWorkspace.shared.urlsForApplications(toOpen: first.url)
                    where application.bundleURLIdentifier != Bundle.main.bundleIdentifier {
                    let item = NSMenuItem(title: application.deletingPathExtension().lastPathComponent,
                        action: #selector(openFilesWith(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = [application] + documents.filter { !$0.isMissing }.map { $0.url }
                    item.image = NSWorkspace.shared.icon(forFile: application.path)
                    item.image?.size = NSSize(width: 16, height: 16)
                    applications.addItem(item)
                }
                let other = NSMenuItem(title: "Other Application…", action: #selector(chooseApplication(_:)), keyEquivalent: "")
                other.target = self
                other.representedObject = documents
                applications.addItem(other)
                open.submenu = applications
                menu.addItem(open)
            }
        }
        return menu
    }

    @objc private func fileMenuAction(_ sender: NSMenuItem) {
        guard let action = FileAction(rawValue: sender.tag) else { return }
        performFileAction(action, documents: sender.representedObject as? [ImageDocument])
    }

    @discardableResult func performFileAction(_ action: FileAction, documents: [ImageDocument]? = nil) -> Bool {
        let targets = documents ?? fileTargets
        guard canPerformFileAction(action, documents: targets) else { return false }
        let urls = targets.filter { !$0.isMissing }.map { $0.url }
        switch action {
        case .selectAll:
            if sidebar.isCollapsed { sidebar.toggleCollapsed() }
            sidebar.selectAllFiles()
            window?.makeFirstResponder(sidebar.collection)
        case .deselectAll: sidebar.deselectAllFiles()
        case .copyFiles: FileClipboard.copyFiles(urls)
        case .copyPaths:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map { $0.path }.joined(separator: "\n"), forType: .string)
        case .copyImage, .copyResult:
            guard let document = targets.first, let url = action == .copyResult ? document.resultURL : document.url else { return false }
            isManagingFiles = true
            refreshStatus()
            fileQueue.async { [weak self] in
                let result = Result { try FileClipboard.encodeImage(ImageAsset.load(url)) }
                DispatchQueue.main.async {
                    guard let self, !self.closed else { return }
                    self.isManagingFiles = false
                    do { FileClipboard.writeImage(try result.get()) }
                    catch { self.showError(error.localizedDescription) }
                    self.refreshStatus()
                }
            }
        case .paste:
            let files = FileClipboard.files()
            if !files.isEmpty { importFiles(files, moving: false) }
            else if let folder, let data = FileClipboard.imageData() {
                let destination = FileOperations.availableURL(in: folder.directory, name: "Image.png")
                runFileMutations([.create(data, destination)], title: "Paste Image")
            }
        case .moveHere: importFiles(FileClipboard.files(), moving: true)
        case .duplicate: importFiles(urls, moving: false)
        case .rename: if let document = targets.first { renameFile(document) }
        case .trash, .deletePermanently:
            if action == .deletePermanently {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Permanently delete the selected files?"
                alert.informativeText = "Files: \(urls.count)\n\n"
                    + urls.prefix(12).map { $0.lastPathComponent }.joined(separator: "\n")
                    + (urls.count > 12 ? "\nAnd \(urls.count - 12)…" : "")
                    + "\n\nThese files cannot be recovered from Trash. This action cannot be undone."
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Delete Permanently")
                guard alert.runModal() == .alertSecondButtonReturn else { return true }
            }
            guard resolveFileResults(targets) else { return true }
            runFileMutations(urls.map { action == .trash ? .trash($0) : .delete($0) }, title: action.title)
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .info: showFileInfo(targets)
        case .refresh: refreshFolder()
        case .saveResults:
            do {
                for document in targets where document.hasUnsavedResult {
                    if let saved = try document.save() { folder?.include(saved) }
                }
                refreshFolder()
            } catch { showError(error.localizedDescription) }
        case .discardResults:
            let alert = NSAlert()
            alert.messageText = "Discard unsaved enhancements?"
            alert.informativeText = "Original images will remain in the folder. Temporary results for the selected files will be deleted."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard Enhancements")
            guard alert.runModal() == .alertSecondButtonReturn else { return true }
            do {
                for document in targets where document.hasUnsavedResult { try document.discard() }
                if let selected = folder?.selected { select(selected.url, reloading: true) }
                if let folder { sidebar.display(folder, revealSelection: false, selectCurrent: false) }
            } catch { showError(error.localizedDescription) }
        }
        return true
    }

    private func renameFile(_ document: ImageDocument) {
        let alert = NSAlert()
        alert.messageText = "Rename File"
        let field = NSTextField(string: document.url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let destination = try FileOperations.renamedURL(document.url, name: field.stringValue)
            if destination == document.url { return }
            if destination.pathExtension.lowercased() != document.url.pathExtension.lowercased() {
                let warning = NSAlert()
                warning.messageText = "Change the file extension?"
                warning.informativeText = "New name: \(destination.lastPathComponent). The file may no longer appear in the image list."
                warning.addButton(withTitle: "Cancel")
                warning.addButton(withTitle: "Change Extension")
                guard warning.runModal() == .alertSecondButtonReturn else { return }
            }
            runFileMutations([.move(document.url, destination)], title: "Rename")
        } catch { showError(error.localizedDescription) }
    }

    private func importFiles(_ urls: [URL], moving: Bool) {
        guard !isManagingFiles, let folder, !moving || WorkerTask.activeTasks.isEmpty else { return }
        let mutations = FileOperations.imports(urls, into: folder.directory, moving: moving)
        runFileMutations(mutations, title: moving ? "Move Files" : "Copy Files")
    }

    private func runFileMutations(_ mutations: [FileMutation], title: String) {
        guard !mutations.isEmpty, !isManagingFiles else { return }
        isManagingFiles = true
        refreshStatus()
        fileQueue.async { [weak self] in
            let result = FileOperations.perform(mutations)
            DispatchQueue.main.async {
                guard let self, !self.closed else { return }
                self.isManagingFiles = false
                self.applyFileChanges(result, title: title)
            }
        }
    }

    private func applyFileChanges(_ result: FileBatchResult, title: String) {
        guard let folder else { return }
        for (source, destination) in result.moved {
            folder.documents.first { $0.url == source }?.relocate(to: destination)
        }
        for source in result.removed {
            let destination = result.moved.first { $0.0 == source }?.1
            for document in folder.documents { document.savedFileMoved(from: source, to: destination) }
            sidebar.invalidateThumbnail(source)
        }
        for destination in result.created { sidebar.invalidateThumbnail(destination) }
        if !result.inverse.isEmpty, let undo = window?.undoManager {
            undo.registerUndo(withTarget: self) { controller in
                // Undo changes are moves/trash, and register their inverse while
                // UndoManager is undoing so that redo remains a single action.
                guard !controller.isManagingFiles, WorkerTask.activeTasks.isEmpty else { return }
                controller.applyFileChanges(FileOperations.perform(result.inverse), title: title)
            }
            undo.setActionName(title)
        }
        refreshFolder(selecting: result.created)
        if !result.errors.isEmpty { showError(result.errors.joined(separator: "\n")) }
    }

    private func resolveFileResults(_ documents: [ImageDocument]) -> Bool {
        do {
            let resolved = try UnsavedResults.resolve(documents) { document, _, _ in
                let alert = NSAlert()
                alert.messageText = "Save the enhancement before deleting the original?"
                alert.informativeText = document.url.lastPathComponent
                alert.addButton(withTitle: "Save Enhancement")
                alert.addButton(withTitle: "Discard Enhancement")
                alert.addButton(withTitle: "Cancel")
                switch alert.runModal() {
                case .alertFirstButtonReturn: return .save
                case .alertSecondButtonReturn: return .discard
                default: return .cancel
                }
            }
            refreshSavedFiles()
            refreshControls()
            return resolved
        } catch { showError(error.localizedDescription); return false }
    }

    private func scheduleFolderRefresh() {
        refreshWork?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.refreshFolder() }
        refreshWork = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    private func refreshFolder(selecting requested: [URL] = []) {
        guard let folder, !closed, !isManagingFiles else { return }
        do {
            let current = folder.selected
            let oldRevision = current?.revision
            let previousIndex = folder.visibleDocuments.firstIndex { $0 === current } ?? 0
            folder.reconcile(try FolderSession.images(in: folder.directory))
            for document in folder.documents {
                if let saved = document.savedURL, !FileManager.default.fileExists(atPath: saved.path) {
                    document.savedFileMoved(from: saved, to: nil)
                }
            }
            sidebar.display(folder, revealSelection: false, selectCurrent: false)
            let created = folder.visibleDocuments.filter { requested.contains($0.url) }
            if let first = created.first {
                sidebar.setSelection(created)
                select(first.url, reloading: true)
            } else if let selected = folder.selected, !selected.isMissing {
                if selected.url != sourceURL || selected.revision != oldRevision {
                    select(selected.url, reloading: true)
                }
            } else if !folder.visibleDocuments.filter({ !$0.isMissing }).isEmpty {
                let available = folder.visibleDocuments.filter { !$0.isMissing }
                let next = available[min(previousIndex, available.count - 1)]
                select(next.url, reloading: true)
            } else {
                loadToken = UUID()
                imageQueue.cancelAllOperations()
                sourceAsset = nil
                sourceURL = nil
                isLoading = false
                viewer.clear()
                emptyState.isHidden = false
                window?.title = folder.directory.lastPathComponent
                status.stringValue = "No available images in this folder"
            }
            refreshStatus()
            refreshControls()
        } catch { status.stringValue = "Could not refresh folder: \(error.localizedDescription)" }
    }

    private func showFileInfo(_ documents: [ImageDocument]) {
        let alert = NSAlert()
        alert.messageText = documents.count == 1 ? documents[0].url.lastPathComponent : "Selected files: \(documents.count)"
        let total = documents.reduce(Int64(0)) { $0 + Int64($1.fileSize) }
        var lines = ["Size: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))",
                     "Folder: \(folder?.directory.path ?? "")"]
        if documents.count == 1, let document = documents.first {
            lines += ["Type: \(document.url.pathExtension.uppercased())",
                      "Created: \(document.created.formatted())", "Modified: \(document.modified.formatted())"]
            if document === folder?.selected, let sourceAsset {
                lines += ["Resolution: \(Int(sourceAsset.pixels.width)) × \(Int(sourceAsset.pixels.height))",
                          "Transparency: \(sourceAsset.hasAlpha ? "yes" : "no")"]
            }
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Close")
        if let window { alert.beginSheetModal(for: window) }
    }

    @objc private func openFilesWith(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], let application = urls.first else { return }
        NSWorkspace.shared.open(Array(urls.dropFirst()), withApplicationAt: application,
            configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.showError(error.localizedDescription) } }
        }
    }

    @objc private func chooseApplication(_ sender: NSMenuItem) {
        guard let documents = sender.representedObject as? [ImageDocument], let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let application = panel.url else { return }
            let item = NSMenuItem()
            item.representedObject = [application] + documents.map { $0.url }
            self?.openFilesWith(item)
        }
    }
}

private extension URL {
    var bundleURLIdentifier: String? { Bundle(url: self)?.bundleIdentifier }
}
