import AppKit
import SwiftUI

/// Manages the main lattice window as a standalone NSWindow.
/// Menu bar icon toggles this window open/closed.
final class MainWindow {
    static let shared = MainWindow()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
            AppDelegate.updateActivationPolicy()
        } else {
            show()
        }
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = MainView(scanner: ProjectScanner.shared)
            .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 460)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "lattice"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        w.appearance = NSAppearance(named: .darkAqua)
        w.minSize = NSSize(width: 340, height: 380)
        w.maxSize = NSSize(width: 600, height: 800)

        // Position near top-right of screen (close to menu bar area)
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.maxX - 380 - 20
            let y = visibleFrame.maxY - 460 - 10
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = w
        AppDelegate.updateActivationPolicy()
    }

    func close() {
        window?.orderOut(nil)
        AppDelegate.updateActivationPolicy()
    }
}
