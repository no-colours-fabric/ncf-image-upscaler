import AppKit

final class ViewerBackground: NSView {
    var showsTransparency = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = dirtyRect.intersection(bounds)
        guard !rect.isEmpty else { return }
        guard showsTransparency else { NSColor.black.setFill(); rect.fill(); return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        rect.clip()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor(white: dark ? 0.21 : 0.96, alpha: 1).setFill()
        rect.fill()
        // Coordinates belong to the viewer, outside the magnified/scrolled
        // document. Both cell size and grid origin stay fixed on screen.
        let side: CGFloat = 9
        let squares = NSBezierPath()
        for row in Int(floor(rect.minY / side))..<Int(ceil(rect.maxY / side)) {
            for col in Int(floor(rect.minX / side))..<Int(ceil(rect.maxX / side)) where (row + col) % 2 == 0 {
                squares.appendRect(NSRect(x: CGFloat(col) * side, y: CGFloat(row) * side,
                                          width: side, height: side))
            }
        }
        NSColor(white: dark ? 0.28 : 0.87, alpha: 1).setFill()
        squares.fill()
    }
}

final class CenteredClipView: NSClipView {
    var leadingObstruction: CGFloat = 0
    var onDoubleClick: (() -> Void)?
    var fileMenu: (() -> NSMenu)?
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(documentView)
        return fileMenu?()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount > 0, event.clickCount.isMultiple(of: 2) { onDoubleClick?() }
        else { super.mouseDown(with: event) }
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return result }
        // The clip still draws across the whole window, behind the translucent
        // panel. Centering and pan limits use its unobscured part instead.
        let inset = leadingObstruction * result.width / max(1, frame.width)
        let availableWidth = result.width - inset
        if availableWidth > documentView.frame.width {
            result.origin.x = documentView.frame.minX + (documentView.frame.width - availableWidth) / 2 - inset
        } else {
            result.origin.x = min(documentView.frame.maxX - result.width,
                                  max(documentView.frame.minX - inset, proposedBounds.minX))
        }
        if result.height > documentView.frame.height {
            result.origin.y = (documentView.frame.height - result.height) / 2
        }
        return result
    }
}

final class ZoomScrollView: NSScrollView {
    var onZoom: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let change = event.scrollingDeltaY
        guard change != 0 else { return }
        let factor = exp(change * (event.hasPreciseScrollingDeltas ? 0.008 : 0.055))
        let value = min(maxMagnification, max(minMagnification, magnification * factor))
        let point = documentView?.convert(event.locationInWindow, from: nil) ?? .zero
        setMagnification(value, centeredAt: point)
        onZoom?()
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        onZoom?()
    }
}

final class ImageCanvas: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var original: ImageAsset?
    var enhanced: ImageAsset?
    var dividerInDocument: CGFloat = 0
    var onDrop: ((URL) -> Void)?
    var onDoubleClick: (() -> Void)?
    var fileMenu: (() -> NSMenu)?
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        return fileMenu?()
    }
    private var dragStart: NSPoint?
    private var scrollStart = NSPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityLabel("Image comparison")
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        // AppKit can request an area larger than a centered, magnified document.
        // Never paint the viewport outside the current image rectangle.
        let dirtyRect = dirtyRect.intersection(bounds)
        guard !dirtyRect.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        guard let original else { return }
        NSGraphicsContext.current?.cgContext.interpolationQuality = .high
        if let enhanced {
            // Draw each version only on its own side. Clearing a previously
            // composited half would also erase the fixed background underneath.
            let split = min(bounds.maxX, max(bounds.minX, dividerInDocument))
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: bounds.minX, y: bounds.minY, width: split - bounds.minX, height: bounds.height).clip()
            original.image.draw(in: bounds, from: .zero, operation: .sourceOver,
                                fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: split, y: bounds.minY, width: bounds.maxX - split, height: bounds.height).clip()
            enhanced.image.draw(in: bounds, from: .zero, operation: .sourceOver,
                                fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            original.image.draw(in: bounds, from: .zero, operation: .sourceOver,
                                fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount > 0, event.clickCount.isMultiple(of: 2) {
            onDoubleClick?()
            return
        }
        window?.makeFirstResponder(self)
        guard let scroll = enclosingScrollView else { return }
        dragStart = event.locationInWindow
        scrollStart = scroll.contentView.bounds.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let current = clip.convert(event.locationInWindow, from: nil)
        let initial = clip.convert(start, from: nil)
        pan(to: NSPoint(x: scrollStart.x - (current.x - initial.x),
                        y: scrollStart.y - (current.y - initial.y)))
    }

    func pan(to origin: NSPoint) {
        guard origin.x.isFinite, origin.y.isFinite, let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let proposed = NSRect(origin: origin, size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { NSCursor.pop() }
        dragStart = nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                            options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first else {
            return false
        }
        onDrop?(url)
        return true
    }
}

final class DividerOverlay: NSView {
    override var isFlipped: Bool { true }
    var imageRect = NSRect.zero
    var fraction: CGFloat = 0.5
    var onChange: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var fileMenu: (() -> NSMenu)?
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder((superview as? ComparisonView)?.canvas)
        return fileMenu?()
    }
    var hasVisibleImage: Bool {
        !imageRect.isEmpty && imageRect.minX.isFinite && imageRect.minY.isFinite &&
            imageRect.maxX.isFinite && imageRect.maxY.isFinite
    }
    var dividerX: CGFloat { hasVisibleImage ? imageRect.minX + imageRect.width * fraction : 0 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Comparison divider: original on the left, result on the right")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityValue() -> Any? { Int((fraction * 100).rounded()) }
    override func accessibilityPerformIncrement() -> Bool { moveDivider(0.05); return true }
    override func accessibilityPerformDecrement() -> Bool { moveDivider(-0.05); return true }

    private func moveDivider(_ amount: CGFloat) {
        fraction = min(1, max(0, fraction + amount))
        needsDisplay = true
        onChange?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, hasVisibleImage, imageRect.contains(point), abs(point.x - dividerX) < 13 else { return nil }
        return self
    }

    override func resetCursorRects() {
        guard !isHidden, hasVisibleImage, dividerX.isFinite else { return }
        let rect = NSRect(x: dividerX - 13, y: imageRect.minY, width: 26, height: imageRect.height)
            .intersection(bounds)
        guard !rect.isEmpty else { return }
        addCursorRect(rect, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hasVisibleImage else { return }
        NSGraphicsContext.saveGraphicsState()
        imageRect.clip()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: dividerX, y: imageRect.minY))
        line.line(to: NSPoint(x: dividerX, y: imageRect.maxY))
        line.lineWidth = 1
        line.stroke()
        let knob = NSBezierPath(ovalIn: NSRect(x: dividerX - 10, y: imageRect.midY - 10,
                                              width: 20, height: 20))
        NSColor.white.setFill()
        knob.fill()
        shadow.shadowBlurRadius = 0
        shadow.set()
        NSColor(white: 0.30, alpha: 1).setStroke()
        let marks = NSBezierPath()
        for offset: CGFloat in [-3, 3] {
            marks.move(to: NSPoint(x: dividerX + offset, y: imageRect.midY - 4))
            marks.line(to: NSPoint(x: dividerX + offset, y: imageRect.midY + 4))
        }
        marks.lineWidth = 1.2
        marks.stroke()
        NSGraphicsContext.restoreGraphicsState()
        drawBadge("Original", at: NSPoint(x: imageRect.minX + 12, y: imageRect.minY + 12))
        let textWidth = ("Result" as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]).width + 18
        drawBadge("Result", at: NSPoint(x: imageRect.maxX - textWidth - 12, y: imageRect.minY + 12))
    }

    private func drawBadge(_ title: String, at point: NSPoint) {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(x: point.x, y: point.y, width: size.width + 18, height: 24)
        NSColor.black.withAlphaComponent(0.50).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        text.draw(at: NSPoint(x: point.x + 9, y: point.y + 5), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount > 0, event.clickCount.isMultiple(of: 2) { onDoubleClick?() }
        else { update(event) }
    }
    override func mouseDragged(with event: NSEvent) { update(event) }
    private func update(_ event: NSEvent) {
        guard hasVisibleImage else { return }
        let point = convert(event.locationInWindow, from: nil)
        fraction = min(1, max(0, (point.x - imageRect.minX) / max(1, imageRect.width)))
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onChange?()
    }
}

struct PreviewPosition {
    let displayedWidth: CGFloat
    let center: NSPoint
    let fraction: CGFloat
    let fitting: Bool
}

final class ComparisonView: NSView {
    let background = ViewerBackground()
    let scroll = ZoomScrollView()
    let canvas = ImageCanvas(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    let divider = DividerOverlay()
    let loadingProgress = NSProgressIndicator()
    var onZoom: ((CGFloat) -> Void)?
    var onDrop: ((URL) -> Void)?
    var fileMenu: (() -> NSMenu)? {
        didSet {
            canvas.fileMenu = fileMenu
            divider.fileMenu = fileMenu
            (scroll.contentView as? CenteredClipView)?.fileMenu = fileMenu
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(canvas)
        return fileMenu?()
    }
    private var observations: [NSObjectProtocol] = []
    private var previousViewport = NSRect.zero
    var leadingObstruction: CGFloat = 0 {
        didSet {
            guard leadingObstruction != oldValue else { return }
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }
    // Drawing extends under the floating panel; fit, center and the divider
    // share the unobscured viewport to its right.
    var viewport: NSRect {
        let leading = min(max(0, leadingObstruction), max(0, bounds.width - 1))
        return NSRect(x: bounds.minX + leading, y: bounds.minY,
                      width: bounds.width - leading, height: bounds.height)
    }
    var comparisonViewport: NSRect { viewport }
    private var visibleCenter: NSPoint {
        canvas.convert(NSPoint(x: viewport.midX, y: viewport.midY), from: self)
    }
    private(set) var fitting = true
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        scroll.contentView = CenteredClipView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.01
        scroll.maxMagnification = 32
        scroll.contentView.postsBoundsChangedNotifications = true
        addSubview(background)
        addSubview(scroll)
        addSubview(divider)
        divider.isHidden = true
        loadingProgress.style = .bar
        loadingProgress.controlSize = .small
        loadingProgress.isIndeterminate = true
        loadingProgress.isDisplayedWhenStopped = false
        loadingProgress.isHidden = true
        loadingProgress.setAccessibilityLabel("Loading image")
        addSubview(loadingProgress)
        divider.onChange = { [weak self] in self?.refreshDivider() }
        scroll.onZoom = { [weak self] in
            self?.fitting = false
            self?.refreshDivider()
            if let self { self.onZoom?(self.scroll.magnification) }
        }
        canvas.onDrop = { [weak self] url in self?.onDrop?(url) }
        canvas.onDoubleClick = { [weak self] in self?.toggleFitAndActualSize() }
        divider.onDoubleClick = { [weak self] in self?.toggleFitAndActualSize() }
        (scroll.contentView as? CenteredClipView)?.onDoubleClick = { [weak self] in self?.toggleFitAndActualSize() }
        observations.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in self?.refreshDivider() })
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { for item in observations { NotificationCenter.default.removeObserver(item) } }

    override func layout() {
        super.layout()
        let oldCenter = canvas.convert(NSPoint(x: previousViewport.midX, y: previousViewport.midY), from: self)
        let resized = previousViewport != viewport
        let hadViewport = !previousViewport.isEmpty
        previousViewport = viewport
        background.frame = bounds
        scroll.frame = bounds
        (scroll.contentView as? CenteredClipView)?.leadingObstruction = viewport.minX - bounds.minX
        divider.frame = bounds
        loadingProgress.frame = NSRect(x: viewport.minX + 16, y: viewport.maxY - 20,
                                       width: min(80, max(0, viewport.width - 32)), height: 4)
        if resized, canvas.original != nil {
            if fitting { fit() }
            else if hadViewport { center(on: oldCenter) }
        }
        refreshDivider()
    }

    func setLoading(_ loading: Bool) {
        loadingProgress.isHidden = !loading
        if loading { loadingProgress.startAnimation(nil) }
        else { loadingProgress.stopAnimation(nil) }
    }

    func setOriginal(_ asset: ImageAsset) {
        scroll.magnification = 1
        canvas.original = asset
        canvas.enhanced = nil
        background.showsTransparency = asset.hasAlpha
        canvas.frame.size = asset.pixels
        canvas.bounds.size = asset.pixels
        divider.fraction = 0.5
        divider.isHidden = true
        fit()
        // First opening may shrink a large image, but must not enlarge a small
        // one. Explicit fitting and restoring a session can still zoom past 1.
        if scroll.magnification > 1 { actualSize() }
        canvas.needsDisplay = true
    }

    func clear() {
        canvas.original = nil
        canvas.enhanced = nil
        background.showsTransparency = false
        divider.isHidden = true
        canvas.needsDisplay = true
        scroll.contentView.needsDisplay = true
    }

    func position() -> PreviewPosition {
        let size = canvas.bounds.size
        return PreviewPosition(displayedWidth: size.width * scroll.magnification,
            center: NSPoint(x: visibleCenter.x / max(1, size.width),
                            y: visibleCenter.y / max(1, size.height)),
            fraction: divider.fraction, fitting: fitting)
    }

    func restore(_ position: PreviewPosition) {
        divider.fraction = position.fraction
        if position.fitting { fit() }
        else {
            fitting = false
            let zoom = position.displayedWidth / max(1, canvas.bounds.width)
            setZoom(min(scroll.maxMagnification, max(scroll.minMagnification, zoom)),
                centeredAt: NSPoint(x: position.center.x * canvas.bounds.width,
                                   y: position.center.y * canvas.bounds.height))
            onZoom?(scroll.magnification)
        }
        refreshDivider()
    }

    func setEnhanced(_ asset: ImageAsset) {
        let wasFitting = fitting
        let oldSize = canvas.bounds.size
        let center = NSPoint(x: visibleCenter.x / oldSize.width,
                             y: visibleCenter.y / oldSize.height)
        let zoom = scroll.magnification * oldSize.width / asset.pixels.width
        canvas.enhanced = asset
        background.showsTransparency = canvas.original?.hasAlpha == true || asset.hasAlpha
        scroll.magnification = 1
        canvas.frame.size = asset.pixels
        canvas.bounds.size = asset.pixels
        divider.isHidden = false
        if wasFitting { fit() }
        else {
            setZoom(max(scroll.minMagnification, zoom),
                centeredAt: NSPoint(x: center.x * asset.pixels.width, y: center.y * asset.pixels.height))
        }
        refreshDivider()
        canvas.needsDisplay = true
        onZoom?(scroll.magnification)
    }

    func fit() {
        guard canvas.original != nil, viewport.width > 0, viewport.height > 0 else { return }
        fitting = true
        let value = max(scroll.minMagnification,
                        min((viewport.width - 48) / canvas.bounds.width,
                            (viewport.height - 48) / canvas.bounds.height))
        // Tiny images may need more than the normal wheel-zoom ceiling to fit.
        scroll.maxMagnification = max(32, value)
        setZoom(value,
                                centeredAt: NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
        refreshDivider()
        onZoom?(scroll.magnification)
    }

    func actualSize() {
        fitting = false
        setZoom(1, centeredAt: visibleCenter)
        refreshDivider()
        onZoom?(1)
    }

    func toggleFitAndActualSize() {
        guard canvas.original != nil else { return }
        if fitting { actualSize() }
        else { fit() }
    }

    func zoomBy(_ factor: CGFloat) {
        fitting = false
        let value = min(scroll.maxMagnification, max(scroll.minMagnification, scroll.magnification * factor))
        setZoom(value, centeredAt: visibleCenter)
        refreshDivider()
        onZoom?(value)
    }

    private func setZoom(_ value: CGFloat, centeredAt point: NSPoint) {
        scroll.setMagnification(value, centeredAt: point)
        center(on: point)
    }

    private func center(on point: NSPoint) {
        let clip = scroll.contentView
        let target = clip.convert(point, from: canvas)
        let current = clip.convert(NSPoint(x: viewport.midX, y: viewport.midY), from: self)
        canvas.pan(to: NSPoint(x: clip.bounds.minX + target.x - current.x,
                              y: clip.bounds.minY + target.y - current.y))
    }

    private func refreshDivider() {
        // Exposed space belongs to the clip view, including before enhancement
        // when the comparison overlay is hidden.
        scroll.contentView.needsDisplay = true
        background.needsDisplay = true
        guard !divider.isHidden else { return }
        let visible = canvas.convert(canvas.bounds, to: divider).intersection(comparisonViewport)
        // CGRect.null has infinite origins. AppKit rejects those coordinates
        // when registering cursor regions after an image leaves the viewport.
        divider.imageRect = visible.isNull || visible.isEmpty ? .zero : visible
        canvas.dividerInDocument = divider.hasVisibleImage
            ? canvas.convert(NSPoint(x: divider.dividerX, y: 0), from: divider).x : 0
        canvas.needsDisplay = true
        divider.needsDisplay = true
        window?.invalidateCursorRects(for: divider)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                            options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first else {
            return false
        }
        onDrop?(url)
        return true
    }
}
