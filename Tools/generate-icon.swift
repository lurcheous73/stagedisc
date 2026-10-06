import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let catalog = root.appendingPathComponent("AppIcon.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let background = NSBezierPath(roundedRect: NSRect(x: 26, y: 26, width: 972, height: 972), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.22, alpha: 1), ending: NSColor(calibratedWhite: 0.02, alpha: 1))!.draw(in: background, angle: -70)
        let disc = NSBezierPath(ovalIn: NSRect(x: 132, y: 132, width: 760, height: 760))
        NSGradient(starting: NSColor(calibratedRed: 0.96, green: 0.84, blue: 0.59, alpha: 1), ending: NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.13, alpha: 1))!.draw(in: disc, angle: 35)
        let inner = NSBezierPath(ovalIn: NSRect(x: 152, y: 152, width: 720, height: 720))
        NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.15, alpha: 1).setFill(); inner.fill()
        for inset in stride(from: 180, through: 350, by: 28) {
            let ring = NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: 1024-inset*2, height: 1024-inset*2))
            NSColor(calibratedRed: 0.83, green: 0.68, blue: 0.38, alpha: 0.24).setStroke(); ring.lineWidth = 3; ring.stroke()
        }
        let play = NSBezierPath(); play.move(to: NSPoint(x: 440, y: 358)); play.line(to: NSPoint(x: 660, y: 512)); play.line(to: NSPoint(x: 440, y: 666)); play.close()
        NSColor(calibratedRed: 0.94, green: 0.80, blue: 0.53, alpha: 1).setFill(); play.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        bitmap.size = NSSize(width: pixels, height: pixels)
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name)); try png.write(to: catalog.appendingPathComponent(name))
        entries.append(["idiom":"mac", "size":"\(size)x\(size)", "scale":"\(scale)x", "filename":name])
    }
}
try JSONSerialization.data(withJSONObject: ["images": entries, "info":["author":"xcode", "version":1]], options:.prettyPrinted).write(to: catalog.appendingPathComponent("Contents.json"))
