import AppKit
import ImageIO

/// Includes inode and nanosecond change time, so an atomic replacement or an
/// in-place edit with a restored modification date still invalidates the entry.
struct FileRevision: Equatable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init?(_ url: URL) {
        var value = stat()
        guard Darwin.fstatat(AT_FDCWD, url.path, &value, 0) == 0 else { return nil }
        device = value.st_dev
        inode = value.st_ino
        size = value.st_size
        modifiedSeconds = value.st_mtimespec.tv_sec
        modifiedNanoseconds = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec
        changedNanoseconds = value.st_ctimespec.tv_nsec
    }
}

struct PreparedThumbnail {
    let bitmap: CGImage
    let pixels: NSSize
    let file: URL?
}

/// Main-thread index + bounded RAM cache, backed by a private temporary session.
/// RAM eviction can only reload a ready PNG, never regenerate from an original.
final class ThumbnailCache {
    private struct Entry {
        let file: URL?
        let fallback: NSImage?
        let size: NSSize
    }
    let session: TemporarySession?
    private let memory = NSCache<NSURL, NSImage>()
    private var entries: [URL: Entry] = [:]
    private var retiredFiles: [URL: [URL]] = [:]
    private var failed = Set<URL>()

    init() {
        session = try? TemporarySession()
        memory.totalCostLimit = 48 * 1024 * 1024
    }

    func contains(_ url: URL) -> Bool { entries[url] != nil || failed.contains(url) }

    func image(_ url: URL) -> NSImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        guard let entry = entries[url] else { return nil }
        if let fallback = entry.fallback { return fallback }
        guard let file = entry.file else { return nil }
        // Lazy, file-backed NSImage keeps the card populated on a cache miss.
        // AppKit reads the session PNG when needed, never the user's original.
        let image = NSImage(byReferencing: file)
        image.size = entry.size
        memory.setObject(image, forKey: url as NSURL, cost: Int(entry.size.width * entry.size.height * 4))
        return image
    }

    func insert(_ thumbnail: PreparedThumbnail?, for url: URL) -> NSImage? {
        guard let thumbnail else { failed.insert(url); return nil }
        let size = NSSize(width: thumbnail.bitmap.width, height: thumbnail.bitmap.height)
        let image = NSImage(cgImage: thumbnail.bitmap, size: size)
        entries[url] = Entry(file: thumbnail.file, fallback: thumbnail.file == nil ? image : nil, size: size)
        memory.setObject(image, forKey: url as NSURL, cost: thumbnail.bitmap.bytesPerRow * thumbnail.bitmap.height)
        failed.remove(url)
        return image
    }

    func remove(_ url: URL) {
        // A visible lazy NSImage may still reference the previous PNG while
        // its replacement is being prepared. Retire it only after that swap.
        if let file = entries.removeValue(forKey: url)?.file { retiredFiles[url, default: []].append(file) }
        memory.removeObject(forKey: url as NSURL)
        failed.remove(url)
    }

    func prune(keeping urls: Set<URL>) {
        for url in Set(entries.keys).union(failed).subtracting(urls) { remove(url) }
        for url in Array(retiredFiles.keys) where !urls.contains(url) || entries[url] != nil || failed.contains(url) {
            for file in retiredFiles.removeValue(forKey: url) ?? [] { try? FileManager.default.removeItem(at: file) }
        }
    }

    func releaseMemory() { memory.removeAllObjects() }

    /// Run only on a worker queue. One decode is sufficient for every slider
    /// size and grid mode, including Retina and multirow portrait previews.
    static func prepare(_ url: URL, in session: TemporarySession?) -> PreparedThumbnail? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
                  let pixels = ThumbnailGeometry.imageSize(in: source) else { return nil }
            let ratio = max(pixels.width, pixels.height) / min(pixels.width, pixels.height)
            let limit = ThumbnailGeometry.usesSingleCellAspect(pixels) ? 800 : min(8192, ceil(800 * ratio))
            guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(limit),
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { return nil }
            var file: URL?
            if let destination = session?.nextResult(),
               let writer = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(writer, bitmap, nil)
                if CGImageDestinationFinalize(writer) { file = destination }
                else { try? FileManager.default.removeItem(at: destination) }
            }
            return PreparedThumbnail(bitmap: bitmap, pixels: pixels, file: file)
        }
    }
}
