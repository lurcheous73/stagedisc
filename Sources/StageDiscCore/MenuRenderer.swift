import AppKit

public enum MenuRenderer {
    public static func image(project: Project, page: MenuPage, selection: Int) -> NSImage {
        let size = NSSize(width: 1920, height: 1080)
        let image = NSImage(size: size)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1920, pixelsHigh: 1080, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let bounds = NSRect(origin: .zero, size: size)
        NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.055, alpha: 1).setFill(); bounds.fill()
        if let path = project.menu.backgroundPath, let background = NSImage(contentsOfFile: path) {
            let factor = max(size.width / background.size.width, size.height / background.size.height)
            let scaled = NSSize(width: background.size.width * factor, height: background.size.height * factor)
            background.draw(in: NSRect(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2, width: scaled.width, height: scaled.height))
            NSColor.black.withAlphaComponent(0.72).setFill(); bounds.fill()
        } else {
            let gradient = NSGradient(starting: NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.12, alpha: 1), ending: .black)
            gradient?.draw(in: bounds, angle: -25)
            for i in 0..<6 {
                let beam = NSBezierPath(); beam.move(to: NSPoint(x: 1350 + i * 65, y: 1080))
                beam.line(to: NSPoint(x: 140 + i * 260, y: 0)); beam.line(to: NSPoint(x: 430 + i * 260, y: 0)); beam.close()
                NSColor.white.withAlphaComponent(0.018).setFill(); beam.fill()
            }
        }
        let hex = UInt32(project.menu.accent, radix: 16) ?? 0xD5AE62
        let accent = NSColor(calibratedRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        func text(_ value: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) {
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
        }
        text(project.menu.band.uppercased(), rect: NSRect(x: 115, y: 890, width: 800, height: 60), size: 28, weight: .medium, color: accent)
        let titleStyle = NSMutableParagraphStyle(); titleStyle.lineBreakMode = .byWordWrapping
        (project.menu.heading as NSString).draw(in: NSRect(x: 110, y: 500, width: 825, height: 370), withAttributes: [.font: NSFont.systemFont(ofSize: 88, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: titleStyle])
        accent.setFill(); NSRect(x: 115, y: 480, width: 90, height: 4).fill()
        text(project.menu.tagline, rect: NSRect(x: 115, y: 360, width: 800, height: 90), size: 30, color: NSColor.white.withAlphaComponent(0.65))
        text(page.name.uppercased(), rect: NSRect(x: 1080, y: 884, width: 720, height: 50), size: 22, weight: .medium, color: accent)
        for (i, button) in page.buttons.enumerated() {
            let rect = NSRect(x: 1065, y: 766 - i * 78, width: 735, height: 65)
            let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            (i == selection ? accent : NSColor.white.withAlphaComponent(0.055)).setFill(); path.fill()
            text(button.label, rect: NSRect(x: rect.minX + 24, y: rect.minY + 13, width: rect.width - 48, height: 43), size: 28, weight: i == selection ? .semibold : .regular,
                 color: i == selection ? NSColor(calibratedWhite: 0.07, alpha: 1) : .white)
        }
        text("LIVE  /  FILM  /  MUSIC", rect: NSRect(x: 115, y: 103, width: 900, height: 45), size: 18, color: NSColor.white.withAlphaComponent(0.38))
        text("↑ ↓  SELECT     ENTER  PLAY     BACK  MENU", rect: NSRect(x: 1065, y: 103, width: 780, height: 45), size: 17, color: NSColor.white.withAlphaComponent(0.38))
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(bitmap)
        return image
    }
    public static func write(project: Project, pages: [MenuPage], to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for page in pages {
            for selection in page.buttons.indices {
                if Task.isCancelled { throw CancellationError() }
                let image = image(project: project, page: page, selection: selection)
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw StageError.message("Could not render menu graphics.") }
                try png.write(to: folder.appendingPathComponent("page\(page.id)-\(selection).png"))
            }
        }
        try MenuPlan.properties(pages, project: project).write(to: folder.appendingPathComponent("menu.properties"), atomically: true, encoding: .utf8)
    }
    public static func albumArtwork(project: Project, title: DiscTitle, to url: URL) throws {
        let art = image(project: project, page: MenuPage(id: 0, name: title.name, buttons: []), selection: -1)
        guard let tiff = art.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw StageError.message("Could not render album artwork.") }
        try png.write(to: url)
    }
}
