import AppKit

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [ImageWindowController] = []
    private var terminating = false
    private let setup = ModelSetupController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyPreferences.migrate()
        TemporarySession.removeAbandoned()
        installMenu()
        setup.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
            for argument in arguments where FileManager.default.fileExists(atPath: argument) {
                self.open(URL(fileURLWithPath: argument))
            }
            if self.controllers.isEmpty { self.makeWindow() }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL { open(url) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { makeWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        if setup.isPreparing {
            terminating = true
            setup.waitForPreparation { [weak self] in
                guard let self else { return }
                self.terminating = false
                let reply = self.applicationShouldTerminate(sender)
                if reply != .terminateLater { sender.reply(toApplicationShouldTerminate: reply == .terminateNow) }
            }
            return .terminateLater
        }
        let fileWork = controllers.filter { $0.hasFileWork }
        if !fileWork.isEmpty {
            terminating = true
            let group = DispatchGroup()
            for controller in fileWork {
                group.enter()
                controller.waitForFileWork { group.leave() }
            }
            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                self.terminating = false
                switch self.applicationShouldTerminate(sender) {
                case .terminateNow: sender.reply(toApplicationShouldTerminate: true)
                case .terminateCancel: sender.reply(toApplicationShouldTerminate: false)
                default: break
                }
            }
            return .terminateLater
        }
        // Stop workers before enumerating pending results. Their final events must
        // not create an unprompted result while a close dialog is running.
        terminating = true
        let tasks = WorkerTask.activeTasks
        if !tasks.isEmpty {
            var pending = tasks.count
            for task in tasks {
                task.cancelAndWait { [weak self] in
                    pending -= 1
                    guard pending == 0, let self else { return }
                    let approved = self.resolveClosing()
                    self.terminating = false
                    sender.reply(toApplicationShouldTerminate: approved)
                }
            }
            return .terminateLater
        }
        let approved = resolveClosing()
        terminating = false
        return approved ? .terminateNow : .terminateCancel
    }

    private func resolveClosing() -> Bool {
        for controller in Array(controllers) {
            guard controller.resolveUnsavedResults() else { return false }
        }
        for controller in Array(controllers) { controller.window?.close() }
        return true
    }

    @discardableResult private func makeWindow() -> ImageWindowController {
        let controller = ImageWindowController()
        controller.onOpen = { [weak self] in self?.openPanel() }
        controller.prepareEnhancement = { [weak self] preset, scale in
            self?.setup.canEnhance(preset: preset, scale: scale) ?? false
        }
        controller.onDrop = { [weak self] url in self?.open(url) }
        controller.onClosed = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        return controller
    }

    private func open(_ url: URL) {
        let url = url.standardizedFileURL
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let directory = (isDirectory ? url : url.deletingLastPathComponent()).resolvingSymlinksInPath()
        if let existing = controllers.first(where: { $0.folderURL == directory }) {
            existing.load(url)
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = controllers.first(where: { $0.folderURL == nil }) ?? makeWindow()
        controller.load(url)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AppPaths.imageTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Open"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { self?.open(url) }
        }
    }

    private var active: ImageWindowController? {
        (NSApp.keyWindow?.windowController as? ImageWindowController)
            ?? controllers.last
    }
    @objc func save() { active?.saveResult() }
    @objc func saveAs() { active?.saveResultAs() }
    @objc func enhance() { active?.enhance() }
    @objc func fit() { active?.fitImage() }
    @objc func actual() { active?.actualSize() }
    @objc func zoomIn() { active?.zoomIn() }
    @objc func zoomOut() { active?.zoomOut() }
    @objc func showModels() { setup.showSetup() }

    private func installMenu() {
        let bar = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: "About NCF Image Upscaler", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        add(application, "Models…", #selector(showModels), "")
        application.addItem(.separator())
        application.addItem(withTitle: "Hide NCF Image Upscaler", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(.separator())
        application.addItem(withTitle: "Quit NCF Image Upscaler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = application
        bar.addItem(appItem)
        let file = NSMenu(title: "File")
        add(file, "Open…", #selector(openPanel), "o")
        file.addItem(.separator())
        add(file, "Enhance", #selector(enhance), "u")
        add(file, "Save", #selector(save), "s")
        let saveAsItem = add(file, "Save As…", #selector(saveAs), "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(.separator())
        file.addItem(withTitle: "Rename…", action: #selector(BrowserWindow.renameFiles(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Duplicate", action: #selector(BrowserWindow.duplicateFiles(_:)), keyEquivalent: "d")
        let trash = file.addItem(withTitle: "Move to Trash", action: #selector(BrowserWindow.trashFiles(_:)), keyEquivalent: "\u{8}")
        trash.keyEquivalentModifierMask = .command
        let delete = file.addItem(withTitle: "Delete Permanently…", action: #selector(BrowserWindow.deleteFiles(_:)), keyEquivalent: "\u{8}")
        delete.keyEquivalentModifierMask = [.command, .option]
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = file
        bar.addItem(fileItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: #selector(BrowserWindow.undo(_:)), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: #selector(BrowserWindow.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(BrowserWindow.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(BrowserWindow.paste(_:)), keyEquivalent: "v")
        let move = edit.addItem(withTitle: "Move Items Here", action: #selector(BrowserWindow.moveClipboardFiles(_:)), keyEquivalent: "v")
        move.keyEquivalentModifierMask = [.command, .option]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Select All", action: #selector(BrowserWindow.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        bar.addItem(editItem)
        let view = NSMenu(title: "View")
        add(view, "Fit to Window", #selector(fit), "0")
        add(view, "Actual Size", #selector(actual), "1")
        add(view, "Zoom In", #selector(zoomIn), "+")
        add(view, "Zoom Out", #selector(zoomOut), "-")
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewItem.submenu = view
        bar.addItem(viewItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        bar.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = bar
    }

    @discardableResult private func add(_ menu: NSMenu, _ title: String,
                                        _ action: Selector, _ key: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

// Used by distribution verification; does not open a window or access the network.
if Array(CommandLine.arguments.dropFirst()) == ["--prepare-runtime"] {
    do {
        guard let installer = try PortableRuntimeInstaller.bundled(resources: Bundle.main.resourceURL, data: AppPaths.data) else {
            throw AppFailure.message("This app does not contain a portable engine.")
        }
        try installer.install()
        print(installer.python.path)
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = ApplicationDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
