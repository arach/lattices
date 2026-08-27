// Renders Action's app icon from the shared mark geometry.
//
// Compiled together with CoreSources/ActionBrandMark.swift by build-app-icon.sh,
// so the icon on disk and the mark the app draws at runtime come from one set of
// numbers. Edit the geometry there, re-run the script, commit the result.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func renderIcon(px: Int) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let canvas = CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
    let body = ActionBrandMark.iconBodyRect(inCanvas: canvas)
    let tile = ActionBrandMark.tilePath(in: body)

    // Warm paper, with a shallow ramp toward the landing system's paper-shadow
    // at the foot so the tile has some depth without reading as gloss. Drawn as
    // a translucent wash over flat paper rather than as a paper -> paperShadow
    // gradient, which at full strength turns the bottom half dingy.
    //
    // In CoreGraphics y points up, so the wash starts clear at the top.
    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.setFillColor(ActionBrandMark.paper)
    context.fill(body)
    if let wash = CGGradient(
        colorsSpace: space,
        colors: [
            ActionBrandMark.paperShadow.copy(alpha: 0) ?? ActionBrandMark.paperShadow,
            ActionBrandMark.paperShadow.copy(alpha: 0.45) ?? ActionBrandMark.paperShadow,
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            wash,
            start: CGPoint(x: 0, y: body.maxY),
            end: CGPoint(x: 0, y: body.minY),
            options: []
        )
    }
    context.restoreGState()

    let markSide = body.width * CGFloat(ActionBrandMark.iconMarkScale)
    let offsetY = body.height * CGFloat(ActionBrandMark.iconMarkOffsetY) / 100
    let markRect = CGRect(
        x: body.midX - markSide / 2,
        // y is up here and the nudge is expressed in design space (y down),
        // so lifting the mark means subtracting.
        y: body.midY - markSide / 2 - offsetY,
        width: markSide,
        height: markSide
    )
    // Marks and triangle are filled separately: the play triangle carries
    // coral, which is the one thing the landing system spends colour on — the
    // take. The marks are the frame around it, so they stay graphite.
    context.addPath(ActionBrandMark.marksPath(in: markRect))
    context.setFillColor(ActionBrandMark.graphite)
    context.fillPath()
    context.addPath(ActionBrandMark.playPath(in: markRect))
    context.setFillColor(ActionBrandMark.coral)
    context.fillPath()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "render-app-icon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "could not create a PNG destination at \(url.path)"
        ])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "render-app-icon", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "could not write \(url.path)"
        ])
    }
}

// iconutil wants exactly these names.
let iconsetSizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

@main
enum RenderAppIcon {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: render-app-icon <iconset-dir> [extra-png-dir]\n".utf8))
            exit(2)
        }

        let iconsetDir = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

        var cache: [Int: CGImage] = [:]
        for entry in iconsetSizes {
            let image: CGImage
            if let cached = cache[entry.px] {
                image = cached
            } else {
                guard let rendered = renderIcon(px: entry.px) else {
                    FileHandle.standardError.write(Data("could not render \(entry.px)px\n".utf8))
                    exit(1)
                }
                cache[entry.px] = rendered
                image = rendered
            }
            try write(image, to: iconsetDir.appendingPathComponent("\(entry.name).png"))
        }

        // A flat 1024 PNG for anything that wants the icon outside a bundle: docs, the
        // README, the design studio.
        if CommandLine.arguments.count >= 3 {
            let extraDir = URL(fileURLWithPath: CommandLine.arguments[2])
            try FileManager.default.createDirectory(at: extraDir, withIntermediateDirectories: true)
            if let image = cache[1024] {
                try write(image, to: extraDir.appendingPathComponent("action-icon-1024.png"))
            }
            if let image = cache[512] {
                try write(image, to: extraDir.appendingPathComponent("action-icon-512.png"))
            }
        }

        print("rendered \(iconsetSizes.count) icon sizes into \(iconsetDir.path)")
    }
}
