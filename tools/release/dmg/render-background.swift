import AppKit

// Finder uses a 680 x 440 point canvas. Render at 2x for Retina displays.
let width = 680
let height = 440
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2,
    pixelsHigh: height * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)
NSColor(calibratedRed: 0.97, green: 0.966, blue: 0.95, alpha: 1).setFill()
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
          _ weight: NSFont.Weight = .regular, _ color: NSColor = .black) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let line = NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color])
    context.saveGState()
    context.translateBy(x: x, y: y + font.ascender)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    context.textMatrix = .identity
    CTLineDraw(CTLineCreateWithAttributedString(line), context)
    context.restoreGState()
}
let muted = NSColor(calibratedWhite: 0.36, alpha: 1)
text("Lattices", 44, 32, 32, .semibold)
text("Make room for your work.", 45, 77, 15, .regular, muted)

// A small version of the app's L-shaped nine-cell mark.
for row in 0..<3 {
    for col in 0..<3 {
        let active = col == 0 || row == 2
        NSColor(calibratedWhite: active ? 0.16 : 0.84, alpha: 1).setFill()
        let rect = CGRect(x: 584 + col * 17, y: 38 + row * 17, width: 13, height: 13)
        context.fill(rect)
    }
}

text("Drag Lattices into Applications", 179, 134, 18, .medium)
// These are background guides; the actual app and folder remain Finder icons.
context.setStrokeColor(NSColor(calibratedWhite: 0.68, alpha: 1).cgColor)
context.setLineWidth(1.5)
context.setLineCap(.round)
context.move(to: CGPoint(x: 305, y: 235))
context.addLine(to: CGPoint(x: 375, y: 235))
context.move(to: CGPoint(x: 367, y: 227))
context.addLine(to: CGPoint(x: 375, y: 235))
context.addLine(to: CGPoint(x: 367, y: 243))
context.strokePath()

context.setStrokeColor(NSColor(calibratedWhite: 0.83, alpha: 1).cgColor)
context.setLineWidth(0.5)
context.move(to: CGPoint(x: 44, y: 345))
context.addLine(to: CGPoint(x: 636, y: 345))
context.strokePath()
text("Then open Lattices from Applications.", 44, 369, 14, .medium)
text("You can eject this disk when the copy finishes.", 44, 393, 12, .regular, muted)
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments[1]
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
