import AppKit
import Foundation

func renderPNG(image: NSImage, size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    image.draw(
        in: CGRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: nil
    )
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

@main enum GenerateAppIcon {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("pass the macos project directory") }
        let projectDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceImage = MultiBrandIcon.switcher
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("MultiSwitcher-icon-" + UUID().uuidString)
        let iconset = temporary.appendingPathComponent("MultiSwitcher.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let catalog = projectDirectory.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        var entries: [[String: String]] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                let data = renderPNG(image: sourceImage, size: points * scale)
                try data.write(to: iconset.appendingPathComponent(name))
                try data.write(to: catalog.appendingPathComponent(name))
                entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
            }
        }
        let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: catalog.appendingPathComponent("Contents.json"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", projectDirectory.appendingPathComponent("MultiSwitcher.icns").path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
        // Legacy resource remains byte-identical; theme can never change the application's identity.
        try Data(contentsOf: projectDirectory.appendingPathComponent("MultiSwitcher.icns"))
            .write(to: projectDirectory.appendingPathComponent("MultiSwitcher-dark.icns"))
        try renderPNG(image: sourceImage, size: 1024).write(to: projectDirectory.appendingPathComponent("icons/app-icon-master.png"))
        print("permanent AЯ: ICNS and 10 AppIcon representations generated from MultiDesignKit")
    }
}
