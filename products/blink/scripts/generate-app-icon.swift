#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets", isDirectory: true)
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Blink.AppIcon.\(UUID().uuidString).iconset", isDirectory: true)

try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

let amber = NSColor(
    srgbRed: 240.0 / 255.0,
    green: 180.0 / 255.0,
    blue: 90.0 / 255.0,
    alpha: 1
)
let background = NSColor(
    srgbRed: 10.0 / 255.0,
    green: 10.0 / 255.0,
    blue: 11.0 / 255.0,
    alpha: 1
)

func png(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.shouldAntialias = true

    let s = CGFloat(size)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    let tile = NSBezierPath(
        roundedRect: NSRect(x: s * 0.0625, y: s * 0.0625, width: s * 0.875, height: s * 0.875),
        xRadius: s * 0.215,
        yRadius: s * 0.215
    )
    background.setFill()
    tile.fill()

    NSColor(white: 1, alpha: 0.08).setStroke()
    tile.lineWidth = max(0.5, s * 0.002)
    tile.stroke()

    let markFrame = NSRect(x: s * 0.27, y: s * 0.27, width: s * 0.46, height: s * 0.46)
    let mark = NSBezierPath(
        roundedRect: markFrame,
        xRadius: s * 0.086,
        yRadius: s * 0.086
    )
    amber.setStroke()
    mark.lineWidth = max(1, s * 0.012)
    mark.stroke()

    let block = s * 0.082
    amber.setFill()
    NSRect(x: s * 0.41, y: s * 0.50, width: block, height: block).fill()
    NSRect(x: s * 0.492, y: s * 0.418, width: block, height: block).fill()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

let files: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in files {
    try png(size: size).write(to: iconset.appendingPathComponent(name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", assets.appendingPathComponent("AppIcon.icns").path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

print("Generated \(assets.appendingPathComponent("AppIcon.icns").path)")
