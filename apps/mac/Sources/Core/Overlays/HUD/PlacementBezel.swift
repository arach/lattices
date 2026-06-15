import AppKit
import SwiftUI

// MARK: - Placement confirmation bezel

/// A notch-style confirmation pill for a placement action — a stylized direction
/// arrow + the window it acted on. Modeled on `LayerBezel`; springs in
/// (grab → accelerate → snap) and fades out on its own.
final class PlacementBezel {
    static let shared = PlacementBezel()

    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var token = 0

    /// Show the confirmation. `glyph` is an SF Symbol (a direction arrow for
    /// placements); `title` is the headline (the window/app), `subtitle` the
    /// secondary line (what ran).
    func show(glyph: String, title: String, subtitle: String?, on screen: NSScreen?) {
        dismissTimer?.invalidate()
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.frame

        let w: CGFloat = 460, h: CGFloat = 120
        let frame = NSRect(
            x: sf.origin.x + (sf.width - w) / 2,
            y: sf.origin.y + sf.height * 0.60,
            width: w, height: h
        )

        token &+= 1
        let mine = token
        let host = NSHostingView(rootView: PlacementBezelView(glyph: glyph, title: title, subtitle: subtitle))

        if panel == nil {
            let p = NSPanel(
                contentRect: frame,
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
        p.setFrame(frame, display: false)
        p.alphaValue = 1
        p.orderFrontRegardless()

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
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
}

// MARK: - Bezel view

private struct PlacementBezelView: View {
    let glyph: String
    let title: String
    let subtitle: String?

    @State private var shown = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: glyph)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(
                    .linearGradient(colors: [.white, .white.opacity(0.8)],
                                    startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    .linearGradient(colors: [.white.opacity(0.9), .white.opacity(0.22)],
                                    startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.5
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.linearGradient(colors: [.white.opacity(0.08), .clear],
                                      startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        // grab → accelerate → snap: a snappy, lightly-overshooting spring.
        .scaleEffect(shown ? 1.0 : 0.84)
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.60)) { shown = true }
        }
    }
}
