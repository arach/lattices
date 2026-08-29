import AppKit

/// Full-screen blur + dim that sits one layer beneath the panel being edited:
/// the note you're writing stays crisp while everything around it — other
/// apps, other panels — recedes. Click-through, so the world stays usable.
@MainActor
final class FocusOverlay {
    private let window: NSWindow
    private let dimView = NSView()

    /// Themable dim strength (config.json → focus.dim). The veil follows the app
    /// scheme: black recedes the world in dark mode, white in light mode — same
    /// "quiet the surroundings" job, mirrored.
    func applyTheme(dim: Double) {
        let scheme = AppearanceManager.shared.scheme
        window.appearance = NSAppearance(named: scheme.nsAppearanceName)
        let base: NSColor = scheme.isDark ? .black : .white
        dimView.layer?.backgroundColor = base.withAlphaComponent(dim).cgColor
    }

    init() {
        let w = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.appearance = NSAppearance(named: AppearanceManager.shared.scheme.nsAppearanceName)
        w.hasShadow = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active

        let dim = dimView
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        dim.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(dim)
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: blur.topAnchor),
            dim.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])

        w.contentView = blur
        w.alphaValue = 0
        window = w
    }

    /// Fade in on the panel's screen, ordered directly beneath it.
    func show(behind panel: NSPanel) {
        guard let frame = (panel.screen ?? NSScreen.main)?.frame else { return }
        window.setFrame(frame, display: false)
        window.order(.below, relativeTo: panel.windowNumber)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 1
        }
    }

    /// Fade out. The window stays ordered but fully transparent and
    /// click-through — no teardown needed between focus sessions.
    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 0
        }
    }
}
