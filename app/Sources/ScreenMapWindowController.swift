import AppKit
import SwiftUI

/// Manages the unified app window (Screen Map + Settings).
/// Singleton with show/close/toggle, plus showPage() for navigation.
final class ScreenMapWindowController: ObservableObject {
    static let shared = ScreenMapWindowController()

    private var window: NSWindow?
    private var controller: ScreenMapController?
    @Published var activePage: AppPage = .screenMap

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

    /// Show the window on the current page (defaults to Screen Map).
    func show() {
        if let existing = window {
            if activePage == .screenMap {
                controller?.enter()
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let ctrl = ScreenMapController()
        ctrl.onDismiss = { [weak self] in
            self?.close()
        }
        if activePage == .screenMap {
            ctrl.enter()
        }

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
        let windowWidth = max(860, CGFloat(620) * aspectRatio + 100)

        let view = AppShellView(controller: ctrl)

        let w = AppWindowShell.makeWindow(
            config: .init(
                title: "Lattice",
                initialSize: NSSize(width: windowWidth, height: 620),
                minSize: NSSize(width: 600, height: 400),
                maxSize: NSSize(width: 2400, height: 1600)
            ),
            rootView: view
        )
        AppWindowShell.positionCentered(w)
        AppWindowShell.present(w)

        self.window = w
        self.controller = ctrl
    }

    /// Navigate to a specific page, opening the window if needed.
    func showPage(_ page: AppPage) {
        activePage = page
        show()
    }

    func close() {
        controller?.endPreview()
        window?.orderOut(nil)
        window = nil
        controller = nil
        activePage = .screenMap
        AppDelegate.updateActivationPolicy()
    }
}
