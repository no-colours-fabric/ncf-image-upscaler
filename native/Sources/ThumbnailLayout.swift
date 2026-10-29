import AppKit
import ImageIO

enum ThumbnailGridMode: String {
    case regular, adaptive
}

enum ThumbnailGeometry {
    // Common photo and screen formats (4:3, 3:2, 16:10 and their rotations)
    // stay in one cell. Reserve extra rows/columns for more elongated images.
    static let singleCellAspectLimit: CGFloat = 16.0 / 10.0

    static func usesSingleCellAspect(_ size: NSSize) -> Bool {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return false }
        return max(size.width, size.height) / min(size.width, size.height) <= singleCellAspectLimit
    }

    static func imageSize(at url: URL) -> NSSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                  [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return imageSize(in: source)
    }

    static func imageSize(in source: CGImageSource) -> NSSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? NSSize(width: height, height: width) : NSSize(width: width, height: height)
    }

    static func imageRect(pixels: NSSize, in bounds: NSRect, enlarge: Bool) -> NSRect {
        guard pixels.width > 0, pixels.height > 0, pixels.width.isFinite, pixels.height.isFinite else { return .zero }
        let factor = min(enlarge ? CGFloat.greatestFiniteMagnitude : 1,
                         max(0, min(bounds.width / pixels.width, bounds.height / pixels.height)))
        let size = NSSize(width: pixels.width * factor, height: pixels.height * factor)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// Integer cell spans preserve alignment and sorted reading order. A forward
/// cursor never backfills earlier gaps. Only column end rows are needed: all
/// skipped holes lie behind the cursor. Very tall images use constant memory.
struct AdaptiveThumbnailGrid {
    let frames: [NSRect]
    let contentSize: NSSize

    init(width: CGFloat, thumbnailSize: CGFloat, imageSizes: [NSSize?]) {
        let metrics = ThumbnailGridMetrics(availableWidth: width, thumbnailSize: thumbnailSize)
        let columns = metrics.columns
        // Adaptive cells have square image areas. The regular flow can stretch
        // column widths to fill the panel; that extra width must not make a
        // square source look like a portrait requiring another row.
        let cell = NSSize(width: metrics.itemSize.width, height: metrics.itemSize.width - 16 + 58)
        let gap = ThumbnailGridMetrics.gap
        let inset = ThumbnailGridMetrics.inset
        var nextFreeRow = Array(repeating: 0, count: columns)
        var placed: [NSRect] = []
        var cursorRow = 0, cursorColumn = 0
        for pixels in imageSizes {
            var columnSpan = 1, rowSpan = 1
            if let pixels, pixels.width > 0, pixels.height > 0, pixels.width.isFinite, pixels.height.isFinite,
               !ThumbnailGeometry.usesSingleCellAspect(pixels) {
                let previewWidth = max(1, cell.width - 16)
                let previewHeight = max(1, cell.height - 58)
                if pixels.width / pixels.height > previewWidth / previewHeight {
                    let scale = min(1, previewHeight / pixels.height)
                    let needed = ceil((pixels.width * scale + 16 + gap) / (cell.width + gap) - 1e-9)
                    columnSpan = Int(min(CGFloat(columns), max(1, needed)))
                } else {
                    let scale = min(1, previewWidth / pixels.width)
                    let needed = ceil((pixels.height * scale + 58 + gap) / (cell.height + gap) - 1e-9)
                    // Bound pathological metadata, without limiting ordinary
                    // portrait sizes or allocating one entry per spanned row.
                    rowSpan = Int(min(100_000, max(1, needed)))
                }
            }
            var bestRow = Int.max, bestColumn = 0
            for column in 0...(columns - columnSpan) {
                let minimumRow = cursorRow + (column < cursorColumn ? 1 : 0)
                let row = nextFreeRow[column..<(column + columnSpan)].reduce(minimumRow, max)
                if row < bestRow { bestRow = row; bestColumn = column }
            }
            cursorRow = bestRow
            cursorColumn = bestColumn + columnSpan
            if cursorColumn == columns { cursorRow += 1; cursorColumn = 0 }
            for column in bestColumn..<(bestColumn + columnSpan) {
                nextFreeRow[column] = bestRow + rowSpan
            }
            placed.append(NSRect(x: inset + CGFloat(bestColumn) * (cell.width + gap),
                y: inset + CGFloat(bestRow) * (cell.height + gap),
                width: CGFloat(columnSpan) * (cell.width + gap) - gap,
                height: CGFloat(rowSpan) * (cell.height + gap) - gap))
        }
        frames = placed
        contentSize = NSSize(width: max(0, width), height: (placed.map { $0.maxY }.max() ?? 0) + inset)
    }
}

final class AdaptiveThumbnailLayout: NSCollectionViewLayout {
    var thumbnailSize: CGFloat = 112
    var imageSizes: [NSSize?] = []
    var usesLoadingPlaceholders = false
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var contentSize = NSSize.zero

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let width = collectionView.enclosingScrollView?.contentView.bounds.width ?? collectionView.bounds.width
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        let placeholderPattern = [NSSize(width: 1200, height: 1200), NSSize(width: 2400, height: 1000),
                                  NSSize(width: 1000, height: 3200), NSSize(width: 1200, height: 1200)]
        let sizes = (0..<count).map { index -> NSSize? in
            if imageSizes.indices.contains(index), let size = imageSizes[index] { return size }
            return usesLoadingPlaceholders ? placeholderPattern[index % placeholderPattern.count] : nil
        }
        let grid = AdaptiveThumbnailGrid(width: width, thumbnailSize: thumbnailSize, imageSizes: sizes)
        contentSize = grid.contentSize
        attributes = grid.frames.enumerated().map { index, frame in
            let item = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            item.frame = frame
            return item
        }
    }

    override var collectionViewContentSize: NSSize { contentSize }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, attributes.indices.contains(indexPath.item) else { return nil }
        return attributes[indexPath.item]
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
    override func layoutAttributesForDropTarget(at pointInCollectionView: NSPoint) -> NSCollectionViewLayoutAttributes? {
        attributes.first { $0.frame.contains(pointInCollectionView) } ?? attributes.min {
            hypot($0.frame.midX - pointInCollectionView.x, $0.frame.midY - pointInCollectionView.y)
                < hypot($1.frame.midX - pointInCollectionView.x, $1.frame.midY - pointInCollectionView.y)
        }
    }
    override func layoutAttributesForInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, indexPath.item >= 0, indexPath.item <= attributes.count else { return nil }
        let gap = NSCollectionViewLayoutAttributes(forInterItemGapBefore: indexPath)
        if attributes.indices.contains(indexPath.item) {
            let frame = attributes[indexPath.item].frame
            gap.frame = NSRect(x: frame.minX - 5, y: frame.minY, width: 2, height: frame.height)
        } else {
            gap.frame = NSRect(x: 8, y: max(8, contentSize.height - 4), width: max(2, contentSize.width - 16), height: 2)
        }
        return gap
    }
}
