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
    private let state = SpaceBezelState()

    /// `direction`: -1 = left, +1 = right. `targetIndex` is the 1-based space
    /// we landed on; nil means the display was already at the edge and
    /// `currentIndex` is shown with the amber "EDGE" treatment instead.
    ///
    /// The tray itself is stable — it fades in once and never translates.
    /// Motion lives in the active cell, which glides between positions.
    func show(direction: Int, targetIndex: Int?, currentIndex: Int?, total: Int, on screen: NSScreen? = nil) {
        dismissTimer?.invalidate()
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.frame

        let height: CGFloat = 40
        let width = pillWidth(total: total)
        let endFrame = frame(for: Preferences.shared.spaceSwitchBezelPosition,
                             direction: direction, width: width, height: height, in: sf)

        token &+= 1
        let mine = token

        state.direction = direction
        state.activeIndex = targetIndex ?? currentIndex
        state.edge = targetIndex == nil
        state.total = total

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
            p.contentView = NSHostingView(rootView: SpaceSwitchBezelView(state: state))
            panel = p
        }
        guard let p = panel else { return }

        if p.isVisible {
            // Already up — keep the box anchored; the cell carries the motion.
            if p.frame != endFrame { p.setFrame(endFrame, display: true) }
            p.alphaValue = 1
        } else {
            p.setFrame(endFrame, display: false)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                p.animator().alphaValue = 1.0
            }
        }

        SpaceEdgeSweep.shared.fire(direction: direction, edge: targetIndex == nil, on: screen)

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

// MARK: - Bezel State + View

/// Mutable content for the persistent bezel panel — `show()` mutates this
/// and SwiftUI animates the cell, while the tray chrome stays put.
final class SpaceBezelState: ObservableObject {
    @Published var direction: Int = 1
    @Published var activeIndex: Int? = nil
    @Published var edge: Bool = false
    @Published var total: Int = 0
}

private struct SpaceSwitchBezelView: View {
    @ObservedObject var state: SpaceBezelState
    @Namespace private var travel

    private var accent: Color { state.edge ? HUDChrome.amber : HUDChrome.cyan }
    private var cellSize: CGFloat { SpaceSwitchBezel.cellSize(total: state.total) }

    var body: some View {
        HStack(spacing: 9) {
            // Direction tick — the only chromatic element besides EDGE.
            Text(state.edge ? "↔" : (state.direction < 0 ? "‹" : "›"))
                .font(Typo.monoBold(13))
                .foregroundStyle(accent)

            if state.total > 1 {
                HStack(spacing: 6) {
                    ForEach(1...state.total, id: \.self) { i in
                        RoundedRectangle(cornerRadius: cellSize * 0.24, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: cellSize, height: cellSize)
                            .overlay {
                                if i == state.activeIndex {
                                    RoundedRectangle(cornerRadius: cellSize * 0.24, style: .continuous)
                                        .fill(state.edge ? HUDChrome.amber : Color(white: 0.95))
                                        .matchedGeometryEffect(id: "active", in: travel)
                                        .shadow(color: accent.opacity(0.45), radius: 4)
                                }
                            }
                    }
                }
                .animation(.snappy(duration: 0.22, extraBounce: 0.05), value: state.activeIndex)
                .animation(.easeOut(duration: 0.18), value: state.edge)
            }

            HUDHairline(axis: .vertical, opacity: 0.9)
                .frame(height: 16)

            Text(state.edge ? "EDGE" : "DESKTOP \(state.activeIndex ?? 0)")
                .font(Typo.monoBold(10))
                .tracking(0.7)
                .foregroundStyle(state.edge ? HUDChrome.amber : Palette.text)

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
                            colors: [accent.opacity(state.edge ? 0.08 : 0.14), Color.clear],
                            startPoint: state.direction >= 0 ? .trailing : .leading,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(state.edge ? HUDChrome.amber.opacity(0.38) : Color.white.opacity(0.10), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 16, y: 8)
        .shadow(color: accent.opacity(state.edge ? 0.06 : 0.14), radius: 12)
    }
}

// MARK: - Edge Sweep

/// A hairline beam at the very top edge of the display that drifts in the
/// direction of travel and fades — a subtle directional echo of the space
/// change itself, since the switch renders as an instant cut.
final class SpaceEdgeSweep {
    static let shared = SpaceEdgeSweep()

    private var panel: NSPanel?
    private let state = SweepState()

    func fire(direction: Int, edge: Bool, on screen: NSScreen? = nil) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let height: CGFloat = 2.5
        let beamWidth = vf.width * 0.32
        let y = vf.maxY - height

        state.direction = direction
        state.edge = edge

        let startX = direction >= 0 ? vf.minX : vf.maxX - beamWidth
        let endX = direction >= 0 ? vf.maxX - beamWidth : vf.minX
        let startFrame = NSRect(x: startX, y: y, width: beamWidth, height: height)
        let endFrame = startFrame.offsetBy(dx: endX - startX, dy: 0)

        if panel == nil {
            let p = NSPanel(
                contentRect: startFrame,
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
            p.contentView = NSHostingView(rootView: SweepView(state: state))
            panel = p
        }
        guard let p = panel else { return }

        p.setFrame(startFrame, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.4, 1)
            p.animator().setFrame(endFrame, display: true)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }
}

final class SweepState: ObservableObject {
    @Published var direction: Int = 1
    @Published var edge: Bool = false
}

private struct SweepView: View {
    @ObservedObject var state: SweepState

    private var accent: Color { state.edge ? HUDChrome.amber : HUDChrome.cyan }

    var body: some View {
        // Bright at the leading edge of travel, dying out behind it.
        LinearGradient(
            colors: [accent.opacity(0.9), accent.opacity(0.35), Color.clear],
            startPoint: state.direction >= 0 ? .trailing : .leading,
            endPoint: state.direction >= 0 ? .leading : .trailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
