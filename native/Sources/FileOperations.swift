import AppKit
import UniformTypeIdentifiers
import CoreServices

enum FileAction: Int, CaseIterable {
    case copyFiles, copyImage, copyResult, copyPaths, paste, moveHere, duplicate, rename
    case trash, deletePermanently, reveal, info, refresh, selectAll, deselectAll
    case saveResults, discardResults

    var title: String {
        switch self {
        case .copyFiles: return "Copy Files"
        case .copyImage: return "Copy Image"
        case .copyResult: return "Copy Enhanced Image"
        case .copyPaths: return "Copy Paths"
        case .paste: return "Paste into This Folder"
        case .moveHere: return "Move Items Here"
        case .duplicate: return "Duplicate"
        case .rename: return "Rename…"
        case .trash: return "Move to Trash"
        case .deletePermanently: return "Delete Permanently…"
        case .reveal: return "Show in Finder"
        case .info: return "Get Info…"
        case .refresh: return "Refresh Folder"
        case .selectAll: return "Select All"
        case .deselectAll: return "Deselect All"
        case .saveResults: return "Save Enhancements"
        case .discardResults: return "Discard Unsaved Enhancements…"
        }
    }

    static func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags) -> FileAction? {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        if flags == .command {
            switch code {
            case 8: return .copyFiles
            case 9: return .paste
            case 2: return .duplicate
            case 0: return .selectAll
            case 51: return .trash
            case 15: return .reveal
            case 34: return .info
            default: return nil
            }
        }
        if flags == [.command, .option] {
            if code == 9 { return .moveHere }
            if code == 51 { return .deletePermanently }
            if code == 8 { return .copyPaths }
            if code == 0 { return .deselectAll }
        }
        if flags.isEmpty, code == 36 { return .rename }
        return nil
    }
}

enum FileMutation {
    case copy(URL, URL), move(URL, URL), trash(URL), delete(URL), create(Data, URL)
}

struct FileBatchResult {
    var inverse: [FileMutation] = []
    var created: [URL] = []
    var removed: [URL] = []
    var moved: [(URL, URL)] = []
    var errors: [String] = []
}

enum FileOperations {
    static func isImage(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension),
              AppPaths.imageTypes.contains(where: { type.conforms(to: $0) }) else { return false }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    static func renamedURL(_ source: URL, name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains(":"), !name.contains("\0"), name.utf8.count <= 255 else {
            throw AppFailure.message("Invalid filename. Use up to 255 bytes without / or :.")
        }
        return source.deletingLastPathComponent().appendingPathComponent(name)
    }

    static func availableURL(in directory: URL, name: String, reserved: Set<URL> = []) -> URL {
        let requested = directory.appendingPathComponent(name)
        let stem = requested.deletingPathExtension().lastPathComponent
        let ext = requested.pathExtension
        var candidate = requested
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) || reserved.contains(candidate) {
            candidate = directory.appendingPathComponent(stem + "_\(index)" + (ext.isEmpty ? "" : ".\(ext)"))
            index += 1
        }
        return candidate
    }

    static func imports(_ sources: [URL], into directory: URL, moving: Bool) -> [FileMutation] {
        var reserved = Set<URL>()
        return Array(Set(sources.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }.compactMap { source in
            guard isImage(source) else { return nil }
            let sameFolder = source.deletingLastPathComponent().resolvingSymlinksInPath() == directory.resolvingSymlinksInPath()
            if moving && sameFolder { return nil }
            let name = sameFolder
                ? source.deletingPathExtension().lastPathComponent + " copy." + source.pathExtension
                : source.lastPathComponent
            let destination = availableURL(in: directory, name: name, reserved: reserved)
            reserved.insert(destination)
            return moving ? .move(source, destination) : .copy(source, destination)
        }
    }

    /// Each file is independent: successful changes remain undoable if another
    /// file fails. Destinations are never replaced, including during undo/redo.
    static func perform(_ mutations: [FileMutation]) -> FileBatchResult {
        let manager = FileManager.default
        var result = FileBatchResult()
        for mutation in mutations {
            do {
                switch mutation {
                case .copy(let source, let destination):
                    let staging = destination.deletingLastPathComponent()
                        .appendingPathComponent(".ncf-image-upscaler-copy-\(UUID().uuidString)")
                    defer { try? manager.removeItem(at: staging) }
                    try manager.copyItem(at: source, to: staging)
                    try manager.moveItem(at: staging, to: destination)
                    result.created.append(destination)
                    result.inverse.insert(.trash(destination), at: 0)
                case .create(let data, let destination):
                    try data.write(to: destination, options: .withoutOverwriting)
                    result.created.append(destination)
                    result.inverse.insert(.trash(destination), at: 0)
                case .move(let source, let destination):
                    if source == destination { continue }
                    try manager.moveItem(at: source, to: destination)
                    result.created.append(destination)
                    result.removed.append(source)
                    result.moved.append((source, destination))
                    result.inverse.insert(.move(destination, source), at: 0)
                case .trash(let source):
                    var location: NSURL?
                    try manager.trashItem(at: source, resultingItemURL: &location)
                    result.removed.append(source)
                    if let location { result.inverse.insert(.move(location as URL, source), at: 0) }
                case .delete(let source):
                    try manager.removeItem(at: source)
                    result.removed.append(source)
                }
            } catch { result.errors.append(error.localizedDescription) }
        }
        return result
    }
}

enum FileClipboard {
    struct ImageData {
        let png: Data
        let tiff: Data
    }
    static func files(_ board: NSPasteboard = .general) -> [URL] {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { FileOperations.isImage($0) }
    }

    static func copyFiles(_ urls: [URL], to board: NSPasteboard = .general) {
        guard !urls.isEmpty else { return }
        board.clearContents()
        board.writeObjects(urls.map { $0 as NSURL })
    }

    static func imageData(_ board: NSPasteboard = .general) -> Data? {
        if let data = board.data(forType: .png), NSBitmapImageRep(data: data) != nil { return data }
        guard let data = board.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func copyImage(_ asset: ImageAsset, to board: NSPasteboard = .general) throws {
        writeImage(try encodeImage(asset), to: board)
    }

    static func encodeImage(_ asset: ImageAsset) throws -> ImageData {
        // Use the decoded pixels rather than NSImage's display/TIFF conversion,
        // which can change the color profile or select a Retina cache.
        let bitmap = asset.image.representations.compactMap { $0 as? NSBitmapImageRep }.first {
            $0.pixelsWide == Int(asset.pixels.width) && $0.pixelsHigh == Int(asset.pixels.height)
        } ?? asset.image.cgImage(forProposedRect: nil, context: nil, hints: nil).map { NSBitmapImageRep(cgImage: $0) }
        guard let bitmap, let tiff = bitmap.representation(using: .tiff, properties: [:]),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AppFailure.message("Could not copy the image.")
        }
        return ImageData(png: png, tiff: tiff)
    }

    static func writeImage(_ data: ImageData, to board: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setData(data.png, forType: .png)
        item.setData(data.tiff, forType: .tiff)
        board.clearContents()
        board.writeObjects([item])
    }
}

final class DirectoryMonitor {
    private var source: DispatchSourceFileSystemObject?
    private var stream: FSEventStreamRef?
    private let changed: () -> Void

    init?(_ directory: URL, changed: @escaping () -> Void) {
        self.changed = changed
        let descriptor = Darwin.open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source
        source.resume()
        // Directory vnode events cover additions/removals, but not writes into
        // an existing child. FSEvents covers those without one descriptor/file.
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                          retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryMonitor>.fromOpaque(info).takeUnretainedValue().changed()
        }
        if let stream = FSEventStreamCreate(nil, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot |
                                    kFSEventStreamCreateFlagNoDefer)) {
            FSEventStreamSetDispatchQueue(stream, .main)
            if FSEventStreamStart(stream) { self.stream = stream }
            else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        }
    }

    deinit {
        source?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
