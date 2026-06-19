import AppKit
import SwiftUI

/// Manages the main lattices window as a standalone NSWindow.
/// Menu bar icon toggles this window open/closed.
final class MainWindow {
    static let shared = MainWindow()

    private var window: NSWindow?
    private var keyMonitor: Any?

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

        let w = AppWindowShell.makeWindow(
            config: .init(
                title: "Lattices",
                initialSize: NSSize(width: 380, height: 460),
                minSize: NSSize(width: 340, height: 380)
            ),
            rootView: view
        )

        // Position near top-right of screen (close to menu bar area)
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.maxX - 380 - 20
            let y = visibleFrame.maxY - 460 - 10
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        AppWindowShell.present(w)

        window = w
        AppDelegate.updateActivationPolicy()

        // Escape key → close
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,
                  self?.window?.isKeyWindow == true else { return event }
            self?.close()
            return nil
        }
    }

    func close() {
        window?.orderOut(nil)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        AppDelegate.updateActivationPolicy()
    }
}
