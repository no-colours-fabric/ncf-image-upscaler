import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let pixels = size * density
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        let scale = CGFloat(pixels) / 1024
        context.scaleBy(x: scale, y: scale)
        let frame = NSRect(x: 92, y: 92, width: 840, height: 840)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 190, yRadius: 190)
        let gradient = NSGradient(starting: NSColor(red: 0.25, green: 0.40, blue: 0.97, alpha: 1),
                                  ending: NSColor(red: 0.43, green: 0.20, blue: 0.82, alpha: 1))!
        gradient.draw(in: shape, angle: 75)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let photo = NSBezierPath(roundedRect: NSRect(x: 230, y: 265, width: 565, height: 480),
                                 xRadius: 52, yRadius: 52)
        photo.lineWidth = 32
        photo.stroke()
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: 325, y: 565, width: 88, height: 88)).fill()
        let mountains = NSBezierPath()
        mountains.move(to: NSPoint(x: 250, y: 305))
        mountains.line(to: NSPoint(x: 430, y: 495))
        mountains.line(to: NSPoint(x: 555, y: 360))
        mountains.line(to: NSPoint(x: 660, y: 460))
        mountains.line(to: NSPoint(x: 775, y: 320))
        mountains.lineWidth = 30
        mountains.lineJoinStyle = .round
        mountains.stroke()
        let spark = NSBezierPath()
        spark.move(to: NSPoint(x: 780, y: 835))
        spark.line(to: NSPoint(x: 800, y: 784))
        spark.line(to: NSPoint(x: 850, y: 765))
        spark.line(to: NSPoint(x: 800, y: 745))
        spark.line(to: NSPoint(x: 780, y: 695))
        spark.line(to: NSPoint(x: 760, y: 745))
        spark.line(to: NSPoint(x: 710, y: 765))
        spark.line(to: NSPoint(x: 760, y: 784))
        spark.close()
        spark.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = density == 2 ? "@2x" : ""
        let filename = "icon_\(size)x\(size)\(suffix).png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
    }
}

