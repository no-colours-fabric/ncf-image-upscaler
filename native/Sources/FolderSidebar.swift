import AppKit
import ImageIO
import QuartzCore

final class ThumbnailView: NSView {
    var representedURL: URL? { didSet { if representedURL != oldValue { hasPresentedImage = false } } }
    var revision: UUID?
    var image: NSImage? { didSet { updateSkeleton(); needsDisplay = true } }
    var sourcePixels: NSSize? { didSet { needsDisplay = true; needsLayout = true } }
    var enlarge = true { didSet { needsDisplay = true; needsLayout = true } }
    var isLoading = false { didSet { updateSkeleton() } }
    var waitsForLayout = false { didSet { updateSkeleton() } }
    private(set) var showsSkeleton = false
    private var hasPresentedImage = false
    private let skeletonHighlight = CALayer()
    var skeletonFrame: NSRect {
        sourcePixels.map { ThumbnailGeometry.imageRect(pixels: $0, in: bounds, enlarge: enlarge) } ?? bounds
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
        wantsLayer = true
        skeletonHighlight.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        skeletonHighlight.name = "thumbnail-loading-highlight"
        skeletonHighlight.cornerRadius = 6
        skeletonHighlight.isHidden = true
        layer?.addSublayer(skeletonHighlight)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        skeletonHighlight.frame = skeletonFrame
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateSkeleton() }
    override func viewDidHide() { super.viewDidHide(); updateSkeleton() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateSkeleton() }

    private func updateSkeleton() {
        if image != nil && !waitsForLayout { hasPresentedImage = true }
        showsSkeleton = (image == nil && isLoading) || (waitsForLayout && !hasPresentedImage)
        skeletonHighlight.isHidden = !showsSkeleton
        let animate = showsSkeleton && window != nil && !isHiddenOrHasHiddenAncestor &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate && skeletonHighlight.animation(forKey: "loading") == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.15
            pulse.toValue = 0.85
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            skeletonHighlight.add(pulse, forKey: "loading")
        } else if !animate { skeletonHighlight.removeAnimation(forKey: "loading") }
        setAccessibilityLabel(showsSkeleton ? "Loading thumbnail" : (image == nil ? "Preview unavailable" : nil))
        needsDisplay = true
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsSkeleton {
            NSColor(white: 0.86, alpha: 1).setFill()
            NSBezierPath(roundedRect: skeletonFrame, xRadius: 6, yRadius: 6).fill()
            return
        }
        guard let image else {
            if representedURL != nil {
                let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
                icon?.draw(in: NSRect(x: bounds.midX - 12, y: bounds.midY - 12, width: 24, height: 24),
                           from: .zero, operation: .sourceOver, fraction: 0.35)
            }
            return
        }
        let rect = ThumbnailGeometry.imageRect(pixels: sourcePixels ?? image.size, in: bounds, enlarge: enlarge)
        guard !rect.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        rect.clip()
        NSColor(white: 0.88, alpha: 1).setFill()
        rect.fill()
        NSColor(white: 0.76, alpha: 1).setFill()
        for y in 0...Int(rect.height / 7) {
            for x in 0...Int(rect.width / 7) where (x + y) % 2 == 0 {
                NSRect(x: rect.minX + CGFloat(x) * 7, y: rect.minY + CGFloat(y) * 7,
                       width: 7, height: 7).fill()
            }
        }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

final class ThumbnailCard: NSView {
    let preview = ThumbnailView()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let improved = NSImageView()
    private let progress = NSProgressIndicator()
    private let percentage = NSTextField(labelWithString: "")
    var selected = false { didSet { updateSelection() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
        updateSelection()
        name.font = .systemFont(ofSize: 11, weight: .medium)
        name.textColor = NSColor(white: 0.15, alpha: 1)
        name.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .systemOrange
        detail.lineBreakMode = .byTruncatingTail
        improved.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Unsaved enhancement available")
        improved.contentTintColor = .systemOrange
        improved.imageScaling = .scaleProportionallyUpOrDown
        improved.setAccessibilityLabel("Unsaved enhancement available")
        progress.style = .bar
        progress.controlSize = .small
        progress.minValue = 0
        progress.maxValue = 100
        progress.setAccessibilityLabel("Enhancement progress")
        percentage.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        percentage.textColor = NSColor(white: 0.35, alpha: 1)
        percentage.lineBreakMode = .byTruncatingTail
        percentage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [preview, name, detail, improved, progress, percentage] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -50),
            name.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            name.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            name.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 6),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 4),
            improved.topAnchor.constraint(equalTo: preview.topAnchor, constant: 2),
            improved.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -2),
            improved.widthAnchor.constraint(equalToConstant: 18), improved.heightAnchor.constraint(equalToConstant: 18),
            progress.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: percentage.leadingAnchor, constant: -6),
            progress.centerYAnchor.constraint(equalTo: detail.centerYAnchor),
            progress.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            percentage.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            percentage.centerYAnchor.constraint(equalTo: detail.centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateSelection() {
        layer?.borderWidth = selected ? 2 : 0.5
        layer?.borderColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.black.withAlphaComponent(0.08).cgColor
    }

    func configure(_ document: ImageDocument, size: CGFloat, adaptive: Bool = false, sourcePixels: NSSize? = nil) {
        preview.enlarge = !adaptive
        preview.sourcePixels = sourcePixels
        name.stringValue = document.url.lastPathComponent
        improved.isHidden = !document.hasUnsavedResult
        let processing = document.processing
        progress.isHidden = processing == nil
        percentage.isHidden = processing == nil
        detail.isHidden = processing != nil
        progress.stopAnimation(nil)
        if let processing {
            percentage.stringValue = processing.label
            progress.isIndeterminate = processing.percentage == nil
            progress.doubleValue = processing.percentage ?? 0
            if progress.isIndeterminate { progress.startAnimation(nil) }
        } else { detail.stringValue = document.isMissing ? "Original unavailable" : (document.hasUnsavedResult ? "Unsaved" : "") }
        toolTip = name.stringValue + (processing.map { " · \($0.label)" } ?? "")
            + (document.hasUnsavedResult ? " · Unsaved" : "")
    }
}

private final class ThumbnailItem: NSCollectionViewItem {
    override func loadView() { view = ThumbnailCard() }
    var card: ThumbnailCard { view as! ThumbnailCard }
    override var isSelected: Bool { didSet { card.selected = isSelected } }
}

private final class SidebarResizeHandle: NSView {
    private var initialX: CGFloat = 0
    private var initialWidth: CGFloat = 0
    var onResize: ((CGFloat) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Image sidebar width")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 1.5, y: bounds.midY - 16,
                                         width: 3, height: 32), xRadius: 1.5, yRadius: 1.5).fill()
    }
    override func mouseDown(with event: NSEvent) {
        initialX = event.locationInWindow.x
        initialWidth = superview?.bounds.width ?? 260
        window?.makeFirstResponder(nil)
    }
    override func mouseDragged(with event: NSEvent) { onResize?(initialWidth + event.locationInWindow.x - initialX) }
    override func accessibilityValue() -> Any? { Int(superview?.bounds.width ?? 0) }
    override func accessibilityPerformIncrement() -> Bool { onResize?((superview?.bounds.width ?? 0) + 20); return true }
    override func accessibilityPerformDecrement() -> Bool { onResize?((superview?.bounds.width ?? 0) - 20); return true }
}

private final class FileListClipView: NSClipView {
    var contextMenu: (() -> NSMenu)?
    var onImport: (([URL]) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() }
    override func mouseDown(with event: NSEvent) { documentView?.mouseDown(with: event) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? NSView !== documentView,
              !FileClipboard.files(sender.draggingPasteboard).isEmpty else { return [] }
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = FileClipboard.files(sender.draggingPasteboard)
        guard !files.isEmpty, onImport != nil else { return false }
        onImport?(files)
        return true
    }
}

final class FileCollectionView: NSCollectionView {
    var contextMenu: (() -> NSMenu)?
    var onContextSelection: ((IndexPath?) -> Void)?
    var focusedPath: IndexPath?
    var onNavigate: ((FileNavigation, Bool) -> Bool)?
    var onResetNavigation: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if let action = FileNavigation.key(event.keyCode, modifiers: event.modifierFlags),
           onNavigate?(action, event.modifierFlags.contains(.shift)) == true { return }
        onResetNavigation?()
        focusedPath = nil
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onResetNavigation?()
        focusedPath = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onResetNavigation?()
        let path = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        window?.makeFirstResponder(self)
        onContextSelection?(path)
        return contextMenu?()
    }
}

final class FolderSidebar: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate {
    let collection = FileCollectionView()
    private let flow = NSCollectionViewFlowLayout()
    private let adaptiveLayout = AdaptiveThumbnailLayout()
    private let scroll = NSScrollView()
    private let heading = NSButton(title: "Images in Folder", target: nil, action: nil)
    private let collapseButton = NSButton()
    private let body = NSView()
    private var bodyBottom: NSLayoutConstraint!
    private var foldedBodyHeight: NSLayoutConstraint?
    private let handle = SidebarResizeHandle()
    private let search = NSSearchField()
    private let locateButton = NSButton()
    private let sort = NSPopUpButton()
    private let sizeSlider = NSSlider()
    private let regularGridButton = NSButton()
    private let adaptiveGridButton = NSButton()
    private let empty = NSTextField(labelWithString: "Open a Folder")
    private var cache: ThumbnailCache?
    private let queue = OperationQueue()
    private let preferences: SidebarPreferences
    private let loadThumbnail: (URL, TemporarySession?) -> PreparedThumbnail?
    private let loadImageSize: (URL) -> NSSize?
    private var requested = Set<URL>()
    private var thumbnailVersions: [URL: UUID] = [:]
    private var imageSizes: [URL: NSSize] = [:]
    private var metadataRequested = Set<URL>()
    private var metadataTasks = Set<UUID>()
    private(set) var isPreparingGrid = false
    private var sourceRevisions: [URL: FileRevision] = [:]
    private var trackedURLs = Set<URL>()
    private var cacheGeneration = UUID()
    private var cleanupTimer: Timer?
    private(set) var thumbnailLoadCount = 0
    private(set) var metadataReadCount = 0
    var pendingThumbnailCount: Int { requested.count }
    private var documents: [ImageDocument] = []
    private var session: FolderSession?
    private var revealAfterLayout: ImageDocument?
    private var navigationFocus: ImageDocument?
    private var navigationAnchor: ImageDocument?
    private var selecting = false
    private var selectionNotification: DispatchWorkItem?
    private var clipObservation: NSObjectProtocol?
    private var updatingGrid = false
    private var adaptiveWidth: CGFloat = 0
    var onSelect: ((URL) -> Void)?
    var onSelectionChange: (() -> Void)?
    var fileMenu: (([ImageDocument]) -> NSMenu)?
    var onImport: (([URL]) -> Void)?
    var onListChange: (() -> Void)?
    var onWidthChange: ((CGFloat) -> Void)?
    var onCollapseChange: (() -> Void)?
    private(set) var isCollapsed = false
    var collapsedWidth: CGFloat { min(300, max(180, heading.intrinsicContentSize.width + 64)) }
    var preferredWidth: CGFloat { preferences.width }
    var thumbnailSize: CGFloat { preferences.thumbnailSize }
    var gridMode: ThumbnailGridMode { preferences.gridMode }
    var selectedDocuments: [ImageDocument] {
        collection.selectionIndexPaths.sorted().compactMap { path in
            documents.indices.contains(path.item) ? documents[path.item] : nil
        }
    }
    var hasFileFocus: Bool { window?.firstResponder === collection }

    init(preferences: SidebarPreferences = SidebarPreferences(),
         loadThumbnail: @escaping (URL, TemporarySession?) -> PreparedThumbnail? = ThumbnailCache.prepare,
         loadImageSize: @escaping (URL) -> NSSize? = ThumbnailGeometry.imageSize) {
        self.preferences = preferences
        self.loadThumbnail = loadThumbnail
        self.loadImageSize = loadImageSize
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: -3)
        let surface = NSVisualEffectView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.material = .sidebar
        surface.blendingMode = .withinWindow
        surface.state = .active
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 16
        surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 0.5
        surface.layer?.borderColor = NSColor.separatorColor.cgColor
        // Keep the background translucent while controls retain full opacity.
        surface.alphaValue = 0.85
        addSubview(surface)
        bodyBottom = body.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.isBordered = false
        heading.alignment = .left
        heading.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        heading.imagePosition = .imageLeft
        heading.imageScaling = .scaleProportionallyDown
        heading.cell?.lineBreakMode = .byTruncatingMiddle
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        heading.target = self
        heading.action = #selector(toggleCollapsed)
        collapseButton.isBordered = false
        collapseButton.target = self
        collapseButton.action = #selector(toggleCollapsed)
        updateCollapseButton()
        for view in [heading, collapseButton, body] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            heading.heightAnchor.constraint(equalToConstant: 24),
            heading.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -6),
            collapseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            collapseButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            collapseButton.widthAnchor.constraint(equalToConstant: 24),
            collapseButton.heightAnchor.constraint(equalToConstant: 24),
            body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            bodyBottom
        ])
        search.placeholderString = "Filter by name"
        search.controlSize = .small
        search.font = .systemFont(ofSize: 11)
        search.delegate = self
        search.setAccessibilityLabel("Filter images")
        let locateSymbol = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)
        locateButton.image = locateSymbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        locateButton.imagePosition = .imageOnly
        locateButton.imageScaling = .scaleProportionallyDown
        locateButton.isBordered = false
        locateButton.contentTintColor = .secondaryLabelColor
        locateButton.controlSize = .small
        locateButton.toolTip = "Show selected file in sidebar"
        locateButton.setAccessibilityLabel("Show selected file in sidebar")
        locateButton.target = self
        locateButton.action = #selector(revealSelection)
        locateButton.isEnabled = false
        sort.addItems(withTitles: ImageSortKey.allCases.flatMap { ["↑ \($0.title)", "↓ \($0.title)"] })
        sort.controlSize = .small
        sort.font = .systemFont(ofSize: 11)
        sort.selectItem(at: (ImageSortKey.allCases.firstIndex(of: preferences.sortKey) ?? 0) * 2
            + (preferences.descending ? 1 : 0))
        sort.target = self
        sort.action = #selector(sortChanged)
        sort.setAccessibilityLabel("Sort by")
        sort.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        flow.scrollDirection = .vertical
        flow.minimumLineSpacing = ThumbnailGridMetrics.gap
        flow.minimumInteritemSpacing = ThumbnailGridMetrics.gap
        flow.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        flow.itemSize = NSSize(width: 128, height: 170)
        collection.collectionViewLayout = flow
        collection.autoresizingMask = [.width]
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        collection.dataSource = self
        collection.delegate = self
        collection.register(ThumbnailItem.self, forItemWithIdentifier: .init("thumbnail"))
        collection.setAccessibilityLabel("Images in Folder")
        collection.contextMenu = { [weak self] in
            guard let self else { return NSMenu() }
            return self.fileMenu?(self.selectedDocuments) ?? NSMenu()
        }
        collection.onContextSelection = { [weak self] path in
            guard let self else { return }
            if let path {
                if !self.collection.selectionIndexPaths.contains(path) {
                    self.setSelection([self.documents[path.item]])
                    self.onSelect?(self.documents[path.item].url)
                }
            } else { self.setSelection([]) }
        }
        collection.onNavigate = { [weak self] action, extend in self?.navigate(action, extendingSelection: extend) ?? false }
        collection.onResetNavigation = { [weak self] in self?.resetKeyboardNavigation() }
        collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        let clip = FileListClipView()
        clip.contextMenu = { [weak self] in
            guard let self else { return NSMenu() }
            self.window?.makeFirstResponder(self.collection)
            self.setSelection([])
            return self.fileMenu?([]) ?? NSMenu()
        }
        clip.onImport = { [weak self] files in self?.onImport?(files) }
        scroll.contentView = clip
        scroll.documentView = collection
        scroll.contentView.postsFrameChangedNotifications = true
        clipObservation = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak self] _ in self?.updateGrid() }
        empty.font = .systemFont(ofSize: 12)
        empty.textColor = .secondaryLabelColor
        let line = NSBox()
        line.boxType = .separator
        sizeSlider.minValue = 64
        sizeSlider.maxValue = 400
        sizeSlider.doubleValue = Double(preferences.thumbnailSize)
        sizeSlider.isContinuous = true
        sizeSlider.controlSize = .small
        sizeSlider.target = self
        sizeSlider.action = #selector(thumbnailSizeChanged)
        sizeSlider.setAccessibilityLabel("Thumbnail size")
        regularGridButton.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        let mosaic = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            for rect in [NSRect(x: 1, y: 1, width: 4, height: 14), NSRect(x: 7, y: 9, width: 8, height: 6),
                         NSRect(x: 7, y: 1, width: 3, height: 6), NSRect(x: 12, y: 1, width: 3, height: 6)] {
                NSBezierPath(roundedRect: rect, xRadius: 0.7, yRadius: 0.7).fill()
            }
            return true
        }
        mosaic.isTemplate = true
        adaptiveGridButton.image = mosaic
        for (index, button) in [regularGridButton, adaptiveGridButton].enumerated() {
            let title = index == 0 ? "Regular grid" : "Adaptive grid"
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .circular
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.tag = index
            button.target = self
            button.action = #selector(gridModeChanged(_:))
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        updateGridButtons()
        let large = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage())
        large.contentTintColor = .secondaryLabelColor
        large.widthAnchor.constraint(equalToConstant: 18).isActive = true
        large.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let sizing = NSStackView(views: [regularGridButton, adaptiveGridButton, sizeSlider, large])
        sizing.spacing = 8
        for view in [search, locateButton, sort, scroll, empty, line, sizing] {
            view.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: body.topAnchor),
            search.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: locateButton.leadingAnchor, constant: -6),
            locateButton.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -14),
            locateButton.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            locateButton.widthAnchor.constraint(equalToConstant: 26),
            locateButton.heightAnchor.constraint(equalToConstant: 22),
            sort.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            sort.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            sort.trailingAnchor.constraint(equalTo: locateButton.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sort.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -5),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            sizing.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 14),
            sizing.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -16),
            sizing.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -12),
            sizing.heightAnchor.constraint(equalToConstant: 22),
            line.leadingAnchor.constraint(equalTo: sizing.leadingAnchor), line.trailingAnchor.constraint(equalTo: sizing.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: sizing.topAnchor, constant: -9)
        ])
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.onResize = { [weak self] width in self?.onWidthChange?(width) }
        addSubview(handle)
        NSLayoutConstraint.activate([
            handle.trailingAnchor.constraint(equalTo: trailingAnchor), handle.widthAnchor.constraint(equalToConstant: 8),
            handle.topAnchor.constraint(equalTo: topAnchor, constant: 16), handle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        cleanupTimer?.invalidate()
        queue.cancelAllOperations()
        if let clipObservation { NotificationCenter.default.removeObserver(clipObservation) }
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 16, cornerHeight: 16, transform: nil)
        scroll.layoutSubtreeIfNeeded()
        updateGrid()
    }

    private func updateGrid(force: Bool = false) {
        guard !isCollapsed, !updatingGrid else { return }
        let width = scroll.contentView.bounds.width
        guard width > 0 else { return }
        updatingGrid = true
        defer { updatingGrid = false }
        if gridMode == .adaptive { requestImageSizes() }
        let oldLayout = collection.collectionViewLayout
        let current = session?.selected
        let currentPath = documents.firstIndex { $0 === current }.map { IndexPath(item: $0, section: 0) }
        let currentWasVisible = currentPath.flatMap { oldLayout?.layoutAttributesForItem(at: $0)?.frame }
            .map { $0.intersects(collection.visibleRect) } ?? false
        let anchor = oldLayout?.layoutAttributesForElements(in: collection.visibleRect)
            .min { $0.frame.minY < $1.frame.minY }
        let anchorOffset = anchor.map { collection.visibleRect.minY - $0.frame.minY } ?? 0
        if collection.frame.width != width {
            collection.setFrameSize(NSSize(width: width, height: collection.frame.height))
        }
        let metrics = ThumbnailGridMetrics(availableWidth: width, thumbnailSize: preferences.thumbnailSize)
        let adaptive = gridMode == .adaptive
        let desired: NSCollectionViewLayout = adaptive ? adaptiveLayout : flow
        let sizes = documents.map { imageSizes[$0.url] }
        let loadingPlaceholders = adaptive && !metadataTasks.isEmpty
        let changed = force || oldLayout !== desired || flow.itemSize != metrics.itemSize ||
            (adaptive && (adaptiveWidth != width || adaptiveLayout.thumbnailSize != thumbnailSize ||
                          adaptiveLayout.imageSizes != sizes || adaptiveLayout.usesLoadingPlaceholders != loadingPlaceholders))
        if changed {
            flow.itemSize = metrics.itemSize
            adaptiveWidth = width
            adaptiveLayout.thumbnailSize = thumbnailSize
            adaptiveLayout.imageSizes = sizes
            adaptiveLayout.usesLoadingPlaceholders = loadingPlaceholders
            if oldLayout !== desired { collection.collectionViewLayout = desired }
            desired.invalidateLayout()
            collection.layoutSubtreeIfNeeded()
            if let path = anchor?.indexPath, let frame = desired.layoutAttributesForItem(at: path)?.frame {
                let clip = scroll.contentView
                let rect = NSRect(x: clip.bounds.minX, y: frame.minY + anchorOffset,
                                  width: clip.bounds.width, height: clip.bounds.height)
                clip.scroll(to: clip.constrainBoundsRect(rect).origin)
                scroll.reflectScrolledClipView(clip)
            }
            for item in collection.visibleItems() {
                if let index = collection.indexPath(for: item)?.item, documents.indices.contains(index) {
                    if let item = item as? ThumbnailItem { configure(item, document: documents[index]) }
                }
            }
        }
        setPreparingGrid(adaptive && !metadataTasks.isEmpty)
        // Metadata may turn preceding one-cell placeholders into multirow
        // cards. Keep the open file visible if it was visible before the change,
        // but preserve a user's scroll position when they browsed elsewhere.
        if let current, let path = currentPath,
           revealAfterLayout === current || (changed && currentWasVisible) {
            if revealItem(at: path) { revealAfterLayout = nil }
        }
    }

    private func configure(_ item: ThumbnailItem, document: ImageDocument) {
        item.card.configure(document, size: thumbnailSize, adaptive: gridMode == .adaptive, sourcePixels: imageSizes[document.url])
        let preview = item.card.preview
        preview.waitsForLayout = isPreparingGrid
        let version = thumbnailVersions[document.url] ?? cacheGeneration
        if preview.representedURL != document.url {
            preview.representedURL = document.url
            preview.revision = version
            preview.image = cache?.image(document.url)
        } else if preview.image == nil || preview.revision != version {
            // A changed source keeps its old preview until the new one is ready.
            if let image = cache?.image(document.url) {
                preview.image = image
                preview.revision = version
            }
        }
        if cache?.contains(document.url) == false && !document.isMissing {
            requestThumbnail(document.url)
        }
        preview.isLoading = requested.contains(document.url)
    }

    private func setPreparingGrid(_ preparing: Bool) {
        guard isPreparingGrid != preparing else { return }
        isPreparingGrid = preparing
        for item in collection.visibleItems() {
            (item.view as? ThumbnailCard)?.preview.waitsForLayout = preparing
        }
    }

    private func updateGridButtons() {
        for (button, mode) in [(regularGridButton, ThumbnailGridMode.regular), (adaptiveGridButton, .adaptive)] {
            button.state = gridMode == mode ? .on : .off
            button.contentTintColor = gridMode == mode ? .controlAccentColor : .secondaryLabelColor
        }
    }

    @objc private func gridModeChanged(_ sender: NSButton) {
        preferences.setGridMode(sender === regularGridButton ? .regular : .adaptive)
        updateGridButtons()
        updateGrid(force: true)
    }

    private func requestImageSizes() {
        let pending = documents.compactMap { document -> (URL, UUID?)? in
            guard imageSizes[document.url] == nil, metadataRequested.insert(document.url).inserted else { return nil }
            return (document.url, thumbnailVersions[document.url])
        }
        guard !pending.isEmpty else { return }
        let task = UUID()
        metadataTasks.insert(task)
        setPreparingGrid(true)
        let generation = cacheGeneration
        let readSize = loadImageSize
        metadataReadCount += pending.count
        queue.addOperation { [weak self] in
            let sizes = pending.map { ($0.0, $0.1, readSize($0.0)) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.cacheGeneration == generation else { return }
                self.metadataTasks.remove(task)
                for (url, version, size) in sizes where self.thumbnailVersions[url] == version && self.trackedURLs.contains(url) {
                    if let size { self.imageSizes[url] = size }
                }
                if self.gridMode == .adaptive { self.updateGrid(force: true) }
                else { self.setPreparingGrid(false) }
            }
        }
    }

    func rememberWidth(_ value: CGFloat) { preferences.setWidth(value) }
    func invalidateThumbnail(_ url: URL) {
        cache?.remove(url)
        imageSizes.removeValue(forKey: url)
        metadataRequested.remove(url)
        thumbnailVersions[url] = UUID()
        requested.remove(url)
    }

    func endThumbnailSession() {
        resetKeyboardNavigation()
        revealAfterLayout = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        cacheGeneration = UUID()
        queue.cancelAllOperations()
        cache = nil
        requested.removeAll()
        thumbnailVersions.removeAll()
        imageSizes.removeAll()
        metadataRequested.removeAll()
        metadataTasks.removeAll()
        setPreparingGrid(false)
        sourceRevisions.removeAll()
        trackedURLs.removeAll()
        for item in collection.visibleItems() {
            guard let preview = (item as? ThumbnailItem)?.card.preview else { continue }
            preview.image = nil
            preview.representedURL = nil
            preview.isLoading = false
            preview.waitsForLayout = false
        }
    }

    func cleanThumbnailCache() {
        let keep = Set(session?.documents.map(\.url) ?? [])
        cache?.prune(keeping: keep)
        // Visible cards retain their NSImages. Only unreferenced RAM entries
        // are released; every ready PNG survives until this folder is closed.
        cache?.releaseMemory()
        for url in trackedURLs.subtracting(keep) {
            thumbnailVersions.removeValue(forKey: url)
            imageSizes.removeValue(forKey: url)
            metadataRequested.remove(url)
            sourceRevisions.removeValue(forKey: url)
            requested.remove(url)
        }
        trackedURLs = keep
    }

    @objc func toggleCollapsed() {
        isCollapsed.toggle()
        if isCollapsed {
            bodyBottom.isActive = false
            foldedBodyHeight = body.heightAnchor.constraint(equalToConstant: max(200, body.bounds.height))
            foldedBodyHeight?.isActive = true
        } else {
            foldedBodyHeight?.isActive = false
            foldedBodyHeight = nil
            bodyBottom.isActive = true
        }
        body.isHidden = isCollapsed
        handle.isHidden = isCollapsed
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor {
            window?.makeFirstResponder(nil)
        }
        updateCollapseButton()
        onCollapseChange?()
    }

    private func updateCollapseButton() {
        let title = isCollapsed ? "Expand sidebar" : "Collapse sidebar"
        collapseButton.image = NSImage(systemSymbolName: isCollapsed ? "chevron.down" : "chevron.up",
                                        accessibilityDescription: title)
        collapseButton.setAccessibilityLabel(title)
        collapseButton.toolTip = title
        heading.toolTip = title
    }

    func display(_ session: FolderSession, revealSelection: Bool = true, selectCurrent: Bool = true) {
        let selected = Set(selectedDocuments.map { ObjectIdentifier($0) })
        let oldDocuments = documents.map { ObjectIdentifier($0) }
        let newSession = self.session !== session || cache == nil
        if newSession {
            endThumbnailSession()
            cache = ThumbnailCache()
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.cleanThumbnailCache()
                TemporarySession.removeAbandoned()
            }
        }
        self.session = session
        for document in session.documents {
            if !trackedURLs.contains(document.url) { thumbnailVersions[document.url] = UUID() }
            if trackedURLs.contains(document.url), sourceRevisions[document.url] != document.revision {
                invalidateThumbnail(document.url)
            }
            sourceRevisions[document.url] = document.revision
        }
        let keep = Set(session.documents.map(\.url))
        cache?.prune(keeping: keep)
        for url in trackedURLs.subtracting(keep) {
            thumbnailVersions.removeValue(forKey: url)
            imageSizes.removeValue(forKey: url)
            metadataRequested.remove(url)
            sourceRevisions.removeValue(forKey: url)
            requested.remove(url)
        }
        trackedURLs = keep
        locateButton.isEnabled = session.selected != nil
        session.descending = preferences.descending
        session.sortKey = preferences.sortKey
        session.filterText = search.stringValue
        documents = session.visibleDocuments
        if newSession || oldDocuments != documents.map({ ObjectIdentifier($0) }) ||
            (selectCurrent && navigationFocus !== session.selected) { resetKeyboardNavigation() }
        heading.title = session.directory.lastPathComponent
        heading.toolTip = session.directory.path
        empty.stringValue = search.stringValue.isEmpty ? "No images" : "No matches"
        empty.isHidden = !documents.isEmpty
        if selectCurrent, revealSelection, let current = session.selected, documents.contains(where: { $0 === current }) {
            revealAfterLayout = current
        }
        selecting = true
        if newSession || oldDocuments != documents.map({ ObjectIdentifier($0) }) { collection.reloadData() }
        else {
            for item in collection.visibleItems() {
                if let path = collection.indexPath(for: item), documents.indices.contains(path.item) {
                    if let item = item as? ThumbnailItem { configure(item, document: documents[path.item]) }
                }
            }
        }
        updateGrid()
        collection.selectionIndexPaths = Set(documents.indices.compactMap { index in
            selected.contains(ObjectIdentifier(documents[index])) ? IndexPath(item: index, section: 0) : nil
        })
        if selectCurrent, let current = session.selected, let index = documents.firstIndex(where: { $0 === current }) {
            let path = IndexPath(item: index, section: 0)
            if !collection.selectionIndexPaths.contains(path) { collection.selectionIndexPaths = [path] }
            if revealSelection, revealItem(at: path) { revealAfterLayout = nil }
        }
        selecting = false
        if isCollapsed { onCollapseChange?() }
    }

    func setSelection(_ selected: [ImageDocument]) {
        resetKeyboardNavigation()
        let ids = Set(selected.map { ObjectIdentifier($0) })
        selecting = true
        collection.selectionIndexPaths = Set(documents.indices.compactMap {
            ids.contains(ObjectIdentifier(documents[$0])) ? IndexPath(item: $0, section: 0) : nil
        })
        selecting = false
        onSelectionChange?()
    }

    func selectAllFiles() { setSelection(documents) }
    func deselectAllFiles() { setSelection([]) }

    private func resetKeyboardNavigation() {
        navigationFocus = nil
        navigationAnchor = nil
        collection.focusedPath = nil
    }

    @discardableResult func navigate(_ action: FileNavigation, extendingSelection: Bool = false) -> Bool {
        guard !documents.isEmpty else { return false }
        if isCollapsed { toggleCollapsed() }
        layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
        selectionNotification?.cancel()
        let selectedPaths = collection.selectionIndexPaths
        let focus = navigationFocus.flatMap { focused in documents.firstIndex { $0 === focused } }
        let clicked = collection.focusedPath.flatMap { selectedPaths.contains($0) ? $0.item : nil }
        let opened = documents.firstIndex(where: { $0 === session?.selected })
        let selectedOpen = opened.flatMap { selectedPaths.isEmpty || selectedPaths.contains(IndexPath(item: $0, section: 0)) ? $0 : nil }
        let current = focus ?? clicked ?? selectedOpen ?? selectedPaths.sorted().last?.item ?? opened ?? 0
        let frames = documents.indices.map { index in
            collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame ?? .zero
        }
        let pageHeight = max(1, scroll.contentView.bounds.height - scroll.verticalPageScroll)
        guard let target = action.target(from: current, frames: frames, pageHeight: pageHeight) else { return false }
        if extendingSelection {
            if navigationAnchor == nil { navigationAnchor = documents[current] }
        } else { navigationAnchor = nil }
        let anchor = navigationAnchor.flatMap { anchored in documents.firstIndex { $0 === anchored } } ?? target
        let path = IndexPath(item: target, section: 0)
        selecting = true
        collection.selectionIndexPaths = Set((min(anchor, target)...max(anchor, target)).map { IndexPath(item: $0, section: 0) })
        collection.focusedPath = path
        navigationFocus = documents[target]
        // Move by a viewport first; revealItem then makes the nearest row fully
        // visible, rather than reducing a page key to a tiny nearest-edge scroll.
        if action == .pageUp || action == .pageDown {
            let clip = scroll.contentView
            let proposed = clip.bounds.offsetBy(dx: 0, dy: action == .pageDown ? pageHeight : -pageHeight)
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(clip)
        }
        revealAfterLayout = documents[target]
        if revealItem(at: path) { revealAfterLayout = nil }
        selecting = false
        window?.makeFirstResponder(collection)
        onSelectionChange?()
        onSelect?(documents[target].url)
        return true
    }

    func update(_ document: ImageDocument) {
        guard let index = documents.firstIndex(where: { $0 === document }),
              let item = collection.item(at: IndexPath(item: index, section: 0)) as? ThumbnailItem else { return }
        configure(item, document: document)
    }

    @objc func revealSelection() {
        resetKeyboardNavigation()
        guard let session, let current = session.selected else { return }
        if isCollapsed { toggleCollapsed() }
        // A filter can hide the open image; clear it only when necessary to
        // make the requested thumbnail visible.
        if !documents.contains(where: { $0 === current }) {
            search.stringValue = ""
            display(session, revealSelection: false)
            onListChange?()
        }
        layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
        guard let index = documents.firstIndex(where: { $0 === current }) else { return }
        let path = IndexPath(item: index, section: 0)
        selecting = true
        collection.selectionIndexPaths = [path]
        revealAfterLayout = current
        if revealItem(at: path) { revealAfterLayout = nil }
        selecting = false
        window?.makeFirstResponder(collection)
    }

    @discardableResult private func revealItem(at path: IndexPath) -> Bool {
        collection.layoutSubtreeIfNeeded()
        guard let frame = collection.collectionViewLayout?.layoutAttributesForItem(at: path)?.frame else { return false }
        let clip = scroll.contentView
        guard clip.bounds.width > 0, clip.bounds.height > 0, !frame.isEmpty else { return false }
        let rect = clip.convert(frame, from: collection)
        guard !clip.bounds.contains(rect) else { return true }
        let visible = clip.bounds
        var y = visible.minY
        if rect.height > visible.height {
            // A multirow card can never fit completely. Keep its visible part
            // steady; when offscreen, reveal its nearest edge, not its centre.
            if rect.maxY > visible.minY && rect.minY < visible.maxY { return true }
            y = rect.minY >= visible.maxY ? rect.minY : rect.maxY - visible.height
        } else if rect.minY < visible.minY { y = rect.minY }
        else if rect.maxY > visible.maxY { y = rect.maxY - visible.height }
        let target = NSRect(x: visible.minX, y: y,
                            width: clip.bounds.width, height: clip.bounds.height)
        // Scroll the clip explicitly: NSCollectionView's nearest-edge scrolling
        // can leave an already selected, recycled item outside its visible area.
        clip.scroll(to: clip.constrainBoundsRect(target).origin)
        scroll.reflectScrolledClipView(clip)
        return clip.bounds.intersects(rect)
    }

    @objc private func sortChanged() {
        preferences.setSortKey(ImageSortKey.allCases[sort.indexOfSelectedItem / 2])
        preferences.setDescending(sort.indexOfSelectedItem % 2 == 1)
        if let session { display(session, revealSelection: false, selectCurrent: false) }
        onListChange?()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === search else { return }
        if let session { display(session, revealSelection: false, selectCurrent: false) }
        onListChange?()
    }

    @objc private func thumbnailSizeChanged() {
        preferences.setThumbnailSize(CGFloat(sizeSlider.doubleValue))
        onWidthChange?(max(bounds.width, SidebarPreferences.minimumWidth(thumbnailSize: preferences.thumbnailSize)))
        collection.collectionViewLayout?.invalidateLayout()
        if let session { display(session, revealSelection: false, selectCurrent: false) }
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { documents.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let document = documents[indexPath.item]
        let item = collection.makeItem(withIdentifier: .init("thumbnail"), for: indexPath) as! ThumbnailItem
        configure(item, document: document)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selectionChanged(preferred: collection.focusedPath ?? indexPaths.sorted().last)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selectionChanged(preferred: nil)
    }

    private func selectionChanged(preferred: IndexPath?) {
        guard !selecting else { return }
        resetKeyboardNavigation()
        selectionNotification?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onSelectionChange?()
            let paths = self.collection.selectionIndexPaths
            let target = preferred.flatMap { paths.contains($0) ? $0 : nil }
                ?? paths.sorted().last
            if let target, self.documents.indices.contains(target.item) {
                self.onSelect?(self.documents[target.item].url)
            }
        }
        selectionNotification = task
        DispatchQueue.main.async(execute: task)
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        documents[indexPath.item].isMissing ? nil : documents[indexPath.item].url as NSURL
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard draggingInfo.draggingSource as? NSCollectionView !== collection,
              !FileClipboard.files(draggingInfo.draggingPasteboard).isEmpty else { return [] }
        proposedDropOperation.pointee = .before
        return .copy
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let urls = FileClipboard.files(draggingInfo.draggingPasteboard)
        guard !urls.isEmpty, onImport != nil else { return false }
        onImport?(urls)
        return true
    }

    private func requestThumbnail(_ url: URL) {
        guard let cache, !cache.contains(url), requested.insert(url).inserted else { return }
        let generation = cacheGeneration
        let version = thumbnailVersions[url]
        let decodeThumbnail = loadThumbnail
        thumbnailLoadCount += 1
        queue.addOperation { [weak self] in
            let thumbnail = decodeThumbnail(url, cache.session)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.cacheGeneration == generation, self.thumbnailVersions[url] == version,
                      self.trackedURLs.contains(url) else {
                    if let file = thumbnail?.file { try? FileManager.default.removeItem(at: file) }
                    return
                }
                if let thumbnail { self.imageSizes[url] = thumbnail.pixels }
                if let image = cache.insert(thumbnail, for: url) {
                    if let index = self.documents.firstIndex(where: { $0.url == url }),
                       let item = self.collection.item(at: IndexPath(item: index, section: 0)) as? ThumbnailItem {
                        item.card.preview.sourcePixels = self.imageSizes[url]
                        item.card.preview.image = image
                        item.card.preview.revision = version ?? generation
                    }
                }
                self.requested.remove(url)
                if let index = self.documents.firstIndex(where: { $0.url == url }),
                   let item = self.collection.item(at: IndexPath(item: index, section: 0)) as? ThumbnailItem {
                    self.configure(item, document: self.documents[index])
                }
                self.updateGrid()
            }
        }
    }
}
