import AppKit
import SwiftUI

/// Manages the unified app window (Home + Layout + Search + Settings).
/// Singleton with show/close/toggle, plus showPage() for navigation.
final class ScreenMapWindowController: ObservableObject {
    static let shared = ScreenMapWindowController()

    private var window: NSWindow?
    private var controller: ScreenMapController?
    @Published var activePage: AppPage = .home

    var isVisible: Bool { window?.isVisible ?? false }

    /// Exposed for event monitor filtering
    var nsWindow: NSWindow? { window }

    private var workspaceWindowSize: NSSize {
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
        let width = min(max(860, CGFloat(620) * aspectRatio + 100), 1600)
        return NSSize(width: width, height: 620)
    }

    private func preferredWindowSize(for page: AppPage) -> NSSize {
        switch page {
        case .home:
            return NSSize(width: 980, height: 720)
        case .settings, .companionSettings, .docs:
            return NSSize(width: 900, height: 640)
        case .screenMap, .desktopInventory, .pi:
            return workspaceWindowSize
        }
    }

    func toggle() {
        if let w = window, w.isVisible {
            close()
        } else {
            show()
        }
    }

    /// Show the window on the current page (defaults to Home).
    func show() {
        if let existing = window {
            if activePage == .screenMap {
                controller?.enter()
            }
            applyPreferredSizing(for: activePage, animate: false)
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

        let view = AppShellView(controller: ctrl)
        let initialSize = preferredWindowSize(for: activePage)

        let w = AppWindowShell.makeWindow(
            config: .init(
                title: "Lattices",
                initialSize: initialSize,
                minSize: NSSize(width: 600, height: 400),
                maxSize: NSSize(width: 2400, height: 1600)
            ),
            rootView: view
        )
        AppWindowShell.positionCentered(w)
        AppWindowShell.present(w)

        self.window = w
        self.controller = ctrl
        settlePreferredSizing(for: activePage)
    }

    /// Navigate to a specific page, opening the window if needed.
    func showPage(_ page: AppPage) {
        activePage = page
        show()
        applyPreferredSizing(for: page, animate: true)
        settlePreferredSizing(for: page)
    }

    private func settlePreferredSizing(for page: AppPage) {
        for delay in [0.0, 0.12, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.activePage == page else { return }
                self.applyPreferredSizing(for: page, animate: false)
            }
        }
    }

    func applyPreferredSizing(for page: AppPage, animate: Bool = true) {
        guard let window else { return }
        if window.isZoomed {
            window.zoom(nil)
        }

        guard let screen = window.screen ?? NSScreen.main else { return }
        let desired = preferredWindowSize(for: page)
        let visible = screen.visibleFrame
        let width = min(desired.width, visible.width * 0.92)
        let height = min(desired.height, visible.height * 0.85)
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2 + (visible.height * 0.04),
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: animate)
    }

    func showScreenMapOverview() {
        activePage = .screenMap
        show()
        DispatchQueue.main.async { [weak self] in
            self?.controller?.focusViewportPreset(.overview)
        }
    }

    /// Open screen map focused on a specific window.
    func showWindow(wid: UInt32) {
        activePage = .screenMap
        show()

        // Avoid overlapping the voice panel — nudge screen map below it
        if let w = window, let voicePanel = VoiceCommandWindow.shared.panel, voicePanel.isVisible {
            let voiceBottom = voicePanel.frame.minY
            let mapFrame = w.frame
            if mapFrame.maxY > voiceBottom - 10 {
                // Position just below the voice panel
                let newY = voiceBottom - mapFrame.height - 16
                w.setFrameOrigin(NSPoint(x: mapFrame.origin.x, y: max(newY, 40)))
            }
        }

        // Select after a brief delay so the controller has time to populate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.controller?.selectSingle(wid)
        }
    }

    func close() {
        controller?.endPreview()
        window?.orderOut(nil)
        window = nil
        controller = nil
        activePage = .home
        AppDelegate.updateActivationPolicy()
    }
}
