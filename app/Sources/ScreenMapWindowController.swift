import AppKit
import SwiftUI

/// Manages the standalone Screen Map editor window.
/// Follows the MainWindow pattern: singleton, real NSWindow with title bar chrome.
final class ScreenMapWindowController {
    static let shared = ScreenMapWindowController()

    private var window: NSWindow?
    private var controller: ScreenMapController?

    var isVisible: Bool { window?.isVisible ?? false }

    /// Exposed for event monitor filtering
    var nsWindow: NSWindow? { window }

    func toggle() {
        if let w = window, w.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        if let existing = window {
            // Re-enter (refresh snapshot) and bring forward
            controller?.enter()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let ctrl = ScreenMapController()
        ctrl.onDismiss = { [weak self] in
            self?.close()
        }
        ctrl.enter()

        let view = ScreenMapView(controller: ctrl)
            .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 560)

        // Compute size from screen aspect ratio
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var bbox = CGRect.zero
        for (i, screen) in screens.enumerated() {
            let cgY = primaryHeight - screen.frame.maxY
            let cgRect = CGRect(x: screen.frame.origin.x, y: cgY,
                                width: screen.frame.width, height: screen.frame.height)
            bbox = i == 0 ? cgRect : bbox.union(cgRect)
        }
        let aspectRatio = bbox.width / max(bbox.height, 1)
        let windowHeight: CGFloat = 620
        let windowWidth = max(860, windowHeight * aspectRatio + 100)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "Screen Map"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .visible
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        w.appearance = NSAppearance(named: .darkAqua)
        w.minSize = NSSize(width: 600, height: 400)
        w.maxSize = NSSize(width: 2400, height: 1600)

        // Center horizontally, slightly above vertical center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let clampedWidth = min(windowWidth, screenFrame.width * 0.92)
            let clampedHeight = min(windowHeight, screenFrame.height * 0.85)
            let x = screenFrame.midX - clampedWidth / 2
            let y = screenFrame.midY - clampedHeight / 2 + (screenFrame.height * 0.08)
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = w
        self.controller = ctrl
        AppDelegate.updateActivationPolicy()
    }

    func close() {
        controller?.endPreview()
        window?.orderOut(nil)
        window = nil
        controller = nil
        AppDelegate.updateActivationPolicy()
    }
}
