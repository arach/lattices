import ActionCore
import AppKit

extension ActionBrandMark {
    /// The status item image.
    ///
    /// At rest it is a template, so the menu bar tints it for the current
    /// appearance and inverts it on highlight — the behaviour every other extra
    /// has. While a drive holds the machine it is drawn in coral instead, which
    /// is the same thing coral means everywhere else in the app: something is
    /// live. A template image cannot carry colour, so the live variant gives up
    /// template tinting; that is fine, because a coral mark is legible against
    /// both a light and a dark menu bar.
    @MainActor
    static func statusItemImage(live: Bool) -> NSImage {
        // 16pt of glyph inside an 18pt image. Menu bar extras are expected to
        // sit a little inside their slot; filling it edge to edge reads as
        // shouting next to the system's own items.
        let side: CGFloat = 18
        let padding: CGFloat = 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(markPath(in: rect.insetBy(dx: padding, dy: padding)))
            context.setFillColor(live ? coral : .black)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = !live
        return image
    }
}
