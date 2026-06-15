import AppKit
import SwiftUI

/// Full-screen 4x4 "placement target" overlay. Triggered by a hotkey
/// (Ctrl+Opt+G by default), it captures the frontmost window up front — before
/// presenting (which activates Lattices and would otherwise become the
/// "frontmost" app) — then snaps that captured window into the chosen cell via
/// `WindowTiler.tileWindowById`.
final class GridPlacementWindow {
    static let shared = GridPlacementWindow()

    private var panel: OverlayPanel?
    private var capturedTarget: (wid: UInt32, pid: Int32)?
    private var capturedScreen: NSScreen?
    /// Shared with the view so mouse drags and keyboard ⇧-anchors highlight the
    /// same in-progress span.
    private let selection = GridPlacementSelection()

    /// NSEvent keyCode → (column, row), 0-indexed from top-left. Mirrors the
    /// keyboard's bottom-left 4x4 block and `GridPlacementView.keyLabels`.
    private static let keyMap: [UInt16: (col: Int, row: Int)] = [
        18: (0, 0), 19: (1, 0), 20: (2, 0), 21: (3, 0), // 1 2 3 4
        12: (0, 1), 13: (1, 1), 14: (2, 1), 15: (3, 1), // Q W E R
        0:  (0, 2), 1:  (1, 2), 2:  (2, 2), 3:  (3, 2), // A S D F
        6:  (0, 3), 7:  (1, 3), 8:  (2, 3), 9:  (3, 3), // Z X C V
    ]

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let p = panel, p.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        // Always rebuild fresh; capture the target before anything activates us.
        dismiss()

        guard let entry = DesktopModel.shared.frontmostWindow() else {
            DiagnosticLog.shared.info("GridPlacement: no frontmost window to place")
            return
        }

        capturedTarget = (wid: entry.wid, pid: entry.pid)
        let screen = screenForWindowFrame(entry.frame)
        capturedScreen = screen
        selection.reset()

        let view = GridPlacementView(
            appName: entry.app,
            selection: selection,
            onSelect: { [weak self] c0, r0, c1, r1 in self?.place(c0: c0, r0: r0, c1: c1, r1: r1) },
            onCancel: { [weak self] in self?.dismiss() }
        )
        .preferredColorScheme(.dark)

        let panel = OverlayPanelShell.makePanel(
            config: .init(
                size: screen.visibleFrame.size,
                styleMask: [.nonactivatingPanel],
                background: .clear,
                level: .floating,
                activatesOnMouseDown: true,
                onKeyDown: { [weak self] event in self?.handleKey(event) }
            ),
            rootView: view
        )
        panel.setFrame(screen.visibleFrame, display: true)
        OverlayPanelShell.present(panel)

        self.panel = panel
        AppDelegate.updateActivationPolicy()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        capturedTarget = nil
        capturedScreen = nil
        selection.reset()
        AppDelegate.updateActivationPolicy()
    }

    // MARK: - Selection

    private func handleKey(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape: cancel an in-progress span first, else close.
            if selection.hasAnchor { selection.reset() } else { dismiss() }
            return
        }
        guard let cell = Self.keyMap[event.keyCode] else { return }
        let c = GridCell(col: cell.col, row: cell.row)

        // A span started with ⇧ (or a held anchor) is completed by the next key.
        if let a = selection.anchor {
            place(c0: a.col, r0: a.row, c1: c.col, r1: c.row)
            return
        }
        // ⇧ + first key begins a span; a plain key places a single cell now.
        if event.modifierFlags.contains(.shift) {
            selection.anchor = c
            selection.focus = c
        } else {
            place(c0: c.col, r0: c.row, c1: c.col, r1: c.row)
        }
    }

    private func place(c0: Int, r0: Int, c1: Int, r1: Int) {
        guard let target = capturedTarget,
              let grid = GridPlacement(columns: 4, rows: 4, from: (c0, r0), to: (c1, r1)) else {
            dismiss()
            return
        }
        let screen = capturedScreen
        // Dismiss first so the overlay isn't raised over the result.
        dismiss()
        WindowTiler.tileWindowById(
            wid: target.wid,
            pid: target.pid,
            fractions: grid.fractions,
            on: screen
        )
    }

    // MARK: - Screen resolution

    /// Map a CGWindowList-style frame (top-left origin, primary-relative) to the
    /// NSScreen that contains its center. Mirrors `WindowTiler.screenForAXWindow`.
    private func screenForWindowFrame(_ f: WindowFrame) -> NSScreen {
        let primaryH = NSScreen.screens.first?.frame.height ?? 1080
        let cx = CGFloat(f.x + f.w / 2)
        let cyTop = CGFloat(f.y + f.h / 2)
        let pt = NSPoint(x: cx, y: primaryH - cyTop)
        return NSScreen.screens.first(where: { $0.frame.contains(pt) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
