import AppKit

let name = CommandLine.arguments[1].lowercased()
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let size = NSSize(width: 700, height: 412)
let image = NSImage(size: size)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 700 * scale,
        pixelsHigh: 412 * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(red: 0.96, green: 0.97, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    let ink = NSColor(red: 0.10, green: 0.14, blue: 0.12, alpha: 1)
    func text(_ value: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor = ink) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }
    text("установите \(name)", x: 44, y: 328, font: .systemFont(ofSize: 30, weight: .semibold))
    text("перетащите приложение в «Программы»", x: 44, y: 290, font: .systemFont(ofSize: 18))
    let arrow = NSBezierPath()
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 325, y: 207)); arrow.line(to: NSPoint(x: 375, y: 207))
    arrow.move(to: NSPoint(x: 362, y: 220)); arrow.line(to: NSPoint(x: 375, y: 207)); arrow.line(to: NSPoint(x: 362, y: 194))
    ink.withAlphaComponent(0.65).setStroke(); arrow.stroke()
    text("после копирования откройте приложение из «Программ»", x: 44, y: 35,
         font: .systemFont(ofSize: 15), color: ink.withAlphaComponent(0.8))
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation!.write(to: destination)
