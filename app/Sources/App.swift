import SwiftUI

@main
struct LatticesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var scanner = ProjectScanner.shared

    /// 3×3 grid icon for the menu bar — L-shape bright, rest dim (template for auto light/dark)
    private static let menuBarIcon: NSImage = {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let pad: CGFloat = 2
            let gap: CGFloat = 1.5
            let cellSize = (size - 2 * pad - 2 * gap) / 3

            // L-shape: left column + bottom row are solid, rest are dim
            let solidCells: Set<Int> = [0, 3, 6, 7, 8]  // (0,0),(1,0),(2,0),(2,1),(2,2)

            for row in 0..<3 {
                for col in 0..<3 {
                    let idx = row * 3 + col
                    let x = pad + CGFloat(col) * (cellSize + gap)
                    let y = pad + CGFloat(row) * (cellSize + gap)
                    let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

                    if solidCells.contains(idx) {
                        NSColor.black.setFill()
                    } else {
                        NSColor.black.withAlphaComponent(0.25).setFill()
                    }
                    let path = NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8)
                    path.fill()
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
