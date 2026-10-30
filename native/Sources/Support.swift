import AppKit
import ImageIO
import UniformTypeIdentifiers

enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum AppPaths {
    static var data: URL {
        if let path = ProcessInfo.processInfo.environment["NCF_IMAGE_UPSCALER_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        if let path = Bundle.main.object(forInfoDictionaryKey: "NCFImageUpscalerDataDirectory") as? String {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ncf-image-upscaler", isDirectory: true)
    }
    static var python: URL {
        if let installer = try? PortableRuntimeInstaller.bundled(resources: Bundle.main.resourceURL, data: data) {
            return installer.python
        }
        return data.appendingPathComponent("runtime/env/bin/python")
    }
    static var sessions: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ncf-image-upscaler-sessions", isDirectory: true)
    }
    static var imageTypes: [UTType] { [.png, .jpeg, .tiff, .bmp, .webP] }
}

enum LegacyPreferences {
    static func migrate(defaults: UserDefaults = .standard,
                        legacy: [String: Any]? = UserDefaults.standard.persistentDomain(forName: "local.image-upscaler.desktop")) {
        guard let legacy, !defaults.bool(forKey: "migration.preNCF.completed") else { return }
        for key in ["sidebar.width", "sidebar.thumbnailSize", "sidebar.descending",
                    "sidebar.sortKey", "sidebar.gridMode"] {
            if defaults.object(forKey: key) == nil, let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "migration.preNCF.completed")
    }
}

struct ImageAsset {
    let image: NSImage
    let pixels: NSSize
    let hasAlpha: Bool

    static func load(_ url: URL) throws -> ImageAsset {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw AppFailure.message("Could not open image «\(url.lastPathComponent)».")
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw AppFailure.message("Animated and multipage images are not supported.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppFailure.message("Unsupported image format.")
        }
        let alpha: Bool
        switch bitmap.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: alpha = true
        default: alpha = false
        }
        let size = NSSize(width: bitmap.width, height: bitmap.height)
        return ImageAsset(image: NSImage(cgImage: bitmap, size: size), pixels: size, hasAlpha: alpha)
    }
}

/// Each window owns a private session. Do not delete other live windows' files.
final class TemporarySession {
    let directory: URL
    private let lockDescriptor: Int32

    init() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: AppPaths.sessions, withIntermediateDirectories: true)
        directory = AppPaths.sessions.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        let lock = directory.appendingPathComponent(".lock").path
        lockDescriptor = Darwin.open(lock, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
            try? manager.removeItem(at: directory)
            throw AppFailure.message("Could not create a temporary folder.")
        }
    }

    func nextResult() -> URL { directory.appendingPathComponent("\(UUID().uuidString).png") }

    deinit {
        try? FileManager.default.removeItem(at: directory)
        flock(lockDescriptor, LOCK_UN)
        Darwin.close(lockDescriptor)
    }

    static func removeAbandoned() {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(at: AppPaths.sessions,
                                                              includingPropertiesForKeys: nil) else { return }
        for directory in children {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            let fd = Darwin.open(directory.appendingPathComponent(".lock").path, O_RDWR)
            guard fd >= 0 else { continue }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                try? manager.removeItem(at: directory)
                flock(fd, LOCK_UN)
            }
            Darwin.close(fd)
        }
    }
}

enum ResultExporter {
    static func isOriginal(_ candidate: URL, original: URL) -> Bool {
        if candidate.standardizedFileURL.resolvingSymlinksInPath()
            == original.standardizedFileURL.resolvingSymlinksInPath() { return true }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let first = try? candidate.resourceValues(forKeys: keys).fileResourceIdentifier,
           let second = try? original.resourceValues(forKeys: keys).fileResourceIdentifier {
            return (first as? NSObject)?.isEqual(second) == true
        }
        return false
    }

    static func suggestedURL(original: URL, scale: Int, index: Int = 1) -> URL {
        let stem = original.deletingPathExtension().lastPathComponent
        let suffix = index == 1 ? "" : "_\(index)"
        return original.deletingLastPathComponent()
            .appendingPathComponent("\(stem)_\(scale)x\(suffix).png")
    }

    static func export(_ temporary: URL, original: URL, destination: URL,
                       replacing: Bool = false) throws -> URL {
        guard destination.pathExtension.lowercased() == "png" else {
            throw AppFailure.message("Save the result in PNG format.")
        }
        guard !isOriginal(destination, original: original) else {
            throw AppFailure.message("The original cannot be replaced. Choose another filename.")
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".ncf-image-upscaler-\(UUID().uuidString).png")
        let manager = FileManager.default
        try manager.copyItem(at: temporary, to: staging)
        defer { try? manager.removeItem(at: staging) }
        if replacing {
            guard !isOriginal(destination, original: original) else {
                throw AppFailure.message("The original cannot be replaced.")
            }
            if Darwin.rename(staging.path, destination.path) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } else if Darwin.link(staging.path, destination.path) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return destination
    }

    static func exportNext(_ temporary: URL, original: URL, scale: Int) throws -> URL {
        var index = 1
        while true {
            let candidate = suggestedURL(original: original, scale: scale, index: index)
            do { return try export(temporary, original: original, destination: candidate) }
            catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == EEXIST {
                index += 1
            }
        }
    }
}
