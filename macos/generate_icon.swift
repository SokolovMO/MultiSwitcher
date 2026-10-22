#!/usr/bin/env swift
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

let projectDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let sourceURL = projectDirectory.appendingPathComponent("icons/app-icon.svg")
guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Cannot load app icon SVG: \(sourceURL.path)")
}

// iconutil needs a temporary iconset; the source SVG and final ICNS are the
// only icon artifacts kept in the repository.
let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("MultiSwitcher-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetDirectory = temporaryDirectory.appendingPathComponent("MultiSwitcher.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

let iconsetSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in iconsetSizes {
    try renderPNG(image: sourceImage, size: size).write(to: iconsetDirectory.appendingPathComponent(name))
}

let iconURL = projectDirectory.appendingPathComponent("MultiSwitcher.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDirectory.path, "-o", iconURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(iconutil.terminationStatus)")
}
print("Generated app icon assets from \(sourceURL.path)")

// Keep reviewable PNG previews alongside the alternate SVG marks.
let previewDirectory = projectDirectory.appendingPathComponent("icons/previews", isDirectory: true)
try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
for name in ["app-icon-az", "app-icon-disabled"] {
    let variantURL = projectDirectory.appendingPathComponent("icons/\(name).svg")
    guard let variantImage = NSImage(contentsOf: variantURL) else {
        fatalError("Cannot load icon variant: \(variantURL.path)")
    }
    try renderPNG(image: variantImage, size: 512)
        .write(to: previewDirectory.appendingPathComponent("\(name).png"))
}
