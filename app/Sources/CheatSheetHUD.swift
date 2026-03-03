import AppKit
import SwiftUI

// MARK: - CheatSheetHUD (singleton window controller)

final class CheatSheetHUD {
    static let shared = CheatSheetHUD()

    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        guard panel == nil else { return }

        let view = CheatSheetView()
            .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = false
        p.contentView = hosting

        // Center on the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - 260
        let y = screenFrame.midY - 210
        p.setFrameOrigin(NSPoint(x: x, y: y))

        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1.0
        }

        self.panel = p
        installMonitors()
    }

    func dismiss() {
        guard let p = panel else { return }
        removeMonitors()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }) { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
        }
    }

    // MARK: - Event monitors

    private func installMonitors() {
        // Escape key dismisses (global — panel is non-activating so keys go to frontmost app)
        localMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
            }
        }

        // Click outside dismisses
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

}

// MARK: - CheatSheetView

struct CheatSheetView: View {
    @ObservedObject private var hotkeyStore = HotkeyStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("KEYBOARD SHORTCUTS")
                    .font(Typo.pixel(14))
                    .foregroundColor(Palette.textDim)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Two-column body
            HStack(alignment: .top, spacing: 20) {
                // Left column: Tiling
                tilingColumn

                Rectangle().fill(Palette.border).frame(width: 0.5)

                // Right column: App + tmux
                VStack(alignment: .leading, spacing: 16) {
                    appColumn
                    Rectangle().fill(Palette.border).frame(height: 0.5)
                    tmuxColumn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Spacer(minLength: 0)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Footer
            HStack {
                Spacer()
                Text("Press ESC to dismiss")
                    .font(Typo.caption(10))
                    .foregroundColor(Palette.textMuted)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 520, height: 420)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Tiling Column

    private var tilingColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            columnHeader("Tiling")

            // 3x3 grid
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    tileCell(action: .tileTopLeft, label: "TL")
                    tileCell(action: .tileTop, label: "Top")
                    tileCell(action: .tileTopRight, label: "TR")
                }
                HStack(spacing: 2) {
                    tileCell(action: .tileLeft, label: "Left")
                    tileCell(action: .tileMaximize, label: "Max")
                    tileCell(action: .tileRight, label: "Right")
                }
                HStack(spacing: 2) {
                    tileCell(action: .tileBottomLeft, label: "BL")
                    tileCell(action: .tileBottom, label: "Bot")
                    tileCell(action: .tileBottomRight, label: "BR")
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )

            // Thirds row
            HStack(spacing: 2) {
                tileCell(action: .tileLeftThird, label: "\u{2153}L")
                tileCell(action: .tileCenterThird, label: "\u{2153}C")
                tileCell(action: .tileRightThird, label: "\u{2153}R")
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )

            // Center + Distribute
            shortcutRow(action: .tileCenter)
            shortcutRow(action: .tileDistribute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - App Column

    private var appColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader("App")

            shortcutRow(action: .palette)
            shortcutRow(action: .screenMap)
            shortcutRow(action: .bezel)
            shortcutRow(action: .cheatSheet)
        }
    }

    // MARK: - tmux Column

    private var tmuxColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader("Inside tmux")

            tmuxRow("Detach", keys: ["Ctrl+B", "D"])
            tmuxRow("Kill pane", keys: ["Ctrl+B", "X"])
            tmuxRow("Pane left", keys: ["Ctrl+B", "\u{2190}"])
            tmuxRow("Pane right", keys: ["Ctrl+B", "\u{2192}"])
            tmuxRow("Zoom toggle", keys: ["Ctrl+B", "Z"])
            tmuxRow("Scroll mode", keys: ["Ctrl+B", "["])
        }
    }

    // MARK: - Shared components

    private func columnHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typo.pixel(12))
            .foregroundColor(Palette.textDim)
            .tracking(1)
    }

    private func tileCell(action: HotkeyAction, label: String) -> some View {
        let binding = hotkeyStore.bindings[action]
        let badgeText = binding?.displayParts.last ?? ""

        return VStack(spacing: 3) {
            Text(label)
                .font(Typo.caption(9))
                .foregroundColor(Palette.textDim)
            Text(badgeText)
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.text)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private func shortcutRow(action: HotkeyAction) -> some View {
        let binding = hotkeyStore.bindings[action]
        return HStack(spacing: 8) {
            if let parts = binding?.displayParts {
                HStack(spacing: 3) {
                    ForEach(parts, id: \.self) { part in
                        keyBadge(part)
                    }
                }
            }
            Text(action.label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
            Spacer()
        }
    }

    private func tmuxRow(_ label: String, keys: [String]) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    keyBadge(key)
                }
            }
            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
            Spacer()
        }
    }

    private func keyBadge(_ key: String) -> some View {
        Text(key)
            .font(Typo.geistMonoBold(10))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
    }
}
