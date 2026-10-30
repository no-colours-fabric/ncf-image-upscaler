import AppKit
import ImageIO

var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() { fatalError("FAILED: \(message)") }
}

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("ncf-image-upscaler-tests-\(UUID().uuidString)")
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
let original = root.appendingPathComponent("изображение с пробелами.png")
let temporary = root.appendingPathComponent("temporary.png")
try Data("original".utf8).write(to: original)
try Data("result".utf8).write(to: temporary)
let first = try ResultExporter.exportNext(temporary, original: original, scale: 4)
let second = try ResultExporter.exportNext(temporary, original: original, scale: 4)
expect(first.lastPathComponent == "изображение с пробелами_4x.png", "default output name")
expect(second.lastPathComponent == "изображение с пробелами_4x_2.png", "indexed output name")
let sameSizeFirst = try ResultExporter.exportNext(temporary, original: original, scale: 1)
let sameSizeSecond = try ResultExporter.exportNext(temporary, original: original, scale: 1)
expect(sameSizeFirst.lastPathComponent == "изображение с пробелами_1x.png" &&
       sameSizeSecond.lastPathComponent == "изображение с пробелами_1x_2.png",
       "same-size enhancement exports separate indexed 1x results")
expect(try! Data(contentsOf: original) == Data("original".utf8), "original is unchanged")
expect(try! Data(contentsOf: second) == Data("result".utf8), "result bytes preserved")
for replace in [false, true] {
    do {
        _ = try ResultExporter.export(temporary, original: original, destination: original, replacing: replace)
        fatalError("Original replacement was allowed")
    } catch { assertions += 1 }
}
let hardlink = root.appendingPathComponent("hardlink.png")
try manager.linkItem(at: original, to: hardlink)
expect(ResultExporter.isOriginal(hardlink, original: original), "hardlinks identify the original")
let symlink = root.appendingPathComponent("symlink.png")
try manager.createSymbolicLink(at: symlink, withDestinationURL: original)
expect(ResultExporter.isOriginal(symlink, original: original), "symlinks identify the original")
let explicit = root.appendingPathComponent("save-as.png")
try Data("old output".utf8).write(to: explicit)
do {
    _ = try ResultExporter.export(temporary, original: original, destination: explicit)
    fatalError("Existing file was replaced without permission")
} catch { assertions += 1 }
expect(try! Data(contentsOf: explicit) == Data("old output".utf8), "no accidental overwrite")
_ = try ResultExporter.export(temporary, original: original, destination: explicit, replacing: true)
expect(try! Data(contentsOf: explicit) == Data("result".utf8), "Save As replacement works")
let remaining = try manager.contentsOfDirectory(atPath: root.path)
expect(!remaining.contains(where: { $0.hasPrefix(".ncf-image-upscaler-") }),
       "staging files removed")

var session: TemporarySession? = try TemporarySession()
let active = session!.directory
TemporarySession.removeAbandoned()
expect(manager.fileExists(atPath: active.path), "live temporary session survives cleanup")
session = nil
expect(!manager.fileExists(atPath: active.path), "session files deleted when released")

// NSScrollView changes document frame coordinates during magnification.
// Repeated fitting must use the stable logical bounds, not the scaled frame.
let application = NSApplication.shared
let viewer = ComparisonView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
viewer.layoutSubtreeIfNeeded()
let asset = ImageAsset(image: NSImage(size: NSSize(width: 1672, height: 941)),
                       pixels: NSSize(width: 1672, height: 941), hasAlpha: false)
viewer.setOriginal(asset)
let fitted = viewer.scroll.magnification
for _ in 0..<8 {
    viewer.fit()
    viewer.layoutSubtreeIfNeeded()
}
expect(abs(viewer.scroll.magnification - fitted) < 0.001, "fit remains stable")
expect(abs(fitted - min(1052.0 / 1672.0, 652.0 / 941.0)) < 0.001, "fit uses image pixels")
let enhanced = ImageAsset(image: NSImage(size: NSSize(width: 6688, height: 3764)),
                          pixels: NSSize(width: 6688, height: 3764), hasAlpha: false)
viewer.setEnhanced(enhanced)
expect(abs(viewer.scroll.magnification * 4 - fitted) < 0.001, "comparison keeps the fitted image size")
viewer.actualSize()
expect(abs(viewer.scroll.magnification - 1) < 0.001, "100% uses output pixels")

// Identical translucent images must not be composited twice on the enhanced half.
let alphaBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let color = NSColor(deviceRed: 0.9, green: 0.2, blue: 0.1, alpha: 0.5)
for y in 0..<80 { for x in 0..<100 { alphaBitmap.setColor(color, atX: x, y: y) } }
let alphaImage = NSImage(size: NSSize(width: 100, height: 80))
alphaImage.addRepresentation(alphaBitmap)
let alphaAsset = ImageAsset(image: alphaImage, pixels: alphaImage.size, hasAlpha: true)
let canvas = ImageCanvas(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
canvas.original = alphaAsset
canvas.enhanced = alphaAsset
canvas.dividerInDocument = 50
let rendered = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
canvas.cacheDisplay(in: canvas.bounds, to: rendered)
let backingScale = CGFloat(rendered.pixelsWide) / canvas.bounds.width
let left = rendered.colorAt(x: Int(5 * backingScale), y: Int(5 * backingScale))!.usingColorSpace(.deviceRGB)!
let right = rendered.colorAt(x: Int(59 * backingScale), y: Int(5 * backingScale))!.usingColorSpace(.deviceRGB)!
expect(abs(left.redComponent - right.redComponent) < 0.01 &&
       abs(left.greenComponent - right.greenComponent) < 0.01 &&
       abs(left.blueComponent - right.blueComponent) < 0.01 &&
       abs(left.alphaComponent - 0.5) < 0.01 && abs(right.alphaComponent - 0.5) < 0.01,
       "both comparison halves preserve partial alpha without double compositing or flattening")
for base: CGFloat in [0, 1] {
    let composite = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: composite)
    NSColor(deviceWhite: base, alpha: 1).setFill()
    canvas.bounds.fill()
    canvas.draw(canvas.bounds)
    NSGraphicsContext.restoreGraphicsState()
    for x in [5, 59] {
        let sample = composite.colorAt(x: x, y: 5)!.usingColorSpace(.deviceRGB)!
        expect(abs(sample.redComponent - (0.9 * 0.5 + base * 0.5)) < 0.015 &&
               abs(sample.greenComponent - (0.2 * 0.5 + base * 0.5)) < 0.015 &&
               abs(sample.blueComponent - (0.1 * 0.5 + base * 0.5)) < 0.015,
               "colored translucent pixels composite once on a light or dark background")
    }
}

// A centered document can receive a dirty rectangle extending beyond its bounds.
// Painting that area leaves old document borders in the surrounding viewport.
let overscan = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 180,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: overscan)
let overscanContext = NSGraphicsContext.current!.cgContext
overscanContext.clear(CGRect(x: 0, y: 0, width: 200, height: 180))
overscanContext.translateBy(x: 50, y: 50)
canvas.draw(NSRect(x: -50, y: -50, width: 200, height: 180))
NSGraphicsContext.restoreGraphicsState()
expect(overscan.colorAt(x: 10, y: 10)!.alphaComponent == 0,
       "drawing stays inside the image bounds even with an oversized dirty region")
expect(abs(overscan.colorAt(x: 75, y: 75)!.alphaComponent - 0.5) < 0.01,
       "clipping preserves partial alpha inside the image bounds")

// The checker is a separate, untransformed view. Sample screen positions both
// inside and outside a fully transparent document before and after zoom/pan.
let clearBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let clearColor = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
for y in 0..<80 { for x in 0..<100 { clearBitmap.setColor(clearColor, atX: x, y: y) } }
let clearImage = NSImage(size: NSSize(width: 100, height: 80))
clearImage.addRepresentation(clearBitmap)
let fixedBackgroundViewer = ComparisonView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
fixedBackgroundViewer.appearance = NSAppearance(named: .aqua)
fixedBackgroundViewer.layoutSubtreeIfNeeded()
fixedBackgroundViewer.setOriginal(ImageAsset(image: clearImage, pixels: NSSize(width: 1000, height: 800), hasAlpha: true))
func screenSamples(_ view: NSView) -> [NSColor] {
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    return [(3, 3), (12, 3), (3, 12), (12, 12), (157, 97), (201, 151), (315, 235)].map { x, y in
        bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))!.usingColorSpace(.deviceRGB)!
    }
}
let fixedSamples = screenSamples(fixedBackgroundViewer)
expect(fixedBackgroundViewer.background.frame == fixedBackgroundViewer.bounds &&
       !fixedBackgroundViewer.scroll.drawsBackground && !fixedBackgroundViewer.scroll.contentView.drawsBackground &&
       fixedSamples[0].redComponent > 0.5 && abs(fixedSamples[0].redComponent - fixedSamples[1].redComponent) > 0.03,
       "checker covers the whole viewer through transparent image and scroll views")
for factor: CGFloat in [4, 0.13, 17] {
    fixedBackgroundViewer.zoomBy(factor)
    fixedBackgroundViewer.canvas.pan(to: NSPoint(x: 123, y: 87))
    let changedSamples = screenSamples(fixedBackgroundViewer)
    expect(zip(fixedSamples, changedSamples).allSatisfy { before, after in
        abs(before.redComponent - after.redComponent) < 0.01 && abs(after.alphaComponent - 1) < 0.01
    }, "checker size and phase stay fixed at screen coordinates through zoom and pan")
}
fixedBackgroundViewer.setOriginal(asset)
expect(!fixedBackgroundViewer.background.showsTransparency && screenSamples(fixedBackgroundViewer)[0].redComponent < 0.01,
       "opening an opaque image restores the black viewer background")
fixedBackgroundViewer.setEnhanced(alphaAsset)
expect(fixedBackgroundViewer.background.showsTransparency, "a transparent result also enables the fixed checker")
fixedBackgroundViewer.clear()
expect(!fixedBackgroundViewer.background.showsTransparency, "clearing the image clears the transparency background")

// File-manager operations use disposable local files and a private pasteboard.
let fileDirectory = root.appendingPathComponent("file-manager", isDirectory: true)
let importA = root.appendingPathComponent("import-a", isDirectory: true)
let importB = root.appendingPathComponent("import-b", isDirectory: true)
for directory in [fileDirectory, importA, importB] {
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
}
let pngBytes = alphaBitmap.representation(using: .png, properties: [:])!
let importFirst = importA.appendingPathComponent("полупрозрачное.png")
let importSecond = importB.appendingPathComponent("полупрозрачное.png")
let excludedImport = importA.appendingPathComponent("notes.txt")
try pngBytes.write(to: importFirst)
try pngBytes.write(to: importSecond)
try Data("text".utf8).write(to: excludedImport)
let imports = FileOperations.imports([importFirst, importSecond, excludedImport, importFirst],
                                    into: fileDirectory, moving: false)
let imported = FileOperations.perform(imports)
expect(imported.errors.isEmpty && imported.created.count == 2 && imported.inverse.count == 2,
       "batch import accepts only images, deduplicates inputs and records undo")
expect(Set(imported.created.map { $0.lastPathComponent }) == ["полупрозрачное.png", "полупрозрачное_2.png"],
       "colliding imported filenames receive unique indexes within the batch")
expect(try! Data(contentsOf: importFirst) == pngBytes && (try! Data(contentsOf: imported.created[0])) == pngBytes,
       "copying preserves source and exact RGBA file bytes")
let copiedOriginal = imported.created[0]
let conflict = FileOperations.perform([.copy(importFirst, copiedOriginal), .create(Data("bad".utf8), copiedOriginal)])
expect(conflict.errors.count == 2 && (try! Data(contentsOf: copiedOriginal)) == pngBytes,
       "copy and paste refuse to replace an existing destination")
for invalidName in ["", ".", "..", "../escape.png", "bad:name.png", "bad\0name", String(repeating: "a", count: 256)] {
    do { _ = try FileOperations.renamedURL(copiedOriginal, name: invalidName); fatalError("Invalid rename accepted") }
    catch { assertions += 1 }
}
let fileSession = FolderSession(directory: fileDirectory, urls: try FolderSession.images(in: fileDirectory))
let renamedDocument = fileSession.select(copiedOriginal)!
let pendingFile = root.appendingPathComponent("pending-file-result.png")
try pngBytes.write(to: pendingFile)
renamedDocument.receive(pendingFile, scale: 4)
renamedDocument.position = PreviewPosition(displayedWidth: 237, center: NSPoint(x: 0.3, y: 0.4), fraction: 0.7, fitting: false)
let renamedURL = try FileOperations.renamedURL(copiedOriginal, name: "Новое имя с пробелами.png")
let renamed = FileOperations.perform([.move(copiedOriginal, renamedURL)])
expect(renamed.errors.isEmpty && renamed.inverse.count == 1, "rename returns its inverse")
fileSession.reconcile(try FolderSession.images(in: fileDirectory))
expect(fileSession.selected === renamedDocument && renamedDocument.url == renamedURL &&
       renamedDocument.hasUnsavedResult && renamedDocument.position?.displayedWidth == 237,
       "external rename preserves document identity, pending result, zoom and active selection")
let restoredRename = FileOperations.perform(renamed.inverse)
fileSession.reconcile(try FolderSession.images(in: fileDirectory))
expect(restoredRename.errors.isEmpty && fileSession.selected === renamedDocument && renamedDocument.url == copiedOriginal,
       "undo rename restores the path without losing session state")
let hardlinkedImage = fileDirectory.appendingPathComponent("00-hardlink.png")
try manager.linkItem(at: copiedOriginal, to: hardlinkedImage)
fileSession.reconcile(try FolderSession.images(in: fileDirectory))
expect(fileSession.documents.count == 3 && fileSession.selected === renamedDocument && renamedDocument.url == copiedOriginal,
       "a hardlinked file does not steal the existing document's identity or pending result")
try manager.removeItem(at: hardlinkedImage)
let missingOriginal = importA.appendingPathComponent("temporarily-missing.png")
try manager.moveItem(at: copiedOriginal, to: missingOriginal)
fileSession.reconcile(try FolderSession.images(in: fileDirectory))
expect(fileSession.documents.contains { $0 === renamedDocument } && renamedDocument.isMissing && renamedDocument.hasUnsavedResult,
       "external removal retains a missing original's pending upscale for saving")
try manager.moveItem(at: missingOriginal, to: copiedOriginal)
fileSession.reconcile(try FolderSession.images(in: fileDirectory))
expect(!renamedDocument.isMissing && renamedDocument.position?.displayedWidth == 237,
       "restoring a missing file reuses its session state")
let moveConflict = FileOperations.perform([.move(copiedOriginal, imported.created[1])])
expect(moveConflict.errors.count == 1 && manager.fileExists(atPath: copiedOriginal.path) &&
       (try! Data(contentsOf: imported.created[1])) == pngBytes,
       "rename never replaces a different existing image")
let caseSource = fileDirectory.appendingPathComponent("Case-Test.png")
let caseDestination = fileDirectory.appendingPathComponent("case-test.png")
try pngBytes.write(to: caseSource)
let caseRename = FileOperations.perform([.move(caseSource, caseDestination)])
expect(caseRename.errors.isEmpty && manager.fileExists(atPath: caseDestination.path),
       "rename supports changing only the filename's letter case")
try manager.removeItem(at: caseDestination)
let duplicates = FileOperations.perform(FileOperations.imports([copiedOriginal], into: fileDirectory, moving: false))
expect(duplicates.errors.isEmpty && duplicates.created.first?.lastPathComponent == "полупрозрачное copy.png",
       "duplicating a file uses a separate copy name")
expect(FileOperations.imports([copiedOriginal], into: fileDirectory, moving: true).isEmpty,
       "moving a file to its own folder is a no-op")
let trashed = FileOperations.perform([.trash(duplicates.created[0])])
expect(trashed.errors.isEmpty && !manager.fileExists(atPath: duplicates.created[0].path) && trashed.inverse.count == 1,
       "trash is recoverable and records the actual trash location")
let untrashed = FileOperations.perform(trashed.inverse)
expect(untrashed.errors.isEmpty && manager.fileExists(atPath: duplicates.created[0].path), "undo trash restores the file")
let deleted = FileOperations.perform([.delete(duplicates.created[0])])
expect(deleted.errors.isEmpty && deleted.inverse.isEmpty && !manager.fileExists(atPath: duplicates.created[0].path),
       "permanent deletion has no inverse")
let moveImport = FileOperations.perform(FileOperations.imports([importSecond], into: fileDirectory, moving: true))
expect(moveImport.errors.isEmpty && !manager.fileExists(atPath: importSecond.path), "move import removes the source")
expect(FileOperations.perform(moveImport.inverse).errors.isEmpty && manager.fileExists(atPath: importSecond.path),
       "undo move import restores its original folder")
let privateBoard = NSPasteboard(name: .init("ncf-image-upscaler-test-\(UUID().uuidString)"))
defer { privateBoard.releaseGlobally() }
FileClipboard.copyFiles([importFirst, importSecond], to: privateBoard)
expect(Set(FileClipboard.files(privateBoard)) == [importFirst, importSecond], "file clipboard carries all selected file URLs")
try FileClipboard.copyImage(alphaAsset, to: privateBoard)
let pastedImage = NSBitmapImageRep(data: FileClipboard.imageData(privateBoard)!)!
let pastedPixel = pastedImage.colorAt(x: 5, y: 5)!.usingColorSpace(.sRGB)!
let sourcePixel = NSBitmapImageRep(data: pngBytes)!.colorAt(x: 5, y: 5)!.usingColorSpace(.sRGB)!
expect(privateBoard.data(forType: .tiff) != nil && FileClipboard.files(privateBoard).isEmpty &&
       pastedImage.pixelsWide == 100 && pastedImage.pixelsHigh == 80 && abs(pastedPixel.alphaComponent - 0.5) < 0.01 &&
       abs(pastedPixel.redComponent - sourcePixel.redComponent) < 0.015 &&
       abs(pastedPixel.greenComponent - sourcePixel.greenComponent) < 0.015 &&
       abs(pastedPixel.blueComponent - sourcePixel.blueComponent) < 0.015,
       "copy image exposes PNG/TIFF pixels with the same color profile and partial alpha, without a file reference or checker")
for action in [(UInt16(8), NSEvent.ModifierFlags.command, FileAction.copyFiles),
               (9, [.command, .option], .moveHere), (51, .command, .trash),
               (51, [.command, .option], .deletePermanently), (36, [], .rename)] {
    expect(FileAction.key(action.0, modifiers: action.1) == action.2, "file shortcut uses physical keys")
}

// Hold asynchronous decoding between two frames. Navigation must not clear the
// existing image/checker, even if a pending selection is subsequently cancelled.
let transitionDirectory = root.appendingPathComponent("transitions", isDirectory: true)
try manager.createDirectory(at: transitionDirectory, withIntermediateDirectories: true)
let transitionFirst = transitionDirectory.appendingPathComponent("1.png")
let transitionSecond = transitionDirectory.appendingPathComponent("2.png")
let transitionOpaque = transitionDirectory.appendingPathComponent("3.png")
try alphaBitmap.representation(using: .png, properties: [:])!.write(to: transitionFirst)
try clearBitmap.representation(using: .png, properties: [:])!.write(to: transitionSecond)
let opaqueBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
try opaqueBitmap.representation(using: .png, properties: [:])!.write(to: transitionOpaque)
let decodeStarted = DispatchSemaphore(value: 0)
let allowDecode = DispatchSemaphore(value: 0)
let transitionController = ImageWindowController { url in
    if url != transitionFirst {
        decodeStarted.signal()
        guard allowDecode.wait(timeout: .now() + 10) == .success else {
            throw AppFailure.message("Timed out waiting for the navigation test")
        }
    }
    return try ImageAsset.load(url)
}
let transitionViewer = transitionController.window!.contentView!.subviews.compactMap { $0 as? ComparisonView }.first!
transitionController.window!.contentView!.layoutSubtreeIfNeeded()
func waitForTransition(_ message: String, until ready: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !ready() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    expect(ready(), message)
}
transitionController.load(transitionFirst)
waitForTransition("first transparent image opens") { transitionViewer.canvas.original != nil }
expect(transitionViewer.loadingProgress.isHidden, "loading indicator is hidden once the first image is ready")
expect(transitionViewer.scroll.magnification == 1 && !transitionViewer.fitting,
       "a small file opens at 100 percent on its first visit")
transitionViewer.zoomBy(2.5)
let firstPreview = transitionViewer.canvas.original!.image
let transitionZoom = transitionViewer.scroll.magnification
let checkerBeforeNavigation = screenSamples(transitionViewer.background)
transitionController.load(transitionSecond)
// The semaphore is consumed once here, rather than in the repeatedly evaluated predicate.
var secondStarted = false
waitForTransition("second decode starts") {
    if !secondStarted { secondStarted = decodeStarted.wait(timeout: .now()) == .success }
    return secondStarted
}
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
expect(!transitionViewer.loadingProgress.isHidden && transitionViewer.loadingProgress.isIndeterminate &&
       transitionViewer.loadingProgress.frame.minX == transitionViewer.viewport.minX + 16 &&
       transitionViewer.loadingProgress.frame.maxY == transitionViewer.viewport.maxY - 16 &&
       transitionViewer.loadingProgress.frame.width == 80,
       "a short indeterminate bar appears at the bottom left of the unobscured viewport while loading")
expect(transitionViewer.canvas.original?.image === firstPreview &&
       transitionViewer.background.showsTransparency && transitionViewer.scroll.magnification == transitionZoom &&
       zip(checkerBeforeNavigation, screenSamples(transitionViewer.background)).allSatisfy {
           abs($0.redComponent - $1.redComponent) < 0.01
       }, "loading the next transparent image retains the previous frame and stationary checker without black frames")
allowDecode.signal()
waitForTransition("second transparent image replaces the previous frame") {
    transitionViewer.canvas.original?.image !== firstPreview && transitionViewer.background.showsTransparency
}
expect(transitionViewer.loadingProgress.isHidden, "loading indicator disappears when navigation completes")
expect(transitionViewer.scroll.magnification == 1 && !transitionViewer.fitting,
       "the next small file starts at 100 percent instead of inheriting the previous file's zoom")
transitionViewer.fit()
let secondFittedZoom = transitionViewer.scroll.magnification
let secondPreview = transitionViewer.canvas.original!.image
transitionController.load(transitionOpaque)
var opaqueStarted = false
waitForTransition("opaque decode starts") {
    if !opaqueStarted { opaqueStarted = decodeStarted.wait(timeout: .now()) == .success }
    return opaqueStarted
}
expect(transitionViewer.background.showsTransparency && transitionViewer.canvas.original?.image === secondPreview,
       "the checker remains until the next opaque image is ready")
transitionController.load(transitionFirst)
allowDecode.signal()
waitForTransition("a newer selection supersedes the cancelled opaque load") {
    transitionViewer.canvas.original?.image !== secondPreview && transitionViewer.background.showsTransparency
}
expect(transitionViewer.loadingProgress.isHidden, "superseding a pending load also finishes the loading indicator")
expect(transitionViewer.canvas.original?.hasAlpha == true && transitionController.sourceURL == transitionFirst,
       "cancelled navigation cannot replace the selected transparent image with an opaque frame")
expect(abs(transitionViewer.scroll.magnification - transitionZoom) < 0.001 && !transitionViewer.fitting,
       "returning to a file restores its manual zoom from the session")
allowDecode.signal()
transitionController.load(transitionOpaque)
waitForTransition("a completed opaque image switches to black") { !transitionViewer.background.showsTransparency }
allowDecode.signal()
transitionController.load(transitionSecond)
waitForTransition("returning from an opaque image restores the checker") { transitionViewer.background.showsTransparency }
expect(transitionViewer.fitting && abs(transitionViewer.scroll.magnification - secondFittedZoom) < 0.001 &&
       secondFittedZoom > 1,
       "returning to a small file preserves explicit enlarged fitting from the session")
transitionController.close()
expect(transitionViewer.loadingProgress.isHidden, "closing the window stops the loading indicator")

fixedBackgroundViewer.setLoading(true)
fixedBackgroundViewer.leadingObstruction = 160
expect(fixedBackgroundViewer.loadingProgress.frame.minX == 176,
       "expanding the sidebar moves the loading indicator to the visible area's left edge")
fixedBackgroundViewer.leadingObstruction = 0
expect(fixedBackgroundViewer.loadingProgress.frame.minX == 16,
       "collapsing the sidebar returns the loading indicator to the window's left edge")
fixedBackgroundViewer.setLoading(false)

// Exercise real controller selection, duplication and undo/redo without showing
// a window or borrowing the user's clipboard.
let filesController = ImageWindowController()
let filesSidebar = filesController.window!.contentView!.subviews.compactMap { $0 as? FolderSidebar }.first!
filesController.window!.contentView!.layoutSubtreeIfNeeded()
filesController.load(copiedOriginal)
waitForTransition("file manager controller opens its folder") { !filesSidebar.selectedDocuments.isEmpty }
expect(filesSidebar.collection.allowsMultipleSelection && filesSidebar.collection.allowsEmptySelection,
       "thumbnail collection allows native mouse/keyboard multiple and empty selection")
filesController.performFileAction(.selectAll)
let originalSelection = filesSidebar.selectedDocuments
expect(originalSelection.count == 2, "select all selects every visible image")
expect(!filesController.canPerformFileAction(.rename, documents: originalSelection) &&
       !filesController.canPerformFileAction(.copyImage, documents: originalSelection) &&
       filesController.canPerformFileAction(.copyFiles, documents: originalSelection),
       "batch selection enables file operations but disables single-file actions")
let menu = filesSidebar.fileMenu!(originalSelection)
expect(menu.items.contains { $0.title == FileAction.trash.title && $0.isEnabled } &&
       menu.items.contains { $0.title == FileAction.rename.title && !$0.isEnabled } &&
       menu.items.contains { $0.title == FileAction.paste.title }, "context menu reflects the actual selection")
filesController.performFileAction(.duplicate, documents: originalSelection)
waitForTransition("batch duplication creates two independent copies") {
    (try? FolderSession.images(in: fileDirectory).count) == 4 && filesController.window?.undoManager?.canUndo == true
}
expect(filesSidebar.selectedDocuments.count == 2 &&
       filesSidebar.selectedDocuments.allSatisfy { $0.url.lastPathComponent.contains(" copy") },
       "newly created files are selected as a group")
filesController.window!.undoManager!.undo()
expect((try! FolderSession.images(in: fileDirectory)).count == 2 && filesController.window!.undoManager!.canRedo,
       "controller undo removes all created copies in one operation and enables redo")
filesController.window!.undoManager!.redo()
expect((try! FolderSession.images(in: fileDirectory)).count == 4,
       "controller redo restores all copies without replacing originals")
let dragWriter = filesSidebar.collectionView(filesSidebar.collection,
    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)) as? NSURL
expect(dragWriter != nil && FileOperations.isImage(dragWriter! as URL), "native drag source exports an actual file URL")
let externalImage = fileDirectory.appendingPathComponent("external-new.png")
try pngBytes.write(to: externalImage)
waitForTransition("directory monitor discovers externally created files") {
    filesSidebar.collection.numberOfItems(inSection: 0) == 5
}
for index in 0..<5 {
    _ = filesSidebar.collectionView(filesSidebar.collection, itemForRepresentedObjectAt: IndexPath(item: index, section: 0))
}
waitForTransition("watcher test warms every thumbnail") { filesSidebar.pendingThumbnailCount == 0 }
let beforeInPlaceLoads = filesSidebar.thumbnailLoadCount
let watchedSource = filesController.sourceURL!
let beforeInPlaceRevision = FileRevision(watchedSource)
let beforeInPlaceDate = try watchedSource.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
let inPlaceWriter = try FileHandle(forWritingTo: watchedSource)
try inPlaceWriter.write(contentsOf: pngBytes)
try inPlaceWriter.close()
try manager.setAttributes([.modificationDate: beforeInPlaceDate], ofItemAtPath: watchedSource.path)
expect(FileRevision(watchedSource) != beforeInPlaceRevision,
       "change-time detects an in-place write with unchanged file size and restored modification date")
waitForTransition("FSEvents refreshes the thumbnail of an existing file changed in place") {
    filesSidebar.thumbnailLoadCount == beforeInPlaceLoads + 1 && filesSidebar.pendingThumbnailCount == 0
}
filesController.performFileAction(.refresh)
expect(filesSidebar.thumbnailLoadCount == beforeInPlaceLoads + 1,
       "duplicate folder notifications and manual refresh do not regenerate unchanged thumbnails")
let filesViewer = filesController.window!.contentView!.subviews.compactMap { $0 as? ComparisonView }.first!
waitForTransition("file preview is ready after redo") {
    filesViewer.canvas.original != nil && filesViewer.loadingProgress.isHidden
}
filesViewer.zoomBy(2.25)
let beforeExternalRename = filesViewer.position()
let activeBeforeRename = filesController.sourceURL!
let externalRename = fileDirectory.appendingPathComponent("external-renamed.png")
try manager.moveItem(at: activeBeforeRename, to: externalRename)
waitForTransition("directory monitor follows an externally renamed current file") {
    filesController.sourceURL == externalRename && filesViewer.loadingProgress.isHidden
}
expect(abs(filesViewer.position().displayedWidth - beforeExternalRename.displayedWidth) < 0.01,
       "directory monitor retains the current zoom through an external rename")
let missingDocument = filesSidebar.selectedDocuments.first { $0.url == externalRename }!
let watcherResult = root.appendingPathComponent("watcher-result.png")
try pngBytes.write(to: watcherResult)
missingDocument.receive(watcherResult, scale: 4)
try manager.removeItem(at: externalRename)
waitForTransition("directory monitor marks an externally removed source with a pending result") { missingDocument.isMissing }
expect(missingDocument.hasUnsavedResult && manager.fileExists(atPath: watcherResult.path) &&
       filesSidebar.collection.numberOfItems(inSection: 0) == 5,
       "external deletion retains the missing image's result instead of silently dropping it")
expect(filesController.performFileAction(.saveResults, documents: [missingDocument]) && !missingDocument.hasUnsavedResult &&
       manager.fileExists(atPath: missingDocument.savedURL!.path), "a retained pending result can be saved after its source disappeared")
filesSidebar.deselectAllFiles()
expect(filesSidebar.selectedDocuments.isEmpty, "mouse background/clear selection can leave the file list unselected")
let emptyListClick = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
let emptyListMenu = filesSidebar.collection.enclosingScrollView!.contentView.menu(for: emptyListClick)
expect(emptyListMenu?.items.contains { $0.title == FileAction.paste.title } == true && filesSidebar.selectedDocuments.isEmpty,
       "blank list space still provides the folder context menu, even below a short collection")
filesController.close()

// Folder browsing: filter files, use Finder ordering, and keep document identity
// across navigation and insertion of newly saved outputs.
let galleryURL = root.appendingPathComponent("gallery", isDirectory: true)
try manager.createDirectory(at: galleryURL, withIntermediateDirectories: true)
for name in ["10.png", "2.png", "photo.JPG", "alpha.webp", "scan.tif", "icon.bmp", "notes.txt", ".hidden.png"] {
    try Data("fixture".utf8).write(to: galleryURL.appendingPathComponent(name))
}
try manager.createDirectory(at: galleryURL.appendingPathComponent("nested.png"), withIntermediateDirectories: true)
let gallery = FolderSession(directory: galleryURL, urls: try FolderSession.images(in: galleryURL))
expect(gallery.documents.count == 6, "folder contains only supported visible image files")
expect(gallery.documents.prefix(2).map { $0.url.lastPathComponent } == ["2.png", "10.png"],
       "folder uses natural filename order")
let firstDocument = gallery.select(galleryURL.appendingPathComponent("2.png"))!
expect(firstDocument.outputScale == 4, "adding same-size mode preserves the default 4x output")
for (index, scale) in [1, 2, 4].enumerated() {
    firstDocument.scaleIndex = index
    expect(firstDocument.outputScale == scale, "toolbar scale index maps to the requested output size")
}
expect(gallery.neighbor(-1) == nil, "previous stops at the first file")
expect(gallery.neighbor(1)?.url.lastPathComponent == "10.png", "next follows folder order")
let secondDocument = gallery.select(galleryURL.appendingPathComponent("10.png"))!
let lastDocument = gallery.documents.last!
gallery.select(lastDocument.url)
expect(gallery.neighbor(1) == nil, "next stops at the last file")
gallery.select(firstDocument.url)
gallery.include(galleryURL.appendingPathComponent("3.png"))
expect(gallery.selected === firstDocument && gallery.neighbor(1)?.url.lastPathComponent == "3.png",
       "saving a new file preserves selection and updates navigation order")
gallery.include(galleryURL.appendingPathComponent("3.png"))
gallery.include(root.appendingPathComponent("outside.png"))
expect(gallery.documents.count == 7, "no duplicate or foreign folder entries")
expect(gallery.select(secondDocument.url) === secondDocument, "navigation reuses document state")

gallery.filterText = "PNG"
expect(gallery.visibleDocuments.map { $0.url.lastPathComponent } == ["2.png", "3.png", "10.png"],
       "quick filtering ignores case and preserves natural order")
gallery.descending = true
expect(gallery.visibleDocuments.map { $0.url.lastPathComponent } == ["10.png", "3.png", "2.png"],
       "descending order reverses the filtered list")
expect(gallery.selected === secondDocument && gallery.neighbor(1)?.url.lastPathComponent == "3.png",
       "sorting preserves the selected document and changes navigation order")
gallery.filterText = "photo"
expect(gallery.selected === secondDocument && gallery.neighbor(1)?.url.lastPathComponent == "photo.JPG",
       "filtering keeps the current preview and navigation enters the filtered list")
gallery.filterText = "no match"
expect(gallery.visibleDocuments.isEmpty && gallery.neighbor(1) == nil && gallery.documents.count == 7,
       "an empty filter result does not remove any document state")
gallery.filterText = " \n "
gallery.descending = false
expect(gallery.visibleDocuments.count == 7, "whitespace filter restores the full list")

let preferencesDomain = "local.ncf-image-upscaler.tests.\(UUID().uuidString)"
let migrationDomain = "local.ncf-image-upscaler.migration-tests.\(UUID().uuidString)"
let migrationDefaults = UserDefaults(suiteName: migrationDomain)!
migrationDefaults.set(320.0, forKey: "sidebar.width")
LegacyPreferences.migrate(defaults: migrationDefaults, legacy: ["sidebar.width": 500.0,
                          "sidebar.thumbnailSize": 144.0, "unrelated": "must not migrate"])
expect(migrationDefaults.double(forKey: "sidebar.width") == 320 &&
       migrationDefaults.double(forKey: "sidebar.thumbnailSize") == 144 &&
       migrationDefaults.object(forKey: "unrelated") == nil,
       "renaming imports only sidebar settings and preserves new preferences")
migrationDefaults.removeObject(forKey: "sidebar.thumbnailSize")
LegacyPreferences.migrate(defaults: migrationDefaults, legacy: ["sidebar.thumbnailSize": 200.0])
expect(migrationDefaults.object(forKey: "sidebar.thumbnailSize") == nil,
       "legacy preferences are imported only once")
migrationDefaults.removePersistentDomain(forName: migrationDomain)
let testDefaults = UserDefaults(suiteName: preferencesDomain)!
defer { testDefaults.removePersistentDomain(forName: preferencesDomain) }
let preferences = SidebarPreferences(defaults: testDefaults)
expect(preferences.width == 260 && preferences.thumbnailSize == 112 && !preferences.descending,
       "sidebar has usable defaults")
expect(preferences.gridMode == .regular, "the existing regular grid remains the default")
preferences.setGridMode(.adaptive)
expect(SidebarPreferences(defaults: testDefaults).gridMode == .adaptive, "the chosen grid mode survives recreation")
preferences.setGridMode(.regular)
preferences.setWidth(420)
preferences.setThumbnailSize(176)
preferences.setDescending(true)
preferences.setSortKey(.modified)
let restoredPreferences = SidebarPreferences(defaults: testDefaults)
expect(restoredPreferences.width == 420 && restoredPreferences.thumbnailSize == 176 && restoredPreferences.descending &&
       restoredPreferences.sortKey == .modified,
       "sidebar width, thumbnail size and ordering survive recreation")
expect(SidebarPreferences.boundedWidth(900, windowWidth: 1280) == 640 &&
       SidebarPreferences.boundedWidth(640, windowWidth: 1040) == 520,
       "sidebar stays within half the window, including after shrinking the window")
expect(SidebarPreferences.boundedWidth(20, windowWidth: 1280) == SidebarPreferences.minimumWidth,
       "sidebar keeps enough width for its toolbar")
preferences.setThumbnailSize(999)
expect(preferences.thumbnailSize == 400, "oversized thumbnail preferences are bounded")
preferences.setThumbnailSize(-10)
preferences.setWidth(20)
expect(preferences.thumbnailSize == 64 && preferences.width == SidebarPreferences.minimumWidth,
       "undersized preferences are bounded")
preferences.setWidth(.nan)
preferences.setThumbnailSize(.infinity)
expect(preferences.width == SidebarPreferences.minimumWidth && preferences.thumbnailSize == 64,
       "invalid geometry cannot corrupt saved preferences")

let narrowGrid = ThumbnailGridMetrics(availableWidth: 320, thumbnailSize: 112)
let wideGrid = ThumbnailGridMetrics(availableWidth: 700, thumbnailSize: 112)
expect(narrowGrid.columns == 2 && wideGrid.columns == 5, "grid adds columns as the panel grows")
let usedWidth = CGFloat(wideGrid.columns) * wideGrid.itemSize.width +
    CGFloat(wideGrid.columns - 1) * ThumbnailGridMetrics.gap + ThumbnailGridMetrics.inset * 2
expect(usedWidth <= 700 && 700 - usedWidth < CGFloat(wideGrid.columns),
       "grid fills the available width without overflowing or dropping card spacing")
let grownWidth = SidebarPreferences.boundedWidth(240, windowWidth: 1280, thumbnailSize: 400)
let singleGrid = ThumbnailGridMetrics(availableWidth: grownWidth - 20, thumbnailSize: 400)
expect(grownWidth == 460 && singleGrid.columns == 1 && singleGrid.itemSize.width >= 416,
       "large thumbnails grow the panel enough to fit one complete column")
expect(SidebarPreferences.boundedWidth(240, windowWidth: 1040, thumbnailSize: 400) <= 520,
       "one large column still respects half the smallest supported window")

let adaptiveSizes: [NSSize?] = [NSSize(width: 440, height: 200), NSSize(width: 200, height: 800),
    NSSize(width: 32, height: 24), NSSize(width: 1000, height: 1000), NSSize(width: 440, height: 200),
    NSSize(width: 6000, height: 300), nil, NSSize(width: 0, height: 0)]
let adaptiveGrid = AdaptiveThumbnailGrid(width: 700, thumbnailSize: 112, imageSizes: adaptiveSizes)
func hasReadingOrder(_ frames: [NSRect]) -> Bool {
    zip(frames, frames.dropFirst()).allSatisfy { previous, next in
        next.minY > previous.minY || (next.minY == previous.minY && next.minX > previous.minX)
    }
}
expect(hasReadingOrder(adaptiveGrid.frames),
       "adaptive placement follows sorted reading order instead of filling earlier gaps after a panorama")
expect(adaptiveGrid.frames[0].width == wideGrid.itemSize.width * 2 + 10 && adaptiveGrid.frames[0].width < 680 &&
       adaptiveGrid.frames[0].height == wideGrid.itemSize.height,
       "a landscape uses only the two columns it needs, rather than the entire five-column row")
expect(adaptiveGrid.frames[1].width == wideGrid.itemSize.width &&
       adaptiveGrid.frames[1].height == wideGrid.itemSize.height * 3 + 20,
       "a portrait uses three rows to maximize its width in one column")
expect(adaptiveGrid.frames[2].size == wideGrid.itemSize,
       "an image smaller than a thumbnail occupies one minimum cell")
for (index, frame) in adaptiveGrid.frames.enumerated() {
    expect(frame.minX >= 8 && frame.maxX <= 692 && frame.minY >= 8 && frame.maxY <= adaptiveGrid.contentSize.height - 8,
           "adaptive cards remain inside the available width and content height: \(index)")
    for other in adaptiveGrid.frames.dropFirst(index + 1) {
        expect(!frame.insetBy(dx: -4.9, dy: -4.9).intersects(other), "adaptive cards preserve spacing without overlapping")
    }
}
let landscapePreview = ThumbnailGeometry.imageRect(pixels: adaptiveSizes[0]!,
    in: NSRect(origin: .zero, size: NSSize(width: adaptiveGrid.frames[0].width - 16, height: 112)), enlarge: false)
let portraitPreview = ThumbnailGeometry.imageRect(pixels: adaptiveSizes[1]!,
    in: NSRect(origin: .zero, size: NSSize(width: adaptiveGrid.frames[1].width - 16,
                                        height: adaptiveGrid.frames[1].height - 58)), enlarge: false)
expect(abs(landscapePreview.height - 112) < 0.01 && abs(portraitPreview.width - 112) < 0.01,
       "landscapes maximize preview height and portraits maximize preview width without cropping")
let smallPreview = ThumbnailGeometry.imageRect(pixels: adaptiveSizes[2]!,
    in: NSRect(x: 0, y: 0, width: 112, height: 112), enlarge: false)
expect(smallPreview.size == NSSize(width: 32, height: 24) && smallPreview.midX == 56 && smallPreview.midY == 56,
       "small previews retain original pixel dimensions and center inside the minimum cell")
expect(ThumbnailGeometry.imageRect(pixels: NSSize(width: 32, height: 24),
    in: NSRect(x: 0, y: 0, width: 112, height: 112), enlarge: true).width == 112,
    "regular grid retains its existing thumbnail enlargement")
let narrowerAdaptive = AdaptiveThumbnailGrid(width: 300, thumbnailSize: 112, imageSizes: adaptiveSizes)
expect(narrowerAdaptive.frames.allSatisfy { $0.minX >= 8 && $0.maxX <= 292 } &&
       narrowerAdaptive.contentSize.height > adaptiveGrid.contentSize.height,
       "narrowing the panel repacks all adaptive cards without horizontal overflow")
let extremeAdaptive = AdaptiveThumbnailGrid(width: 700, thumbnailSize: 112,
    imageSizes: [NSSize(width: 1, height: 1_000_000_000), NSSize(width: CGFloat.nan, height: 20)])
expect(extremeAdaptive.frames.allSatisfy { $0.minX.isFinite && $0.maxY.isFinite } &&
       extremeAdaptive.frames[1].size == wideGrid.itemSize,
       "extreme or invalid dimensions yield finite, bounded layout geometry")
expect(ThumbnailGeometry.imageSize(at: importFirst) == NSSize(width: 100, height: 80),
       "thumbnail metadata reports original dimensions instead of the decoded thumbnail size")
let rotatedThumbnail = root.appendingPathComponent("rotated-thumbnail.jpg")
let rotatedWriter = CGImageDestinationCreateWithURL(rotatedThumbnail as CFURL, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(rotatedWriter, alphaBitmap.cgImage!, [kCGImagePropertyOrientation: 6] as CFDictionary)
expect(CGImageDestinationFinalize(rotatedWriter) &&
       ThumbnailGeometry.imageSize(at: rotatedThumbnail) == NSSize(width: 80, height: 100),
       "adaptive spans account for EXIF rotation without decoding the whole image")

// Disk backing survives RAM eviction without reading the original at all.
let cacheSource = root.appendingPathComponent("cache-source.png")
try pngBytes.write(to: cacheSource)
var thumbnailCache: ThumbnailCache? = ThumbnailCache()
let cacheDirectory = thumbnailCache!.session!.directory
let preparedCacheImage = ThumbnailCache.prepare(cacheSource, in: thumbnailCache!.session)!
expect(preparedCacheImage.file != nil && manager.fileExists(atPath: preparedCacheImage.file!.path),
       "the session stores a ready thumbnail outside the source folder")
expect(thumbnailCache!.insert(preparedCacheImage, for: cacheSource) != nil,
       "a prepared thumbnail becomes available in RAM immediately")
thumbnailCache!.releaseMemory()
try manager.removeItem(at: cacheSource)
let diskImage = thumbnailCache!.image(cacheSource)!
let diskBitmap = NSBitmapImageRep(cgImage: diskImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
let cachedPixel = diskBitmap.colorAt(x: 5, y: 5)!.usingColorSpace(.sRGB)!
expect(diskBitmap.pixelsWide == 100 && diskBitmap.pixelsHigh == 80 &&
       abs(cachedPixel.alphaComponent - sourcePixel.alphaComponent) < 0.01 &&
       abs(cachedPixel.redComponent - sourcePixel.redComponent) < 0.01 &&
       abs(cachedPixel.greenComponent - sourcePixel.greenComponent) < 0.01 &&
       abs(cachedPixel.blueComponent - sourcePixel.blueComponent) < 0.01,
       "after RAM eviction an absent original is not needed and cached PNG preserves partial alpha and RGB")
for background: CGFloat in [0, 1] {
    expect(abs((cachedPixel.redComponent * cachedPixel.alphaComponent + background * (1 - cachedPixel.alphaComponent)) -
               (sourcePixel.redComponent * sourcePixel.alphaComponent + background * (1 - sourcePixel.alphaComponent))) < 0.01,
           "cached transparency composes identically on light and dark backgrounds")
}
thumbnailCache!.prune(keeping: [])
expect(!thumbnailCache!.contains(cacheSource) && !manager.fileExists(atPath: preparedCacheImage.file!.path),
       "cleanup removes deleted entries and their session PNGs")
_ = thumbnailCache!.insert(nil, for: cacheSource)
expect(thumbnailCache!.contains(cacheSource) && thumbnailCache!.image(cacheSource) == nil,
       "failed decodes are remembered instead of retried on every navigation")
thumbnailCache = nil
expect(!manager.fileExists(atPath: cacheDirectory.path), "closing the cache removes its private temporary session")

// Attach a real collection to a hidden window. Metadata loading and AppKit's
// layout lifecycle are exercised without taking over the user's active app.
let layoutDirectory = root.appendingPathComponent("adaptive-layout", isDirectory: true)
try manager.createDirectory(at: layoutDirectory, withIntermediateDirectories: true)
var layoutURLs: [URL] = []
for (index, size) in adaptiveSizes.prefix(6).enumerated() {
    let size = size!
    let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
        bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let url = layoutDirectory.appendingPathComponent("image\(index).png")
    let writer = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, context.makeImage()!, nil)
    expect(CGImageDestinationFinalize(writer), "adaptive collection fixture is written")
    layoutURLs.append(url)
}
let layoutDomain = "local.ncf-image-upscaler.layout-tests.\(UUID().uuidString)"
let layoutDefaults = UserDefaults(suiteName: layoutDomain)!
defer { layoutDefaults.removePersistentDomain(forName: layoutDomain) }
let layoutPreferences = SidebarPreferences(defaults: layoutDefaults)
layoutPreferences.setGridMode(.adaptive)
let layoutPanel = FolderSidebar(preferences: layoutPreferences)
let layoutWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 850),
                            styleMask: [.titled], backing: .buffered, defer: false)
layoutPanel.frame = NSRect(x: 12, y: 12, width: 740, height: 800)
layoutWindow.contentView!.addSubview(layoutPanel)
layoutWindow.contentView!.layoutSubtreeIfNeeded()
let layoutSession = FolderSession(directory: layoutDirectory, urls: layoutURLs)
layoutSession.select(layoutURLs[0])
layoutPanel.display(layoutSession)
layoutPanel.setSelection([layoutSession.documents[0], layoutSession.documents[2]])
waitForTransition("adaptive collection reads every original's dimensions asynchronously") {
    (layoutPanel.collection.collectionViewLayout as? AdaptiveThumbnailLayout)?.imageSizes.compactMap { $0 }.count == 6
}
layoutPanel.collection.layoutSubtreeIfNeeded()
let actualAdaptiveLayout = layoutPanel.collection.collectionViewLayout as! AdaptiveThumbnailLayout
actualAdaptiveLayout.prepare()
let firstAdaptiveFrame = actualAdaptiveLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
let portraitAdaptiveFrame = actualAdaptiveLayout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
let smallAdaptiveFrame = actualAdaptiveLayout.layoutAttributesForItem(at: IndexPath(item: 2, section: 0))!.frame
expect(firstAdaptiveFrame.width > smallAdaptiveFrame.width && portraitAdaptiveFrame.height > smallAdaptiveFrame.height &&
       actualAdaptiveLayout.collectionViewContentSize.height >= portraitAdaptiveFrame.maxY,
       "AppKit's adaptive layout actually expands landscape and portrait frames and scrollable content")
expect(layoutPanel.selectedDocuments.count == 2, "asynchronous layout preserves multiple selection")
let portraitItem = layoutPanel.collectionView(layoutPanel.collection, itemForRepresentedObjectAt: IndexPath(item: 1, section: 0))
portraitItem.view.frame = portraitAdaptiveFrame
portraitItem.view.layoutSubtreeIfNeeded()
let portraitCard = portraitItem.view as! ThumbnailCard
expect(abs(portraitCard.preview.bounds.height - (portraitAdaptiveFrame.height - 58)) < 0.01 && !portraitCard.preview.enlarge,
       "a portrait's preview expands with the multirow card while its title and progress remain in the footer")
expect(actualAdaptiveLayout.layoutAttributesForDropTarget(at: NSPoint(x: firstAdaptiveFrame.midX, y: firstAdaptiveFrame.midY)) != nil &&
       actualAdaptiveLayout.layoutAttributesForInterItemGap(before: IndexPath(item: 0, section: 0)) != nil,
       "adaptive layout supplies native drag and drop target geometry")
let layoutRegularButton = descendants(layoutPanel).compactMap { $0 as? NSButton }.first {
    $0.accessibilityLabel() == "Regular grid"
}!
NSApp.sendAction(layoutRegularButton.action!, to: layoutRegularButton.target, from: layoutRegularButton)
expect(layoutPanel.collection.collectionViewLayout is NSCollectionViewFlowLayout && layoutPanel.selectedDocuments.count == 2,
       "a real collection switches back to the regular grid without losing multiple selection")
for index in layoutURLs.indices {
    _ = layoutPanel.collectionView(layoutPanel.collection, itemForRepresentedObjectAt: IndexPath(item: index, section: 0))
}
waitForTransition("all six session thumbnails are generated once") { layoutPanel.pendingThumbnailCount == 0 }
let warmLoads = layoutPanel.thumbnailLoadCount
let warmMetadata = layoutPanel.metadataReadCount
expect(warmLoads == 6, "each source is decoded once even across grid-mode changes")
let visibleBeforeNavigation = layoutPanel.collection.visibleItems().compactMap { item -> (NSView, NSImage)? in
    guard let card = item.view as? ThumbnailCard, let image = card.preview.image else { return nil }
    return (card, image)
}
for index in 0..<60 {
    layoutSession.select(layoutURLs[index % layoutURLs.count])
    layoutPanel.display(layoutSession, revealSelection: false)
}
expect(layoutPanel.thumbnailLoadCount == warmLoads && layoutPanel.metadataReadCount == warmMetadata &&
       layoutPanel.pendingThumbnailCount == 0,
       "sixty navigation changes do not read headers or regenerate any thumbnail")
expect(!visibleBeforeNavigation.isEmpty && visibleBeforeNavigation.allSatisfy { view, image in
    (view as! ThumbnailCard).preview.image === image
}, "navigation preserves the exact visible NSImages rather than clearing or replacing them")
layoutPanel.cleanThumbnailCache()
let recycledCards = layoutURLs.indices.map {
    layoutPanel.collectionView(layoutPanel.collection, itemForRepresentedObjectAt: IndexPath(item: $0, section: 0)).view as! ThumbnailCard
}
expect(recycledCards.allSatisfy { $0.preview.image != nil } && layoutPanel.thumbnailLoadCount == warmLoads,
       "after periodic RAM cleanup recycled cards synchronously receive ready cached images without source decoding")
let layoutAdaptiveButton = descendants(layoutPanel).compactMap { $0 as? NSButton }.first {
    $0.accessibilityLabel() == "Adaptive grid"
}!
let layoutSlider = descendants(layoutPanel).compactMap { $0 as? NSSlider }.first!
for size in [400.0, 64.0, 176.0] {
    layoutSlider.doubleValue = size
    NSApp.sendAction(layoutSlider.action!, to: layoutSlider.target, from: layoutSlider)
    NSApp.sendAction(layoutAdaptiveButton.action!, to: layoutAdaptiveButton.target, from: layoutAdaptiveButton)
    NSApp.sendAction(layoutRegularButton.action!, to: layoutRegularButton.target, from: layoutRegularButton)
}
expect(layoutPanel.thumbnailLoadCount == warmLoads && layoutPanel.metadataReadCount == warmMetadata,
       "all slider sizes and both layouts reuse the same once-generated thumbnails")
let editedURL = layoutURLs[0]
let beforeEditData = try Data(contentsOf: editedURL)
let beforeEditImage = (layoutPanel.collection.item(at: IndexPath(item: 0, section: 0))?.view as? ThumbnailCard)?.preview.image
let editedWriter = try FileHandle(forWritingTo: editedURL)
try editedWriter.write(contentsOf: beforeEditData)
try editedWriter.close()
layoutSession.documents[0].refreshMetadata()
layoutPanel.display(layoutSession, revealSelection: false)
let duringEditImage = (layoutPanel.collection.item(at: IndexPath(item: 0, section: 0))?.view as? ThumbnailCard)?.preview.image
expect(beforeEditImage != nil && duringEditImage === beforeEditImage,
       "a changed source keeps its previous visible thumbnail while the replacement is generated")
waitForTransition("only the edited file is regenerated") {
    layoutPanel.pendingThumbnailCount == 0 && layoutPanel.thumbnailLoadCount == warmLoads + 1
}
let nextThumbnailSession = FolderSession(directory: layoutDirectory, urls: layoutURLs)
layoutPanel.display(nextThumbnailSession, revealSelection: false)
for index in layoutURLs.indices {
    _ = layoutPanel.collectionView(layoutPanel.collection, itemForRepresentedObjectAt: IndexPath(item: index, section: 0))
}
waitForTransition("reopening the folder starts a fresh thumbnail session") {
    layoutPanel.pendingThumbnailCount == 0 && layoutPanel.thumbnailLoadCount == warmLoads + 7
}
layoutPanel.endThumbnailSession()
layoutWindow.close()

// Opening a file near the end initially lays out unknown dimensions as single
// cells. The asynchronous portrait spans must not scroll the open file away.
let revealDirectory = root.appendingPathComponent("adaptive-reveal", isDirectory: true)
try manager.createDirectory(at: revealDirectory, withIntermediateDirectories: true)
let revealPortraitData = try Data(contentsOf: layoutURLs[1])
let revealURLs = try (0..<64).map { index -> URL in
    let url = revealDirectory.appendingPathComponent(String(format: "%03d.png", index))
    try revealPortraitData.write(to: url)
    return url
}
let revealDefaults = UserDefaults(suiteName: "\(preferencesDomain).reveal")!
defer { revealDefaults.removePersistentDomain(forName: "\(preferencesDomain).reveal") }
let revealPreferences = SidebarPreferences(defaults: revealDefaults)
revealPreferences.setGridMode(.adaptive)
let revealPanel = FolderSidebar(preferences: revealPreferences)
let revealWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
revealWindow.isReleasedWhenClosed = false
revealPanel.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
revealWindow.contentView!.addSubview(revealPanel)
revealWindow.contentView!.layoutSubtreeIfNeeded()
let revealSession = FolderSession(directory: revealDirectory, urls: revealURLs)
revealSession.select(revealURLs[50])
revealPanel.display(revealSession)
let revealPath = IndexPath(item: 50, section: 0)
waitForTransition("opening near the end waits for all adaptive source dimensions") {
    (revealPanel.collection.collectionViewLayout as? AdaptiveThumbnailLayout)?.imageSizes.compactMap { $0 }.count == 64 &&
        revealPanel.pendingThumbnailCount == 0
}
let revealedFrame = revealPanel.collection.collectionViewLayout!.layoutAttributesForItem(at: revealPath)!.frame
expect(revealedFrame.intersects(revealPanel.collection.visibleRect),
       "the opened file stays visible after asynchronous thumbnail loading expands preceding portrait cards")
let revealClip = revealPanel.collection.enclosingScrollView!.contentView
revealClip.scroll(to: .zero)
let revealSlider = descendants(revealPanel).compactMap { $0 as? NSSlider }.first!
revealSlider.doubleValue = 176
NSApp.sendAction(revealSlider.action!, to: revealSlider.target, from: revealSlider)
expect(revealClip.bounds.minY < 1 && !revealPanel.collection.visibleRect.intersects(
    revealPanel.collection.collectionViewLayout!.layoutAttributesForItem(at: revealPath)!.frame),
    "after a user scrolls away, relayout preserves their browsing position instead of snapping to the open file")
revealPanel.endThumbnailSession()
revealWindow.close()

// A tall card and a short neighbour on the same row must not bounce the
// viewport down and back up just because their vertical centres differ.
let navigationDefaults = UserDefaults(suiteName: "\(preferencesDomain).navigation")!
defer { navigationDefaults.removePersistentDomain(forName: "\(preferencesDomain).navigation") }
let navigationPreferences = SidebarPreferences(defaults: navigationDefaults)
navigationPreferences.setGridMode(.adaptive)
let navigationPanel = FolderSidebar(preferences: navigationPreferences)
let navigationWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
navigationWindow.isReleasedWhenClosed = false
navigationPanel.frame = NSRect(x: 0, y: 0, width: 740, height: 380)
navigationWindow.contentView!.addSubview(navigationPanel)
navigationWindow.contentView!.layoutSubtreeIfNeeded()
let navigationSession = FolderSession(directory: layoutDirectory, urls: layoutURLs)
navigationPanel.display(navigationSession)
waitForTransition("mixed-height navigation waits for stable adaptive geometry") {
    (navigationPanel.collection.collectionViewLayout as? AdaptiveThumbnailLayout)?.imageSizes.compactMap { $0 }.count == 6 &&
        navigationPanel.pendingThumbnailCount == 0
}
let navigationClip = navigationPanel.collection.enclosingScrollView!.contentView
navigationClip.scroll(to: .zero)
navigationSession.select(layoutURLs[1])
navigationPanel.display(navigationSession)
expect(navigationClip.bounds.minY < 1,
       "selecting an already visible oversized portrait does not centre it or move the list")
let beforeShortNeighbour = navigationClip.bounds.minY
navigationSession.select(layoutURLs[2])
navigationPanel.display(navigationSession)
expect(navigationClip.bounds.minY == beforeShortNeighbour,
       "next from a tall card to its short neighbour on the same row does not bounce the viewport")
var forwardOffsets: [CGFloat] = []
for url in layoutURLs {
    navigationSession.select(url)
    navigationPanel.display(navigationSession)
    forwardOffsets.append(navigationClip.bounds.minY)
}
expect(zip(forwardOffsets, forwardOffsets.dropFirst()).allSatisfy { $1 >= $0 },
       "forward navigation through mixed spans never scrolls back upward")
let lastNavigationFrame = navigationPanel.collection.collectionViewLayout!
    .layoutAttributesForItem(at: IndexPath(item: 5, section: 0))!.frame
expect(abs(navigationClip.bounds.minY - (lastNavigationFrame.maxY - navigationClip.bounds.height)) < 1,
       "an offscreen short card moves only to the nearest viewport edge rather than being centred")
var backwardOffsets: [CGFloat] = []
for url in layoutURLs.reversed() {
    navigationSession.select(url)
    navigationPanel.display(navigationSession)
    backwardOffsets.append(navigationClip.bounds.minY)
}
expect(zip(backwardOffsets, backwardOffsets.dropFirst()).allSatisfy { $1 <= $0 },
       "backward navigation through mixed spans never scrolls forward downward")
navigationPanel.endThumbnailSession()
navigationWindow.close()

// Hold real background work at deterministic checkpoints, without showing a
// window or relying on slow files to make the loading skeleton observable.
let skeletonMetadataGate = DispatchGroup()
let skeletonDecodeGate = DispatchGroup()
skeletonMetadataGate.enter()
skeletonDecodeGate.enter()
var skeletonMetadataReleased = false, skeletonDecodeReleased = false
defer {
    if !skeletonMetadataReleased { skeletonMetadataGate.leave() }
    if !skeletonDecodeReleased { skeletonDecodeGate.leave() }
}
let skeletonDefaults = UserDefaults(suiteName: "\(preferencesDomain).skeleton")!
defer { skeletonDefaults.removePersistentDomain(forName: "\(preferencesDomain).skeleton") }
let skeletonPreferences = SidebarPreferences(defaults: skeletonDefaults)
skeletonPreferences.setGridMode(.adaptive)
let skeletonPanel = FolderSidebar(preferences: skeletonPreferences, loadThumbnail: { url, session in
    guard skeletonDecodeGate.wait(timeout: .now() + 10) == .success else { return nil }
    return url == layoutURLs[2] ? nil : ThumbnailCache.prepare(url, in: session)
}, loadImageSize: { url in
    guard skeletonMetadataGate.wait(timeout: .now() + 10) == .success else { return nil }
    return ThumbnailGeometry.imageSize(at: url)
})
let skeletonWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
skeletonWindow.isReleasedWhenClosed = false
skeletonPanel.frame = NSRect(x: 12, y: 12, width: 740, height: 800)
skeletonWindow.contentView!.addSubview(skeletonPanel)
skeletonWindow.contentView!.layoutSubtreeIfNeeded()
let skeletonSession = FolderSession(directory: layoutDirectory, urls: layoutURLs)
skeletonSession.select(layoutURLs[0])
skeletonPanel.display(skeletonSession)
func skeletonCard(_ index: Int) -> ThumbnailCard {
    (skeletonPanel.collection.item(at: IndexPath(item: index, section: 0)) ??
     skeletonPanel.collectionView(skeletonPanel.collection, itemForRepresentedObjectAt: IndexPath(item: index, section: 0)))
        .view as! ThumbnailCard
}
func skeletonFrame(_ index: Int) -> NSRect {
    skeletonPanel.collection.collectionViewLayout!.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
}
func saveSkeletonSnapshot(_ name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["NCF_IMAGE_UPSCALER_TEST_SNAPSHOTS"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    skeletonPanel.layoutSubtreeIfNeeded()
    let bitmap = skeletonPanel.bitmapImageRepForCachingDisplay(in: skeletonPanel.bounds)!
    skeletonPanel.cacheDisplay(in: skeletonPanel.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name).png"))
}
expect(skeletonPanel.isPreparingGrid && skeletonCard(0).preview.showsSkeleton,
       "a skeleton is visible synchronously while adaptive metadata is still loading")
expect(skeletonFrame(1).width > skeletonFrame(0).width && skeletonFrame(2).height > skeletonFrame(0).height,
       "even before metadata arrives the adaptive skeleton imitates wide and tall cells, not a uniform grid")
try saveSkeletonSnapshot("adaptive-before-metadata")
let skeletonButtons = descendants(skeletonPanel).compactMap { $0 as? NSButton }
let skeletonRegular = skeletonButtons.first { $0.accessibilityLabel() == "Regular grid" }!
let skeletonAdaptive = skeletonButtons.first { $0.accessibilityLabel() == "Adaptive grid" }!
let skeletonSlider = descendants(skeletonPanel).compactMap { $0 as? NSSlider }.first!
NSApp.sendAction(skeletonRegular.action!, to: skeletonRegular.target, from: skeletonRegular)
expect(!skeletonPanel.isPreparingGrid && skeletonFrame(0).size == skeletonFrame(1).size &&
       skeletonFrame(1).size == skeletonFrame(2).size && skeletonCard(0).preview.showsSkeleton,
       "the simple grid immediately uses uniform skeleton cells even with metadata work pending")
for size in [64.0, 176.0] {
    skeletonSlider.doubleValue = size
    NSApp.sendAction(skeletonSlider.action!, to: skeletonSlider.target, from: skeletonSlider)
    expect(abs(skeletonFrame(0).height - size - 58) < 0.01 && skeletonCard(0).preview.showsSkeleton,
           "simple skeleton cells track the configured thumbnail size while decoding is blocked")
}
skeletonSlider.doubleValue = 112
NSApp.sendAction(skeletonSlider.action!, to: skeletonSlider.target, from: skeletonSlider)
try saveSkeletonSnapshot("regular-before-metadata")
NSApp.sendAction(skeletonAdaptive.action!, to: skeletonAdaptive.target, from: skeletonAdaptive)
expect(skeletonPanel.isPreparingGrid && skeletonFrame(1).width > skeletonFrame(0).width,
       "switching back to adaptive restores the mixed skeleton pattern without restarting reads")
let smallAdaptiveSkeletonWidth = skeletonFrame(0).width
skeletonSlider.doubleValue = 176
NSApp.sendAction(skeletonSlider.action!, to: skeletonSlider.target, from: skeletonSlider)
expect(skeletonFrame(0).width > smallAdaptiveSkeletonWidth && skeletonFrame(1).width > skeletonFrame(0).width &&
       skeletonFrame(2).height > skeletonFrame(0).height && skeletonCard(0).preview.showsSkeleton,
       "adaptive skeleton spans also resize with the slider while real dimensions are still unknown")
skeletonSlider.doubleValue = 112
NSApp.sendAction(skeletonSlider.action!, to: skeletonSlider.target, from: skeletonSlider)
skeletonMetadataReleased = true
skeletonMetadataGate.leave()
waitForTransition("skeleton adopts actual geometry when all headers arrive, before any image decode completes") {
    !skeletonPanel.isPreparingGrid &&
        (skeletonPanel.collection.collectionViewLayout as? AdaptiveThumbnailLayout)?.imageSizes.compactMap { $0 }.count == 6
}
expect(skeletonFrame(0).width > skeletonFrame(2).width && skeletonFrame(1).height > skeletonFrame(2).height,
       "the adaptive skeleton switches from estimated spans to exact landscape and portrait spans")
expect(skeletonCard(0).preview.showsSkeleton && skeletonCard(1).preview.showsSkeleton &&
       skeletonCard(0).preview.image == nil,
       "skeletons remain visible after layout is ready until the image itself has loaded")
let portraitSkeleton = skeletonCard(1).preview
portraitSkeleton.layoutSubtreeIfNeeded()
expect(portraitSkeleton.bounds.contains(portraitSkeleton.skeletonFrame) &&
       portraitSkeleton.skeletonFrame.height > portraitSkeleton.skeletonFrame.width * 3.9,
       "the portrait skeleton fills its real multirow preview in the correct aspect ratio")
let tinySkeleton = skeletonCard(2).preview
tinySkeleton.layoutSubtreeIfNeeded()
expect(tinySkeleton.skeletonFrame.size == NSSize(width: 32, height: 24),
       "a tiny adaptive image has an original-size skeleton inside one minimum cell")
try saveSkeletonSnapshot("adaptive-exact-geometry")
skeletonDecodeReleased = true
skeletonDecodeGate.leave()
waitForTransition("ready images replace skeletons and failed decodes stop loading") {
    skeletonPanel.pendingThumbnailCount == 0
}
expect(!skeletonCard(0).preview.showsSkeleton && skeletonCard(0).preview.image != nil &&
       !skeletonCard(1).preview.showsSkeleton,
       "successful thumbnails replace their skeletons immediately")
expect(!skeletonCard(2).preview.showsSkeleton && skeletonCard(2).preview.image == nil &&
       skeletonCard(2).preview.accessibilityLabel() == "Preview unavailable",
       "a failed preview stops its skeleton instead of pulsing forever")
let skeletonWarmLoads = skeletonPanel.thumbnailLoadCount
let skeletonWarmImage = skeletonCard(0).preview.image
skeletonPanel.cleanThumbnailCache()
skeletonPanel.display(skeletonSession)
expect(!skeletonCard(0).preview.showsSkeleton && skeletonCard(0).preview.image === skeletonWarmImage &&
       skeletonPanel.thumbnailLoadCount == skeletonWarmLoads,
       "cached navigation and periodic memory cleanup never flash a skeleton over ready thumbnails")
try saveSkeletonSnapshot("ready-thumbnails")
let skeletonStateView = ThumbnailView(frame: NSRect(x: 0, y: 0, width: 112, height: 112))
skeletonWindow.contentView!.addSubview(skeletonStateView)
skeletonStateView.representedURL = layoutURLs[0]
skeletonStateView.waitsForLayout = true
skeletonStateView.isLoading = true
skeletonStateView.image = alphaImage
expect(skeletonStateView.showsSkeleton, "an early image stays behind its skeleton until adaptive layout is ready")
let skeletonHighlight = skeletonStateView.layer!.sublayers!.first { $0.name == "thumbnail-loading-highlight" }!
expect((skeletonHighlight.animation(forKey: "loading") != nil) == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
       "skeleton pulsing respects the system Reduce Motion setting")
skeletonStateView.isHidden = true
expect(skeletonHighlight.animation(forKey: "loading") == nil, "hidden skeletons stop animating")
skeletonStateView.isHidden = false
skeletonStateView.waitsForLayout = false
expect(!skeletonStateView.showsSkeleton, "finishing layout reveals an already decoded thumbnail")
expect(skeletonHighlight.animation(forKey: "loading") == nil, "ready thumbnails remove the skeleton animation")
skeletonStateView.waitsForLayout = true
expect(!skeletonStateView.showsSkeleton, "background relayout never hides a previously presented image behind a skeleton")
skeletonStateView.representedURL = layoutURLs[1]
skeletonStateView.image = nil
expect(skeletonStateView.showsSkeleton, "a recycled card resets its presentation state for another file")
skeletonPanel.endThumbnailSession()
skeletonWindow.close()

// Standard Mac file-list navigation in a hidden window. Route physical Fn key
// codes through the real window handler and preserve Shift's range anchor.
let keyboardDefaults = UserDefaults(suiteName: "\(preferencesDomain).keyboard")!
defer { keyboardDefaults.removePersistentDomain(forName: "\(preferencesDomain).keyboard") }
let keyboardPreferences = SidebarPreferences(defaults: keyboardDefaults)
let keyboardPanel = FolderSidebar(preferences: keyboardPreferences)
let keyboardWindow = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                                  styleMask: [.titled], backing: .buffered, defer: false)
keyboardWindow.isReleasedWhenClosed = false
keyboardPanel.frame = NSRect(x: 0, y: 0, width: 740, height: 540)
keyboardWindow.contentView!.addSubview(keyboardPanel)
keyboardWindow.contentView!.layoutSubtreeIfNeeded()
let keyboardSession = FolderSession(directory: revealDirectory, urls: revealURLs)
keyboardSession.select(revealURLs[0])
var keyboardOpened: [URL] = []
keyboardPanel.onSelect = { [weak keyboardPanel] url in
    keyboardOpened.append(url)
    keyboardSession.select(url)
    keyboardPanel?.display(keyboardSession)
}
keyboardWindow.onFileNavigation = { [weak keyboardPanel] action, extend in
    keyboardPanel?.navigate(action, extendingSelection: extend) ?? false
}
keyboardPanel.display(keyboardSession)
keyboardWindow.makeFirstResponder(keyboardPanel.collection)
func fileNavigationEvent(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: code)!
}
func keyboardPress(_ code: UInt16, modifiers: NSEvent.ModifierFlags = [.function]) -> Bool {
    keyboardWindow.handleFileNavigation(fileNavigationEvent(code, modifiers: modifiers))
}
let keyboardClip = keyboardPanel.collection.enclosingScrollView!.contentView
expect(keyboardPress(121), "Fn+Down routes Page Down from the window into the file list")
let keyboardFirstPage = keyboardSession.visibleDocuments.firstIndex { $0 === keyboardSession.selected }!
expect(keyboardFirstPage > 1 && keyboardClip.bounds.minY > keyboardClip.bounds.height / 2,
       "Page Down moves by a visible page, not by one image or a tiny edge scroll")
expect(keyboardPress(121), "repeated Page Down is handled")
let keyboardSecondPage = keyboardSession.visibleDocuments.firstIndex { $0 === keyboardSession.selected }!
expect(keyboardSecondPage > keyboardFirstPage, "repeated paging continues forward through the sorted list")
expect(keyboardPress(116) && keyboardSession.selected?.url == revealURLs[keyboardFirstPage],
       "Fn+Up returns one page while retaining the visual column")
expect(keyboardPress(115) && keyboardSession.selected?.url == revealURLs.first,
       "Fn+Left goes to the first file")
expect(keyboardPress(119) && keyboardSession.selected?.url == revealURLs.last,
       "Fn+Right goes to the last file")
let keyboardLastFrame = keyboardPanel.collection.collectionViewLayout!
    .layoutAttributesForItem(at: IndexPath(item: 63, section: 0))!.frame
expect(keyboardPanel.collection.visibleRect.intersects(keyboardLastFrame), "the last file is made visible")
expect(keyboardPress(126, modifiers: .command) && keyboardSession.selected?.url == revealURLs.first,
       "Command+Up goes to the first file")
expect(keyboardPress(125, modifiers: .command) && keyboardSession.selected?.url == revealURLs.last,
       "Command+Down goes to the last file")
expect(keyboardPress(115, modifiers: [.function, .shift]) && keyboardPanel.selectedDocuments.count == 64 &&
       keyboardSession.selected?.url == revealURLs.first,
       "Shift+Fn+Left selects through the first file and opens the moving end of the range")
expect(keyboardPress(119, modifiers: [.function, .shift]) && keyboardPanel.selectedDocuments.count == 1 &&
       keyboardSession.selected?.url == revealURLs.last,
       "reversing Shift+Home/End contracts the same anchored range")
_ = keyboardPress(126, modifiers: .command)
_ = keyboardPress(121, modifiers: [.function, .shift])
expect(keyboardPanel.selectedDocuments.count == keyboardFirstPage + 1,
       "Shift+Page Down extends selection from the original anchor")
_ = keyboardPress(121, modifiers: [.function, .shift])
expect(keyboardPanel.selectedDocuments.count == keyboardSecondPage + 1,
       "repeated Shift+Page Down preserves its anchor across preview updates")
_ = keyboardPress(116, modifiers: [.function, .shift])
expect(keyboardPanel.selectedDocuments.count == keyboardFirstPage + 1,
       "Shift+Page Up contracts the page range")
_ = keyboardPress(116)
expect(keyboardPanel.selectedDocuments.count == 1 && keyboardSession.selected?.url == revealURLs.first,
       "paging without Shift collapses a multiple selection")
keyboardPanel.setSelection([keyboardSession.documents[30]])
_ = keyboardPress(119, modifiers: [.function, .shift])
expect(keyboardPanel.selectedDocuments.count == 34,
       "a new mouse/programmatic selection resets the range anchor rather than reusing an old keyboard range")
let keyboardSearch = descendants(keyboardPanel).compactMap { $0 as? NSSearchField }.first!
keyboardWindow.makeFirstResponder(keyboardSearch)
let beforeTextNavigation = keyboardOpened.count
expect(!keyboardPress(121) && !keyboardPress(125, modifiers: .command) && keyboardOpened.count == beforeTextNavigation,
       "page and Command+arrow shortcuts retain native text-editing behaviour inside the filter field")
keyboardWindow.makeFirstResponder(keyboardPanel.collection)
keyboardSearch.stringValue = "00"
keyboardPanel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: keyboardSearch))
_ = keyboardPress(119)
expect(keyboardSession.selected?.url == revealURLs[9] && keyboardSession.visibleDocuments.count == 10,
       "End targets the last filtered file rather than the end of the whole directory")
let keyboardSort = descendants(keyboardPanel).compactMap { $0 as? NSPopUpButton }.first!
keyboardSort.selectItem(at: 1)
NSApp.sendAction(keyboardSort.action!, to: keyboardSort.target, from: keyboardSort)
_ = keyboardPress(115)
expect(keyboardSession.selected?.url == revealURLs[9], "Home respects descending sort order")
_ = keyboardPress(119)
expect(keyboardSession.selected?.url == revealURLs[0], "End respects descending sort order")
keyboardSearch.stringValue = ""
keyboardPanel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: keyboardSearch))
keyboardSort.selectItem(at: 0)
NSApp.sendAction(keyboardSort.action!, to: keyboardSort.target, from: keyboardSort)
let keyboardAdaptive = descendants(keyboardPanel).compactMap { $0 as? NSButton }.first {
    $0.accessibilityLabel() == "Adaptive grid"
}!
NSApp.sendAction(keyboardAdaptive.action!, to: keyboardAdaptive.target, from: keyboardAdaptive)
waitForTransition("keyboard paging waits for adaptive geometry") { !keyboardPanel.isPreparingGrid }
_ = keyboardPress(115)
_ = keyboardPress(121)
let adaptivePageIndex = keyboardSession.visibleDocuments.firstIndex { $0 === keyboardSession.selected }!
expect(adaptivePageIndex > 0 && adaptivePageIndex < keyboardFirstPage,
       "adaptive paging uses tall card geometry instead of the regular grid's item count")
expect(keyboardPanel.collection.visibleRect.intersects(keyboardPanel.collection.collectionViewLayout!
    .layoutAttributesForItem(at: IndexPath(item: adaptivePageIndex, section: 0))!.frame),
       "the adaptive page target remains visible")
_ = keyboardPress(116)
expect(keyboardSession.selected?.url == revealURLs.first, "adaptive Page Up returns to the first row")
_ = keyboardPress(119)
_ = keyboardPress(121)
expect(keyboardSession.selected?.url == revealURLs.last, "Page Down at the end stops without wrapping")
keyboardPanel.collection.keyDown(with: fileNavigationEvent(115, modifiers: .function))
expect(keyboardSession.selected?.url == revealURLs.first,
       "Home also works through the collection responder's own keyboard route")
keyboardSearch.stringValue = "no-file-matches"
keyboardPanel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: keyboardSearch))
let beforeEmptyNavigation = keyboardOpened.count
expect(!keyboardPress(115) && !keyboardPress(121) && keyboardOpened.count == beforeEmptyNavigation,
       "navigation safely ignores an empty filtered list")
keyboardPanel.endThumbnailSession()
keyboardWindow.close()

for width: CGFloat in [300, 420, 454, 474, 700] {
    for size: CGFloat in [64, 112, 120.1158644153226, 176] {
        let squares = AdaptiveThumbnailGrid(width: width, thumbnailSize: size,
            imageSizes: [1000, 600, 900, 1024, 1023, 32].map { NSSize(width: $0, height: $0) })
        let base = ThumbnailGridMetrics(availableWidth: width, thumbnailSize: size)
        expect(squares.frames.allSatisfy {
            abs($0.width - base.itemSize.width) < 0.01 && abs(($0.height - 58) - ($0.width - 16)) < 0.01
        }, "square images occupy one square preview cell at every panel width and fractional slider size")
    }
}
let standardAspectSizes = [NSSize(width: 1250, height: 1000), NSSize(width: 1000, height: 1250),
    NSSize(width: 1200, height: 1000), NSSize(width: 1000, height: 1200), NSSize(width: 1024, height: 960),
    NSSize(width: 800, height: 600), NSSize(width: 600, height: 800),
    NSSize(width: 1500, height: 1000), NSSize(width: 1000, height: 1500),
    NSSize(width: 1600, height: 1000), NSSize(width: 1000, height: 1600),
    NSSize(width: 2560, height: 1600), NSSize(width: 1600, height: 2560)]
let standardAspects = AdaptiveThumbnailGrid(width: 700, thumbnailSize: 112, imageSizes: standardAspectSizes)
for (size, frame) in zip(standardAspectSizes, standardAspects.frames) {
    let previewBounds = NSRect(x: 0, y: 0, width: frame.width - 16, height: frame.height - 58)
    let drawn = ThumbnailGeometry.imageRect(pixels: size, in: previewBounds, enlarge: false)
    expect(frame.size == wideGrid.itemSize && ThumbnailGeometry.usesSingleCellAspect(size) &&
           abs(drawn.width / drawn.height - size.width / size.height) < 0.001 &&
           drawn.width * drawn.height / (previewBounds.width * previewBounds.height) >= 10.0 / 16.0 - 0.0001,
           "photo and screen aspects up to 16:10 use one cell and preserve proportions in both orientations")
}
let outsideSquareTolerance = AdaptiveThumbnailGrid(width: 700, thumbnailSize: 112,
    imageSizes: [NSSize(width: 1601, height: 1000), NSSize(width: 1000, height: 1601),
                 NSSize(width: 1920, height: 1080), NSSize(width: 1080, height: 1920),
                 NSSize(width: 3840, height: 2160), NSSize(width: 2160, height: 3840)])
for index in stride(from: 0, to: outsideSquareTolerance.frames.count, by: 2) {
    expect(outsideSquareTolerance.frames[index].width > wideGrid.itemSize.width &&
           outsideSquareTolerance.frames[index + 1].height > wideGrid.itemSize.height,
           "images beyond 16:10, including Full HD/4K, expand horizontally or vertically")
}
let largeLayoutSizes: [NSSize?] = (0..<2000).map { index in
    [NSSize(width: 1200, height: 1000), NSSize(width: 440, height: 200),
     NSSize(width: 200, height: 800), NSSize(width: 32, height: 24)][index % 4]
}
let layoutBenchmarkStart = Date()
let largeAdaptive = AdaptiveThumbnailGrid(width: 700, thumbnailSize: 112, imageSizes: largeLayoutSizes)
let layoutBenchmarkMilliseconds = Date().timeIntervalSince(layoutBenchmarkStart) * 1000
expect(largeAdaptive.frames.count == 2000 && largeAdaptive.contentSize.height.isFinite,
       "a large mixed-aspect gallery has finite geometry without allocating per-row cell maps")
print("Adaptive layout: 2000 items in \(Int(layoutBenchmarkMilliseconds.rounded())) ms")
for width: CGFloat in [240, 300, 420, 700, 1100] {
    for thumbnailSize: CGFloat in [64, 112, 176] {
        let ordered = AdaptiveThumbnailGrid(width: width, thumbnailSize: thumbnailSize,
            imageSizes: Array(largeLayoutSizes.prefix(120)))
        let reversed = AdaptiveThumbnailGrid(width: width, thumbnailSize: thumbnailSize,
            imageSizes: Array(largeLayoutSizes.prefix(120).reversed()))
        expect(hasReadingOrder(ordered.frames) && hasReadingOrder(reversed.frames),
               "normal and reversed sorting keep visual reading order at every tested panel width and thumbnail size")
    }
}

let sortingURL = root.appendingPathComponent("sorting")
try manager.createDirectory(at: sortingURL, withIntermediateDirectories: true)
for (name, size, seconds) in [("b.png", 1, 10.0), ("a.jpg", 5, 30.0), ("c.bmp", 3, 20.0)] {
    let url = sortingURL.appendingPathComponent(name)
    try Data(repeating: 1, count: size).write(to: url)
    try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: url.path)
}
let sorting = FolderSession(directory: sortingURL, urls: try FolderSession.images(in: sortingURL))
sorting.select(sortingURL.appendingPathComponent("a.jpg"))
sorting.sortKey = .fileSize
expect(sorting.visibleDocuments.map { $0.url.lastPathComponent } == ["b.png", "c.bmp", "a.jpg"],
       "size sort compares file bytes rather than names")
sorting.sortKey = .modified
expect(sorting.visibleDocuments.map { $0.url.lastPathComponent } == ["b.png", "c.bmp", "a.jpg"],
       "modified sort compares filesystem modification dates")
sorting.descending = true
expect(sorting.visibleDocuments.first === sorting.selected && sorting.neighbor(1)?.url.lastPathComponent == "c.bmp",
       "reverse metadata sorting preserves selection and navigation order")
sorting.descending = false
sorting.sortKey = .fileType
expect(sorting.visibleDocuments.map { $0.url.pathExtension } == ["bmp", "jpg", "png"],
       "type sort groups file extensions")
sorting.sortKey = .created
let creationDates = sorting.visibleDocuments.map { $0.created }
expect(creationDates == creationDates.sorted(), "created sort uses creation dates")

firstDocument.processing = .preparing
expect(firstDocument.processing?.percentage == nil && !firstDocument.hasUnsavedResult,
       "preparing shows indeterminate progress without claiming a finished result")
firstDocument.processing = .processing(45.8)
expect(firstDocument.processing?.percentage == 45.8 && firstDocument.processing?.label == "45%",
       "thumbnail progress carries its document's percentage")
gallery.filterText = "photo"
expect(firstDocument.processing?.percentage == 45.8, "filtering does not reset a hidden image's progress")
gallery.filterText = ""
expect(ImageProcessingProgress.processing(120).percentage == 100 &&
       ImageProcessingProgress.processing(-5).percentage == 0, "displayed progress stays in range")
firstDocument.processing = .cancelling
expect(firstDocument.processing?.label == "Cancelling…", "cancelling has a distinct thumbnail state")
firstDocument.processing = nil

// Exercise the actual thumbnail cell without taking focus from the running app.
let progressFixture = root.appendingPathComponent("progress-source.png")
try alphaBitmap.representation(using: .png, properties: [:])!.write(to: progressFixture)
let thumbnailSession = FolderSession(directory: root, urls: [progressFixture])
let thumbnailDocument = thumbnailSession.select(progressFixture)!
thumbnailDocument.processing = .processing(37)
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
let floatingPanel = FolderSidebar(preferences: preferences)
floatingPanel.frame = NSRect(x: 12, y: 12, width: 420, height: 600)
let locateThumbnail = descendants(floatingPanel).compactMap { $0 as? NSButton }.first {
    $0.accessibilityLabel() == "Show selected file in sidebar"
}!
expect(!locateThumbnail.isEnabled && locateThumbnail.image != nil,
       "crosshair button is disabled until an image is selected")
floatingPanel.display(thumbnailSession)
expect(locateThumbnail.isEnabled, "selecting an image enables the crosshair button")
let sortingMenus = descendants(floatingPanel).compactMap { $0 as? NSPopUpButton }
let sortingMenu = sortingMenus.first!
expect(sortingMenus.count == 1 && sortingMenu.itemTitles == ImageSortKey.allCases.flatMap {
    ["↑ \($0.title)", "↓ \($0.title)"]
}, "one sorting menu contains every criterion in both directions")
sortingMenu.selectItem(at: 9)
NSApp.sendAction(sortingMenu.action!, to: sortingMenu.target, from: sortingMenu)
let panelPreferences = SidebarPreferences(defaults: testDefaults)
expect(thumbnailSession.sortKey == .fileType && thumbnailSession.descending &&
       panelPreferences.sortKey == .fileType && panelPreferences.descending,
       "combined sorting selection updates the folder and persists both fields")
let panelSurface = descendants(floatingPanel).compactMap { $0 as? NSVisualEffectView }.first!
expect(panelSurface.alphaValue < 1 && panelSurface.blendingMode == .withinWindow,
       "floating panel background blends with the image in the same window")
var collapseChanges = 0
floatingPanel.onCollapseChange = { collapseChanges += 1 }
let expandedPanelWidth = floatingPanel.preferredWidth
floatingPanel.toggleCollapsed()
expect(floatingPanel.isCollapsed && sortingMenu.isHiddenOrHasHiddenAncestor &&
       floatingPanel.collapsedWidth <= 300 && thumbnailDocument.processing == .processing(37),
       "folding hides controls in a compact folder plaque and preserves processing state")
floatingPanel.toggleCollapsed()
expect(!floatingPanel.isCollapsed && !sortingMenu.isHiddenOrHasHiddenAncestor && collapseChanges == 2 &&
       floatingPanel.preferredWidth == expandedPanelWidth && sortingMenu.indexOfSelectedItem == 9,
       "expanding restores the controls, sort choice and preferred panel width")
let panelSearch = descendants(floatingPanel).compactMap { $0 as? NSSearchField }.first!
panelSearch.stringValue = "no matching image"
floatingPanel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: panelSearch))
floatingPanel.toggleCollapsed()
floatingPanel.revealSelection()
let panelCollection = descendants(floatingPanel).compactMap { $0 as? NSCollectionView }.first!
expect(!floatingPanel.isCollapsed && panelSearch.stringValue.isEmpty && thumbnailSession.filterText.isEmpty &&
       panelCollection.selectionIndexPaths == [IndexPath(item: 0, section: 0)] &&
       thumbnailSession.selected === thumbnailDocument,
       "revealing the selected image unfolds the panel and removes a filter hiding its thumbnail")
panelSearch.stringValue = "progress"
floatingPanel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: panelSearch))
NSApp.sendAction(locateThumbnail.action!, to: locateThumbnail.target, from: locateThumbnail)
expect(panelSearch.stringValue == "progress" && thumbnailDocument.processing == .processing(37),
       "crosshair button reveals the selection without changing a matching filter or processing state")
let gridButtons = descendants(floatingPanel).compactMap { $0 as? NSButton }.filter {
    ["Regular grid", "Adaptive grid"].contains($0.accessibilityLabel() ?? "")
}
expect(gridButtons.count == 2 && gridButtons.allSatisfy { $0.image != nil && $0.bezelStyle == .circular },
       "two round icon buttons switch the grid modes")
let adaptiveButton = gridButtons.first { $0.accessibilityLabel() == "Adaptive grid" }!
let regularButton = gridButtons.first { $0.accessibilityLabel() == "Regular grid" }!
NSApp.sendAction(adaptiveButton.action!, to: adaptiveButton.target, from: adaptiveButton)
expect(floatingPanel.gridMode == .adaptive && adaptiveButton.state == .on && regularButton.state == .off &&
       panelCollection.collectionViewLayout is AdaptiveThumbnailLayout &&
       panelCollection.selectionIndexPaths == [IndexPath(item: 0, section: 0)] &&
       panelSearch.stringValue == "progress" && thumbnailDocument.processing == .processing(37) &&
       SidebarPreferences(defaults: testDefaults).gridMode == .adaptive,
       "adaptive mode preserves selection, filter and processing while saving the new preference")
NSApp.sendAction(regularButton.action!, to: regularButton.target, from: regularButton)
expect(floatingPanel.gridMode == .regular && regularButton.state == .on && adaptiveButton.state == .off &&
       panelCollection.collectionViewLayout is NSCollectionViewFlowLayout,
       "regular mode restores the original uniform layout")
let thumbnailCell = ThumbnailCard(frame: NSRect(x: 0, y: 0, width: 160, height: 170))
thumbnailCell.configure(thumbnailDocument, size: 112)
thumbnailCell.layoutSubtreeIfNeeded()
let thumbnailProgress = descendants(thumbnailCell).compactMap { $0 as? NSProgressIndicator }.first!
expect(!thumbnailProgress.isHiddenOrHasHiddenAncestor && thumbnailProgress.doubleValue == 37 &&
       !thumbnailProgress.isIndeterminate, "thumbnail displays the processing file's actual progress")
expect(thumbnailProgress.superview === thumbnailCell && thumbnailCell.layer?.cornerRadius == 10,
       "progress sits directly in the rounded card without a separate background or padding container")
thumbnailDocument.processing = .preparing
thumbnailCell.configure(thumbnailDocument, size: 112)
expect(thumbnailProgress.isIndeterminate && !thumbnailProgress.isHiddenOrHasHiddenAncestor,
       "thumbnail displays preparing before percentage progress is available")
let thumbnailResult = root.appendingPathComponent("progress-result.png")
try manager.copyItem(at: progressFixture, to: thumbnailResult)
thumbnailDocument.processing = nil
thumbnailDocument.receive(thumbnailResult, scale: 2)
thumbnailCell.configure(thumbnailDocument, size: 112)
let improvementIcon = descendants(thumbnailCell).compactMap { $0 as? NSImageView }.first {
    $0.accessibilityLabel() == "Unsaved enhancement available"
}!
expect(!improvementIcon.isHiddenOrHasHiddenAncestor && thumbnailProgress.isHiddenOrHasHiddenAncestor,
       "completed thumbnail replaces progress with the unsaved improvement icon")
try thumbnailDocument.save()
thumbnailCell.configure(thumbnailDocument, size: 112)
expect(improvementIcon.isHiddenOrHasHiddenAncestor, "saving removes the unsaved improvement icon")

expect(BrowserAction.key(6, modifiers: []) == .previous, "physical Z goes to previous")
expect(BrowserAction.key(7, modifiers: [.shift]) == .next, "physical X works with Shift")
expect(BrowserAction.key(49, modifiers: []) == .next, "Space goes to next")
expect(BrowserAction.key(53, modifiers: []) == .close, "Escape requests application exit")
expect(BrowserAction.key(116, modifiers: []) == nil && BrowserAction.key(121, modifiers: []) == nil,
       "Page Up and Page Down are separate from single-image Z/X navigation")
expect(FileNavigation.key(116, modifiers: .function) == .pageUp &&
       FileNavigation.key(121, modifiers: [.function, .shift]) == .pageDown,
       "Mac Fn+Up/Down physical page codes accept Fn and Shift flags")
expect(FileNavigation.key(115, modifiers: .function) == .first &&
       FileNavigation.key(119, modifiers: .function) == .last,
       "Mac Fn+Left/Right physical Home/End codes navigate to the ends")
expect(FileNavigation.key(126, modifiers: [.command, .numericPad]) == .first &&
       FileNavigation.key(125, modifiers: [.command, .shift]) == .last,
       "Mac Command arrows accept their native arrow-key flags and Shift")
expect(FileNavigation.key(126, modifiers: []) == nil && FileNavigation.key(125, modifiers: .shift) == nil &&
       FileNavigation.key(121, modifiers: .option) == nil && FileNavigation.key(115, modifiers: .control) == nil,
       "plain arrows and unrelated modified shortcuts remain native")
let pageFrames = (0..<12).map { index in NSRect(x: (index % 2) * 120, y: (index / 2) * 180, width: 110, height: 170) }
expect(FileNavigation.pageDown.target(from: 0, frames: pageFrames, pageHeight: 360) == 4 &&
       FileNavigation.pageUp.target(from: 4, frames: pageFrames, pageHeight: 360) == 0,
       "a page follows vertical distance and retains the current column")
expect(FileNavigation.pageUp.target(from: 0, frames: pageFrames, pageHeight: 360) == 0 &&
       FileNavigation.pageDown.target(from: 11, frames: pageFrames, pageHeight: 360) == 11 &&
       FileNavigation.first.target(from: 0, frames: [], pageHeight: 360) == nil,
       "paging clamps at both ends and handles an empty layout")
expect(BrowserAction.key(6, modifiers: [.command]) == nil &&
       BrowserAction.key(7, modifiers: [.option]) == nil &&
       BrowserAction.key(49, modifiers: [.control]) == nil,
       "navigation preserves modified shortcuts")
let cyrillic = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: 0, context: nil, characters: "ч", charactersIgnoringModifiers: "ч", isARepeat: false,
    keyCode: 7)!
expect(BrowserAction.key(cyrillic.keyCode, modifiers: cyrillic.modifierFlags) == .next,
       "Russian layout uses the same physical X key")

// Multiple pending results survive navigation. Resolve each individually, with
// partial progress retained when a later dialog is cancelled.
let thirdDocument = gallery.documents.first(where: { $0.url.lastPathComponent == "alpha.webp" })!
let documents = [firstDocument, secondDocument, thirdDocument]
for document in documents {
    let output = root.appendingPathComponent("\(UUID().uuidString).png")
    try Data("upscale".utf8).write(to: output)
    document.receive(output, scale: 2)
}
gallery.select(lastDocument.url)
expect(documents.allSatisfy { $0.hasUnsavedResult }, "pending results remain on other images")
let removed = secondDocument.resultURL!
var questions: [(Int, Int)] = []
let closing = try UnsavedResults.resolve(documents) { _, index, total in
    questions.append((index, total))
    return index == 1 ? .save : index == 2 ? .discard : .cancel
}
expect(!closing && questions.map { $0.0 } == [1, 2, 3] && questions.allSatisfy { $0.1 == 3 },
       "closing visits every pending file and can be cancelled")
expect(firstDocument.savedURL?.lastPathComponent == "2_2x.png" && !firstDocument.hasUnsavedResult,
       "close saves the correct original with the result scale")
expect(secondDocument.resultURL == nil && !manager.fileExists(atPath: removed.path),
       "discard deletes only its temporary result")
expect(try! Data(contentsOf: secondDocument.url) == Data("fixture".utf8), "discard preserves the original")
expect(thirdDocument.hasUnsavedResult && manager.fileExists(atPath: thirdDocument.resultURL!.path),
       "cancel preserves the unresolved result")
let resumed = try UnsavedResults.resolve(documents) { document, index, total in
    expect(document === thirdDocument && index == 1 && total == 1, "resuming only prompts unresolved files")
    return .save
}
expect(resumed && !documents.contains(where: { $0.hasUnsavedResult }), "all decisions resolve the close")
let failedDocument = ImageDocument(url: root.appendingPathComponent("missing-folder/source.png"))
let failedResult = root.appendingPathComponent("failed-save.png")
try Data("keep".utf8).write(to: failedResult)
failedDocument.receive(failedResult, scale: 4)
do {
    _ = try UnsavedResults.resolve([failedDocument]) { _, _, _ in .save }
    fatalError("Closing succeeded after a failed save")
} catch { assertions += 1 }
expect(failedDocument.hasUnsavedResult && manager.fileExists(atPath: failedResult.path),
       "failed saving preserves the pending result")

// Switching between differently sized images must reset the logical canvas;
// restoring a view keeps screen size even when an upscale changes pixel count.
viewer.setOriginal(alphaAsset)
expect(viewer.canvas.bounds.size == alphaAsset.pixels, "switching images resets canvas dimensions")
viewer.zoomBy(2)
viewer.divider.fraction = 0.3
let position = viewer.position()
viewer.setEnhanced(ImageAsset(image: alphaImage, pixels: NSSize(width: 400, height: 320), hasAlpha: true))
viewer.restore(position)
expect(abs(viewer.position().displayedWidth - position.displayedWidth) < 0.01,
       "restoring zoom preserves displayed size across result resolutions")
expect(abs(viewer.divider.fraction - 0.3) < 0.001, "comparison divider is retained per image")

let boundedViewer = ComparisonView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
boundedViewer.leadingObstruction = 344
boundedViewer.layoutSubtreeIfNeeded()
boundedViewer.setOriginal(asset)
boundedViewer.setEnhanced(enhanced)
let beforePanelGrowth = boundedViewer.scroll.magnification
boundedViewer.restore(PreviewPosition(displayedWidth: 0, center: NSPoint(x: 0.5, y: 0.5), fraction: 0, fitting: true))
expect(boundedViewer.scroll.frame == boundedViewer.bounds && boundedViewer.divider.dividerX >= 344,
       "image extends under the floating panel while the divider avoids it")
expect(abs(beforePanelGrowth - min(708.0 / 6688, 652.0 / 3764)) < 0.001,
       "fit uses the unobscured area to the right of the floating panel")
func displayedImage(_ viewer: ComparisonView) -> NSRect {
    viewer.canvas.convert(viewer.canvas.bounds, to: viewer)
}
func centeredInVisibleArea(_ viewer: ComparisonView) -> Bool {
    let image = displayedImage(viewer)
    return abs(image.midX - viewer.viewport.midX) < 0.1 && abs(image.midY - viewer.viewport.midY) < 0.1
}
expect(centeredInVisibleArea(boundedViewer), "fitted image is centered in the area right of the panel")
boundedViewer.leadingObstruction = 544
boundedViewer.layoutSubtreeIfNeeded()
expect(boundedViewer.divider.dividerX >= 544 && boundedViewer.scroll.magnification < beforePanelGrowth &&
       centeredInVisibleArea(boundedViewer),
       "resizing the overlay refits and recenters the image in the remaining area")
let expandedFit = boundedViewer.scroll.magnification
boundedViewer.leadingObstruction = 0
boundedViewer.layoutSubtreeIfNeeded()
expect(boundedViewer.scroll.frame == boundedViewer.bounds && boundedViewer.scroll.magnification > expandedFit &&
       centeredInVisibleArea(boundedViewer), "folding the panel fits and centers using the whole window")
boundedViewer.leadingObstruction = 544
for size in [NSSize(width: 1800, height: 600), NSSize(width: 600, height: 1800),
             NSSize(width: 120, height: 90)] {
    boundedViewer.setOriginal(ImageAsset(image: alphaImage, pixels: size, hasAlpha: true))
    let initialFit = min((boundedViewer.viewport.width - 48) / size.width,
                         (boundedViewer.viewport.height - 48) / size.height)
    expect(abs(boundedViewer.scroll.magnification - min(1, initialFit)) < 0.001 &&
           centeredInVisibleArea(boundedViewer),
           "initial zoom shrinks oversized images and centers small images at 100 percent: \(size)")
    boundedViewer.fit()
    let rect = displayedImage(boundedViewer)
    expect(centeredInVisibleArea(boundedViewer) && rect.minX >= boundedViewer.viewport.minX + 23.9 &&
           rect.maxX <= boundedViewer.viewport.maxX - 23.9 && rect.height <= boundedViewer.viewport.height - 47.9,
           "wide, portrait and small images fit entirely in the unobscured area: \(size)")
    expect(abs(boundedViewer.scroll.magnification - min((boundedViewer.viewport.width - 48) / size.width,
                                                      (boundedViewer.viewport.height - 48) / size.height)) < 0.001,
           "fit fills the available space even when it requires enlarging a small image")
    boundedViewer.actualSize()
    boundedViewer.zoomBy(0.1)
    expect(centeredInVisibleArea(boundedViewer), "small manual zoom centers to the right of the panel")
}
boundedViewer.setOriginal(asset)
boundedViewer.setEnhanced(enhanced)
boundedViewer.actualSize()
let manualPosition = boundedViewer.position()
boundedViewer.leadingObstruction = 0
expect(abs(boundedViewer.position().center.x - manualPosition.center.x) < 0.001 &&
       boundedViewer.position().displayedWidth == manualPosition.displayedWidth,
       "folding in manual zoom preserves the viewed image point and magnification")
boundedViewer.leadingObstruction = 544
let doubleClick = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
boundedViewer.canvas.mouseDown(with: doubleClick)
expect(boundedViewer.fitting && centeredInVisibleArea(boundedViewer) &&
       boundedViewer.scroll.magnification < 1,
       "double click from manual zoom fits the image in the visible area")
boundedViewer.divider.mouseDown(with: doubleClick)
expect(!boundedViewer.fitting && boundedViewer.scroll.magnification == 1,
       "double click on the fitted image or divider changes to actual size")
boundedViewer.leadingObstruction = 0
boundedViewer.canvas.mouseDown(with: doubleClick)
expect(boundedViewer.fitting && centeredInVisibleArea(boundedViewer) && boundedViewer.viewport == boundedViewer.bounds,
       "double click with a collapsed panel fits and centers using the whole window")
boundedViewer.canvas.mouseDown(with: doubleClick)
expect(!boundedViewer.fitting && boundedViewer.scroll.magnification == 1,
       "repeated double click returns from fit to 100 percent")
boundedViewer.leadingObstruction = 544

// Continuous clicking produces clickCount 1, 2, 3, 4... rather than starting
// every pair at 1. After shrinking, the same screen point may hit the clip view.
boundedViewer.setOriginal(alphaAsset)
expect(boundedViewer.scroll.magnification == 1 && !boundedViewer.fitting && centeredInVisibleArea(boundedViewer),
       "a small image starts at actual size centered in the visible area")
boundedViewer.canvas.mouseDown(with: doubleClick)
let enlargedFit = boundedViewer.scroll.magnification
expect(enlargedFit > 1 && boundedViewer.fitting && centeredInVisibleArea(boundedViewer),
       "double clicking a newly opened small image explicitly fits it with enlargement")
for target: NSView in [boundedViewer.canvas, boundedViewer.scroll.contentView, boundedViewer.divider] {
    boundedViewer.fit()
    for count in 1...12 {
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: Double(count) * 0.1, windowNumber: 0, context: nil, eventNumber: count,
            clickCount: count, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
            timestamp: Double(count) * 0.1 + 0.01, windowNumber: 0, context: nil, eventNumber: count,
            clickCount: count, pressure: 0)!
        target.mouseDown(with: down)
        target.mouseUp(with: up)
        if count % 2 == 0 {
            let shouldFit = count % 4 == 0
            expect(boundedViewer.fitting == shouldFit &&
                   abs(boundedViewer.scroll.magnification - (shouldFit ? enlargedFit : 1)) < 0.001,
                   "each fast click pair toggles fit/100% on image, empty viewport or divider: \(count)")
        }
    }
}
boundedViewer.actualSize()
let outsideImage = NSPoint(x: boundedViewer.viewport.minX + 10, y: boundedViewer.viewport.midY)
let emptyTarget = boundedViewer.hitTest(outsideImage)
expect(emptyTarget === boundedViewer.scroll.contentView, "shrinking the image leaves the clip view under the pointer")
emptyTarget?.mouseDown(with: doubleClick)
expect(boundedViewer.fitting && abs(boundedViewer.scroll.magnification - enlargedFit) < 0.001,
       "double clicking exposed background enlarges the small image back to fit")
boundedViewer.setOriginal(ImageAsset(image: alphaImage, pixels: NSSize(width: 8, height: 6), hasAlpha: true))
expect(boundedViewer.scroll.magnification == 1 && !boundedViewer.fitting,
       "even a tiny icon starts at 100 percent")
boundedViewer.canvas.mouseDown(with: doubleClick)
expect(boundedViewer.scroll.magnification > 32 && centeredInVisibleArea(boundedViewer) &&
       abs(displayedImage(boundedViewer).width - (boundedViewer.viewport.width - 48)) < 0.1,
       "even a tiny icon can fill the available space beyond the normal zoom ceiling")
boundedViewer.setOriginal(asset)
boundedViewer.setEnhanced(enhanced)

// Regression for the reported cursor-region exception: a hand drag must stop
// at the document edges, and an invisible document must never register infinity.
boundedViewer.actualSize()
for zoom in [CGFloat(1), 2, 0.25] {
    boundedViewer.scroll.setMagnification(zoom, centeredAt: .zero)
    for origin in [NSPoint(x: -1_000_000, y: 0), NSPoint(x: 1_000_000, y: 0),
                   NSPoint(x: 0, y: -1_000_000), NSPoint(x: 0, y: 1_000_000)] {
        boundedViewer.canvas.pan(to: origin)
        let clip = boundedViewer.scroll.contentView
        let allowed = clip.constrainBoundsRect(clip.bounds)
        expect(abs(clip.bounds.minX - allowed.minX) < 0.01 && abs(clip.bounds.minY - allowed.minY) < 0.01 &&
               boundedViewer.divider.hasVisibleImage && boundedViewer.divider.dividerX.isFinite,
               "large pan remains bounded and keeps a finite divider at zoom \(zoom)")
        expect(boundedViewer.divider.dividerX >= boundedViewer.comparisonViewport.minX &&
               boundedViewer.divider.dividerX <= boundedViewer.comparisonViewport.maxX,
               "panning cannot push the divider behind the panel or beyond the window")
    }
}
boundedViewer.scroll.contentView.setBoundsOrigin(NSPoint(x: 1_000_000, y: 1_000_000))
boundedViewer.scroll.onZoom?()
expect(boundedViewer.divider.dividerX.isFinite && boundedViewer.canvas.dividerInDocument.isFinite &&
       (boundedViewer.divider.hasVisibleImage || boundedViewer.divider.imageRect == .zero),
       "offscreen geometry either stays constrained or clears the divider without infinite coordinates")
boundedViewer.divider.resetCursorRects()
let emptyDivider = DividerOverlay(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
emptyDivider.imageRect = .null
emptyDivider.resetCursorRects()
expect(emptyDivider.hitTest(NSPoint(x: 10, y: 10)) == nil && emptyDivider.dividerX.isFinite,
       "null divider rectangles do not register cursor regions or accept dragging")

// Exercise the native subprocess bridge, JSON ordering, and cancellation.
if manager.isExecutableFile(atPath: AppPaths.python.path),
   manager.fileExists(atPath: AppPaths.data.appendingPathComponent("models/x2plus").path) {
    let context = CGContext(data: nil, width: 45, height: 37, bitsPerComponent: 8,
        bytesPerRow: 45 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.5).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 45, height: 37))
    let fixture = root.appendingPathComponent("bridge-source.png")
    let writer = CGImageDestinationCreateWithURL(fixture as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, context.makeImage()!, nil)
    expect(CGImageDestinationFinalize(writer), "worker fixture created")
    let bridgeSession = try TemporarySession()
    for scale in [1, 2] {
        let result = bridgeSession.nextResult()
        let worker = WorkerTask(session: bridgeSession)
        var events: [String] = []
        var exited = false
        worker.onEvent = { event in events.append(event["event"] as? String ?? "unknown") }
        worker.onExit = { code, cancelled, message in
            expect(code == 0 && !cancelled, "native bridge succeeds: \(message)")
            exited = true
        }
        try worker.start(input: fixture, output: result, scale: scale, model: "photo")
        let deadline = Date().addingTimeInterval(30)
        while !exited && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        expect(exited, "native bridge exits")
        expect(events.first == "started" && events.last == "completed", "JSON events precede process exit")
        expect(events.contains("progress"), "tile progress delivered")
        let decoded = try ImageAsset.load(result)
        expect(decoded.pixels == NSSize(width: 45 * scale, height: 37 * scale) && decoded.hasAlpha,
               "native bridge preserves alpha and requested dimensions at scale \(scale)")
    }

    let cancelledWorker = WorkerTask(session: bridgeSession)
    var cancellationFinished = false
    cancelledWorker.onEvent = { event in
        if event["event"] as? String == "started" { cancelledWorker.cancel() }
    }
    cancelledWorker.onExit = { _, cancelled, _ in
        expect(cancelled, "native cancellation is reported")
        cancellationFinished = true
    }
    try cancelledWorker.start(input: fixture, output: bridgeSession.nextResult(), scale: 2, model: "photo")
    let cancellationDeadline = Date().addingTimeInterval(15)
    while !cancellationFinished && Date() < cancellationDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    expect(cancellationFinished, "cancelled process exits without an orphan")
    expect(WorkerTask.activeTasks.isEmpty, "no active worker remains")
} else {
    print("Native GPU bridge checks skipped: install the local runtime and x2plus model to run them")
}

// The portable installer must work without Python and must reject damaged payloads.
let engineFixture = root.appendingPathComponent("engine fixture with spaces")
let engineResources = root.appendingPathComponent("relocated resources")
let engineData = root.appendingPathComponent("isolated engine data")
try manager.createDirectory(at: engineFixture.appendingPathComponent("runtime/bin"), withIntermediateDirectories: true)
try manager.createDirectory(at: engineResources, withIntermediateDirectories: true)
let fakePython = engineFixture.appendingPathComponent("runtime/bin/python3")
try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fakePython)
try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakePython.path)
let engineArchive = engineResources.appendingPathComponent("runtime.tar")
let tar = Process()
tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
tar.arguments = ["-cf", engineArchive.path, "-C", engineFixture.path, "runtime"]
try tar.run()
tar.waitUntilExit()
expect(tar.terminationStatus == 0, "portable fixture archive created")
let engineDigest = try PortableRuntimeInstaller.sha256(engineArchive)
let engineManifest = PortableRuntimeManifest(archive: "runtime.tar", sha256: engineDigest, version: "test")
expect(engineManifest.isValid, "portable manifest accepts a pinned payload")
expect(!PortableRuntimeManifest(archive: "../runtime.tar", sha256: engineDigest, version: "test").isValid,
       "portable manifest rejects archive traversal")
expect(!PortableRuntimeManifest(archive: "runtime.tar", sha256: "../invalid", version: "test").isValid,
       "portable manifest rejects invalid runtime identifiers")
let engineInstaller = PortableRuntimeInstaller(resources: engineResources, data: engineData, manifest: engineManifest)
expect(!engineInstaller.isInstalled, "portable engine starts uninstalled")
try engineInstaller.install()
expect(engineInstaller.isInstalled && manager.isExecutableFile(atPath: engineInstaller.python.path),
       "portable engine installs into isolated Application Support layout")
expect(engineInstaller.python.path.hasPrefix(engineData.path), "portable engine does not use source or bundle paths")
let engineTime = try engineInstaller.python.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
try engineInstaller.install()
let engineTimeAgain = try engineInstaller.python.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
expect(engineTimeAgain == engineTime,
       "repeat bootstrap reuses the installed engine")
let badEngine = PortableRuntimeInstaller(resources: engineResources, data: engineData,
    manifest: PortableRuntimeManifest(archive: "runtime.tar", sha256: String(repeating: "0", count: 64), version: "test"))
do {
    try badEngine.install()
    expect(false, "damaged payload must fail")
} catch {
    expect(!manager.fileExists(atPath: badEngine.directory.path), "checksum failure never publishes an engine")
}

print("Native tests: \(assertions) assertions passed")
