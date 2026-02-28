import SwiftUI

@main
struct LatticeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var scanner = ProjectScanner.shared

    /// 4×4 dot grid icon for the menu bar (template for auto light/dark)
    private static let menuBarIcon: NSImage = {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let dotRadius: CGFloat = 1.3
            let cols = 4, rows = 4
            let padX: CGFloat = 2.5, padY: CGFloat = 2.5
            let spacingX = (size - 2 * padX) / CGFloat(cols - 1)
            let spacingY = (size - 2 * padY) / CGFloat(rows - 1)

            NSColor.black.setFill()
            for row in 0..<rows {
                for col in 0..<cols {
                    let cx = padX + CGFloat(col) * spacingX
                    let cy = padY + CGFloat(row) * spacingY
                    let dot = NSBezierPath(ovalIn: NSRect(
                        x: cx - dotRadius, y: cy - dotRadius,
                        width: dotRadius * 2, height: dotRadius * 2
                    ))
                    dot.fill()
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }()

    var body: some Scene {
        MenuBarExtra {
            MainView(scanner: scanner)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
