import AppKit
import UniformTypeIdentifiers

enum FileNavigation: Equatable {
    case pageUp, pageDown, first, last

    static func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags) -> FileNavigation? {
        let flags = modifiers.intersection([.command, .control, .option])
        guard flags.isEmpty || flags == .command else { return nil }
        if flags == .command {
            switch code {
            case 126, 115: return .first
            case 125, 119: return .last
            default: return nil
            }
        }
        // Fn+arrows on a Mac emit the same physical codes as these keys.
        switch code {
        case 116: return .pageUp
        case 121: return .pageDown
        case 115: return .first
        case 119: return .last
        default: return nil
        }
    }

    func target(from current: Int, frames: [NSRect], pageHeight: CGFloat) -> Int? {
        guard frames.indices.contains(current) else { return nil }
        if self == .first { return frames.startIndex }
        if self == .last { return frames.count - 1 }
        let down = self == .pageDown
        let candidates = down ? Array((current + 1)..<frames.count) : Array(0..<current)
        guard !candidates.isEmpty else { return current }
        let origin = frames[current]
        let targetY = origin.minY + (down ? 1 : -1) * max(1, pageHeight)
        return candidates.min { a, b in
            let verticalA = abs(frames[a].minY - targetY), verticalB = abs(frames[b].minY - targetY)
            if verticalA != verticalB { return verticalA < verticalB }
            let horizontalA = abs(frames[a].midX - origin.midX), horizontalB = abs(frames[b].midX - origin.midX)
            if horizontalA != horizontalB { return horizontalA < horizontalB }
            return abs(a - current) < abs(b - current)
        }
    }
}

enum BrowserAction: Equatable {
    case previous, next, close

    static func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags) -> BrowserAction? {
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
        // Hardware key positions: ANSI Z / X, Space and Escape. No character lookup.
        switch code {
        case 6: return .previous
        case 7, 49: return .next
        case 53: return .close
        default: return nil
        }
    }
}

final class BrowserWindow: NSWindow {
    var onBrowserAction: ((BrowserAction) -> Void)?
    var onFileAction: ((FileAction) -> Bool)?
    var canFileAction: ((FileAction) -> Bool)?
    var canUndoFiles: (() -> Bool)?
    var onFileNavigation: ((FileNavigation, Bool) -> Bool)?
    let fileUndo = UndoManager()
    override var undoManager: UndoManager? { fileUndo }

    @objc func copy(_ sender: Any?) { _ = onFileAction?(.copyFiles) }
    @objc func paste(_ sender: Any?) { _ = onFileAction?(.paste) }
    override func selectAll(_ sender: Any?) { _ = onFileAction?(.selectAll) }
    @objc func moveClipboardFiles(_ sender: Any?) { _ = onFileAction?(.moveHere) }
    @objc func duplicateFiles(_ sender: Any?) { _ = onFileAction?(.duplicate) }
    @objc func renameFiles(_ sender: Any?) { _ = onFileAction?(.rename) }
    @objc func trashFiles(_ sender: Any?) { _ = onFileAction?(.trash) }
    @objc func deleteFiles(_ sender: Any?) { _ = onFileAction?(.deletePermanently) }
    @objc func undo(_ sender: Any?) { if canUndoFiles?() != false { fileUndo.undo() } }
    @objc func redo(_ sender: Any?) { if canUndoFiles?() != false { fileUndo.redo() } }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let actions: [Selector: FileAction] = [#selector(copy(_:)): .copyFiles, #selector(paste(_:)): .paste,
            #selector(selectAll(_:)): .selectAll, #selector(moveClipboardFiles(_:)): .moveHere,
            #selector(duplicateFiles(_:)): .duplicate, #selector(renameFiles(_:)): .rename,
            #selector(trashFiles(_:)): .trash, #selector(deleteFiles(_:)): .deletePermanently]
        if let selector = menuItem.action, let action = actions[selector] { return canFileAction?(action) ?? false }
        if menuItem.action == #selector(undo(_:)) { return fileUndo.canUndo && canUndoFiles?() != false }
        if menuItem.action == #selector(redo(_:)) { return fileUndo.canRedo && canUndoFiles?() != false }
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        if isKeyWindow, handleFileNavigation(event) { return }
        if event.type == .keyDown, isKeyWindow, attachedSheet == nil,
           NSApp.modalWindow == nil,
           !(firstResponder is NSTextView), !(firstResponder is NSTextField),
           !(firstResponder is NSControl) {
            if let action = FileAction.key(event.keyCode, modifiers: event.modifierFlags), onFileAction?(action) == true {
                return
            }
            if let action = BrowserAction.key(event.keyCode, modifiers: event.modifierFlags) {
                onBrowserAction?(action)
                return
            }
        }
        super.sendEvent(event)
    }

    @discardableResult func handleFileNavigation(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, attachedSheet == nil, NSApp.modalWindow == nil,
              !(firstResponder is NSTextView), !(firstResponder is NSTextField), !(firstResponder is NSControl),
              let action = FileNavigation.key(event.keyCode, modifiers: event.modifierFlags) else { return false }
        return onFileNavigation?(action, event.modifierFlags.contains(.shift)) ?? false
    }
}

enum ImageProcessingProgress: Equatable {
    case preparing, processing(Double), cancelling

    var percentage: Double? {
        if case .processing(let value) = self { return min(100, max(0, value)) }
        return nil
    }

    var label: String {
        switch self {
        case .preparing: return "Preparing…"
        case .processing: return "\(Int(percentage ?? 0))%"
        case .cancelling: return "Cancelling…"
        }
    }
}

enum ImageSortKey: String, CaseIterable {
    case name, modified, created, fileSize, fileType

    var title: String {
        switch self {
        case .name: return "Name"
        case .modified: return "Date Modified"
        case .created: return "Date Created"
        case .fileSize: return "File Size"
        case .fileType: return "File Type"
        }
    }
}

struct ThumbnailGridMetrics {
    let columns: Int
    let itemSize: NSSize
    static let gap: CGFloat = 10
    static let inset: CGFloat = 8

    init(availableWidth: CGFloat, thumbnailSize: CGFloat) {
        let usable = max(1, availableWidth - Self.inset * 2)
        columns = max(1, Int(floor((usable + Self.gap) / (thumbnailSize + 16 + Self.gap))))
        itemSize = NSSize(width: floor((usable - CGFloat(columns - 1) * Self.gap) / CGFloat(columns)),
                          height: thumbnailSize + 58)
    }
}

final class SidebarPreferences {
    private let defaults: UserDefaults
    private(set) var width: CGFloat
    private(set) var thumbnailSize: CGFloat
    private(set) var descending: Bool
    private(set) var sortKey: ImageSortKey
    private(set) var gridMode: ThumbnailGridMode
    static let minimumWidth: CGFloat = 240

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let width = defaults.object(forKey: "sidebar.width") as? Double ?? 260
        let size = defaults.object(forKey: "sidebar.thumbnailSize") as? Double ?? 112
        self.width = width.isFinite ? max(Self.minimumWidth, width) : 260
        thumbnailSize = size.isFinite ? min(400, max(64, size)) : 112
        descending = defaults.bool(forKey: "sidebar.descending")
        sortKey = ImageSortKey(rawValue: defaults.string(forKey: "sidebar.sortKey") ?? "") ?? .name
        gridMode = ThumbnailGridMode(rawValue: defaults.string(forKey: "sidebar.gridMode") ?? "") ?? .regular
    }

    static func minimumWidth(thumbnailSize: CGFloat) -> CGFloat {
        max(minimumWidth, thumbnailSize + 60)
    }

    static func boundedWidth(_ preferred: CGFloat, windowWidth: CGFloat, thumbnailSize: CGFloat = 112) -> CGFloat {
        min(max(minimumWidth(thumbnailSize: thumbnailSize), preferred), max(0, windowWidth / 2))
    }

    func setWidth(_ value: CGFloat) {
        guard value.isFinite else { return }
        width = max(Self.minimumWidth, value)
        defaults.set(Double(width), forKey: "sidebar.width")
    }

    func setThumbnailSize(_ value: CGFloat) {
        guard value.isFinite else { return }
        thumbnailSize = min(400, max(64, value))
        defaults.set(Double(thumbnailSize), forKey: "sidebar.thumbnailSize")
    }

    func setDescending(_ value: Bool) {
        descending = value
        defaults.set(value, forKey: "sidebar.descending")
    }

    func setSortKey(_ value: ImageSortKey) {
        sortKey = value
        defaults.set(value.rawValue, forKey: "sidebar.sortKey")
    }
    func setGridMode(_ value: ThumbnailGridMode) {
        gridMode = value
        defaults.set(value.rawValue, forKey: "sidebar.gridMode")
    }
}

final class ImageDocument {
    private(set) var url: URL
    private(set) var fileSize = 0
    private(set) var modified = Date.distantPast
    private(set) var created = Date.distantPast
    private(set) var fileID: String?
    private(set) var revision: FileRevision?
    private(set) var isMissing = false
    private(set) var resultURL: URL?
    private(set) var savedURL: URL?
    private(set) var resultScale = 4
    var modelIndex = 0
    static let outputScales = [1, 2, 4]
    var scaleIndex = 2
    var outputScale: Int { Self.outputScales[scaleIndex] }
    var position: PreviewPosition?
    var processing: ImageProcessingProgress?
    var hasUnsavedResult: Bool { resultURL != nil && savedURL == nil }

    init(url: URL) {
        self.url = url.standardizedFileURL
        refreshMetadata()
    }

    func relocate(to url: URL) {
        self.url = url.standardizedFileURL
        refreshMetadata()
    }

    func refreshMetadata() {
        revision = FileRevision(url)
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
        fileSize = values?.fileSize ?? 0
        modified = values?.contentModificationDate ?? .distantPast
        created = values?.creationDate ?? .distantPast
        isMissing = !FileManager.default.fileExists(atPath: url.path)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let device = attributes[.systemNumber] as? NSNumber,
           let inode = attributes[.systemFileNumber] as? NSNumber {
            fileID = "\(device):\(inode)"
        }
    }

    func receive(_ result: URL, scale: Int) {
        let old = resultURL
        resultURL = result
        resultScale = scale
        savedURL = nil
        if let old, old != result { try? FileManager.default.removeItem(at: old) }
    }

    @discardableResult func save() throws -> URL? {
        guard let resultURL else { return nil }
        if let savedURL { return savedURL }
        let destination = try ResultExporter.exportNext(resultURL, original: url, scale: resultScale)
        savedURL = destination
        return destination
    }

    func didSave(_ destination: URL) { savedURL = destination }

    func savedFileMoved(from source: URL, to destination: URL?) {
        if savedURL == source { savedURL = destination }
    }

    func discard() throws {
        if let resultURL, FileManager.default.fileExists(atPath: resultURL.path) {
            try FileManager.default.removeItem(at: resultURL)
        }
        resultURL = nil
        savedURL = nil
    }
}

enum CloseDecision { case save, discard, cancel }

enum UnsavedResults {
    static func resolve(_ documents: [ImageDocument],
                        choose: (ImageDocument, Int, Int) -> CloseDecision) throws -> Bool {
        let pending = documents.filter { $0.hasUnsavedResult }
        for (index, document) in pending.enumerated() {
            switch choose(document, index + 1, pending.count) {
            case .save: try document.save()
            case .discard: try document.discard()
            case .cancel: return false
            }
        }
        return true
    }
}

final class FolderSession {
    let directory: URL
    private(set) var documents: [ImageDocument]
    private(set) var selected: ImageDocument?
    var filterText = ""
    var descending = false
    var sortKey: ImageSortKey = .name
    var visibleDocuments: [ImageDocument] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? documents : documents.filter {
            $0.url.lastPathComponent.localizedStandardContains(query)
        }
        let sorted = matches.sorted { first, second in
            let ascending: Bool
            switch sortKey {
            case .name: ascending = Self.ordered(first.url, second.url)
            case .modified:
                ascending = first.modified == second.modified ? Self.ordered(first.url, second.url) : first.modified < second.modified
            case .created:
                ascending = first.created == second.created ? Self.ordered(first.url, second.url) : first.created < second.created
            case .fileSize:
                ascending = first.fileSize == second.fileSize ? Self.ordered(first.url, second.url) : first.fileSize < second.fileSize
            case .fileType:
                let a = first.url.pathExtension.lowercased(), b = second.url.pathExtension.lowercased()
                ascending = a == b ? Self.ordered(first.url, second.url) : a < b
            }
            return ascending
        }
        return descending ? Array(sorted.reversed()) : sorted
    }

    init(directory: URL, urls: [URL]) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        documents = urls.map { ImageDocument(url: $0) }
    }

    static func images(in directory: URL) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles])
        return urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension),
                  AppPaths.imageTypes.contains(where: { type.conforms(to: $0) }) else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted(by: ordered)
    }

    private static func ordered(_ first: URL, _ second: URL) -> Bool {
        let comparison = first.lastPathComponent.localizedStandardCompare(second.lastPathComponent)
        return comparison == .orderedSame ? first.path < second.path : comparison == .orderedAscending
    }

    @discardableResult func select(_ url: URL) -> ImageDocument? {
        guard let document = documents.first(where: { $0.url == url.standardizedFileURL }) else { return nil }
        selected = document
        return document
    }

    func neighbor(_ offset: Int) -> ImageDocument? {
        let visible = visibleDocuments
        guard let selected, let index = visible.firstIndex(where: { $0 === selected }) else {
            return offset < 0 ? visible.last : visible.first
        }
        guard visible.indices.contains(index + offset) else { return nil }
        return visible[index + offset]
    }

    func include(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() == directory,
              !documents.contains(where: { $0.url == url.standardizedFileURL }) else { return }
        documents.append(ImageDocument(url: url))
        documents.sort { Self.ordered($0.url, $1.url) }
    }

    /// Preserve zoom/results by document identity when Finder renames a file.
    /// Missing originals with pending work remain available for saving results.
    func reconcile(_ urls: [URL]) {
        let urls = urls.map { $0.standardizedFileURL }
        var remaining = documents
        var updated: [ImageDocument] = []
        let existing = Set(urls)
        for url in urls {
            if let index = remaining.firstIndex(where: { $0.url == url }) {
                let document = remaining.remove(at: index)
                document.refreshMetadata()
                updated.append(document)
            } else {
                let fresh = ImageDocument(url: url)
                let matches = remaining.indices.filter {
                    fresh.fileID != nil && remaining[$0].fileID == fresh.fileID && !existing.contains(remaining[$0].url)
                }
                if matches.count == 1, let index = matches.first {
                    let document = remaining.remove(at: index)
                    document.relocate(to: url)
                    updated.append(document)
                } else { updated.append(fresh) }
            }
        }
        for document in remaining where document.hasUnsavedResult || document.processing != nil {
            document.refreshMetadata()
            updated.append(document)
        }
        documents = updated
        if let selected, !documents.contains(where: { $0 === selected }) { self.selected = nil }
    }
}
