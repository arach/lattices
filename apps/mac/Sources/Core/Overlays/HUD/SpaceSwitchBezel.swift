import AppKit
import SwiftUI

// MARK: - Space Switch HUD

/// Compact acknowledgement for Ctrl+←/→ space jumps handled by
/// `SpaceSwitchInterceptor`. A boxy tray of logo-cells — one rounded square
/// per space, the logo's own bright/dim language — docked top-center by
/// default. `SpaceSwitchBezelPosition` is agent-configurable via
/// `settings.spaceBezel.set` (top, bottom, center, or travelEdge, which
/// docks at the screen edge the desktop is moving toward).
final class SpaceSwitchBezel {
    static let shared = SpaceSwitchBezel()

    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var token = 0

    /// `direction`: -1 = left, +1 = right. `targetIndex` is the 1-based space
    /// we landed on; nil means the display was already at the edge and
    /// `currentIndex` is shown with the amber "EDGE" treatment instead.
    func show(direction: Int, targetIndex: Int?, currentIndex: Int?, total: Int, on screen: NSScreen? = nil) {
        dismissTimer?.invalidate()
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.frame

        let height: CGFloat = 40
        let width = pillWidth(total: total)
        let endFrame = frame(for: Preferences.shared.spaceSwitchBezelPosition,
                             direction: direction, width: width, height: height, in: sf)

        // Enter offset ~16pt from the direction of travel.
        let drift: CGFloat = direction >= 0 ? -16 : 16
        let startFrame = endFrame.offsetBy(dx: drift, dy: 0)

        token &+= 1
        let mine = token
        let view = SpaceSwitchBezelView(
            direction: direction,
            activeIndex: targetIndex ?? currentIndex,
            edge: targetIndex == nil,
            total: total
        )
        let host = NSHostingView(rootView: view)

        if panel == nil {
            let p = NSPanel(
                contentRect: endFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.isMovable = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel = p
        }
        guard let p = panel else { return }

        p.contentView = host
        p.setFrame(startFrame, display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.35, 0.36, 1)
            p.animator().alphaValue = 1.0
            p.animator().setFrame(endFrame, display: true)
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            guard let self, self.token == mine else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    private func frame(for position: SpaceSwitchBezelPosition, direction: Int,
                       width: CGFloat, height: CGFloat, in sf: NSRect) -> NSRect {
        switch position {
        case .travelEdge:
            let x = direction >= 0 ? sf.maxX - width - 26 : sf.minX + 26
            return NSRect(x: x, y: sf.midY - height / 2, width: width, height: height)
        case .top:
            return NSRect(x: sf.midX - width / 2, y: sf.maxY - height - 50, width: width, height: height)
        case .center:
            return NSRect(x: sf.midX - width / 2, y: sf.midY - height / 2, width: width, height: height)
        case .bottom:
            return NSRect(x: sf.midX - width / 2, y: sf.minY + 68, width: width, height: height)
        }
    }

    private func pillWidth(total: Int) -> CGFloat {
        let n = max(total, 1)
        let cell = Self.cellSize(total: total)
        let cellsWidth = n > 1 ? CGFloat(n) * cell + CGFloat(n - 1) * Self.cellGap : 0
        // tick(10) + gaps + hairline(1) + "DESKTOP N" + "LATTICES" + padding
        let labelWidth: CGFloat = total >= 10 ? 76 : 62
        return ceil(11 + 10 + 9 + cellsWidth + 9 + 1 + 9 + labelWidth + 9 + 44 + 11)
    }

    private static let cellGap: CGFloat = 6

    /// Logo cells stay 15pt through a dozen spaces, then shrink to keep the
    /// tray inside ~280pt.
    static func cellSize(total: Int) -> CGFloat {
        guard total > 12 else { return 15 }
        return max(7, floor((240 - CGFloat(total - 1) * cellGap) / CGFloat(total)))
    }
}

// MARK: - Bezel View

private struct SpaceSwitchBezelView: View {
    let direction: Int
    let activeIndex: Int?
    let edge: Bool
    let total: Int

    private var accent: Color { edge ? HUDChrome.amber : HUDChrome.cyan }

    private var cellSize: CGFloat { SpaceSwitchBezel.cellSize(total: total) }

    var body: some View {
        HStack(spacing: 9) {
            // Direction tick — the only chromatic element besides EDGE.
            Text(edge ? "↔" : (direction < 0 ? "‹" : "›"))
                .font(Typo.monoBold(13))
                .foregroundStyle(accent)

            if total > 1 {
                HStack(spacing: 6) {
                    ForEach(1...total, id: \.self) { i in
                        RoundedRectangle(cornerRadius: cellSize * 0.24, style: .continuous)
                            .fill(i == activeIndex
                                  ? (edge ? HUDChrome.amber : Color(white: 0.95))
                                  : Color.white.opacity(0.18))
                            .frame(width: cellSize, height: cellSize)
                            .shadow(color: i == activeIndex ? accent.opacity(0.45) : .clear, radius: 4)
                    }
                }
            }

            HUDHairline(axis: .vertical, opacity: 0.9)
                .frame(height: 16)

            Text(edge ? "EDGE" : "DESKTOP \(activeIndex ?? 0)")
                .font(Typo.monoBold(10))
                .tracking(0.7)
                .foregroundStyle(edge ? HUDChrome.amber : Palette.text)

            Text("LATTICES")
                .font(Typo.monoBold(6.5))
                .tracking(1.2)
                .foregroundStyle(Palette.textDim)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 11)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [HUDChrome.baseTop, HUDChrome.baseBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Directional wash — light bleeds in from the edge of travel.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(edge ? 0.08 : 0.14), Color.clear],
                            startPoint: direction >= 0 ? .trailing : .leading,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(edge ? HUDChrome.amber.opacity(0.38) : Color.white.opacity(0.10), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 16, y: 8)
        .shadow(color: accent.opacity(edge ? 0.06 : 0.14), radius: 12)
    }
}
