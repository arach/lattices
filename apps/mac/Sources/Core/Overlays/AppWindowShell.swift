import AppKit
import SwiftUI

/// Shared factory for standalone NSWindow chrome.
/// Every managed window (Screen Map, Settings, Diagnostics, etc.) uses this
/// to get consistent title bar styling, dark appearance, and positioning.
struct AppWindowShell {

    struct Config {
        var title: String
        var titleVisible: Bool = true
        var initialSize: NSSize
        var minSize: NSSize
        var maxSize: NSSize
        var miniaturizable: Bool = true
    }

    /// Create a styled NSWindow hosting a SwiftUI root view.
    static func makeWindow<V: View>(config: Config, rootView: V) -> NSWindow {
        let hosting = NSHostingView(
            rootView: rootView
                .preferredColorScheme(.dark)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.sizingOptions = []

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]
        if config.miniaturizable { styleMask.insert(.miniaturizable) }

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: config.initialSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(origin: .zero, size: config.initialSize))
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        w.contentView = container
        w.title = config.title
        w.titlebarAppearsTransparent = true
        w.titleVisibility = config.titleVisible ? .visible : .hidden
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        w.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        w.appearance = NSAppearance(named: .darkAqua)
        w.minSize = config.minSize
        w.maxSize = config.maxSize
        return w
    }

    /// Center the window on screen, nudged 8% above vertical center.
    /// Clamps to 92% screen width / 85% screen height.
    static func positionCentered(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = window.frame.size
        let w = min(size.width, frame.width * 0.92)
        let h = min(size.height, frame.height * 0.85)
        let x = frame.midX - w / 2
        let y = frame.midY - h / 2 + (frame.height * 0.08)
        window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    /// Bring the window to front and update activation policy.
    static func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.updateActivationPolicy()
    }
}
