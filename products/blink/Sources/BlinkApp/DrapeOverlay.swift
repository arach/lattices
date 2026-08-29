import AppKit

/// Full-screen blur + dim surfaces parked one level beneath the note panels.
/// There is one native window per display that currently contains a visible
/// note. A single union-sized window is not reliable across macOS displays:
/// its visual-effect backing belongs to one screen, so the blur can appear on
/// the neighboring monitor instead of behind the notes.
@MainActor
final class DrapeOverlay {
    @MainActor
    private final class Surface {
        let window: NSWindow
        let blur = NSVisualEffectView()
        let dimView = NSView()

        init() {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            // One step below note panels' `.floating` level: behind every note,
            // above ordinary windows such as terminals, editors, and browsers.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.appearance = NSAppearance(named: AppearanceManager.shared.scheme.nsAppearanceName)
            window.hasShadow = false

            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active

            dimView.wantsLayer = true
            dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
            dimView.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(dimView)
            NSLayoutConstraint.activate([
                dimView.topAnchor.constraint(equalTo: blur.topAnchor),
                dimView.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                dimView.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            ])

            window.contentView = blur
            window.alphaValue = 0
            self.window = window
        }

        func applyTheme(dim: CGFloat, material: NSVisualEffectView.Material) {
            // Follow the app scheme: a dark stage in dark mode, a bright one in
            // light. `.hudWindow` stays dark even under aqua, so swap it for a
            // light glass when the veil itself has gone light.
            let scheme = AppearanceManager.shared.scheme
            window.appearance = NSAppearance(named: scheme.nsAppearanceName)
            let base: NSColor = scheme.isDark ? .black : .white
            dimView.layer?.backgroundColor = base.withAlphaComponent(dim).cgColor
            blur.material = (scheme == .light && material == .hudWindow) ? .popover : material
        }

        func show(frame: NSRect, opacity: CGFloat) {
            window.setFrame(frame, display: false)
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                window.animator().alphaValue = opacity
            }
        }

        func hide() {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                window.animator().alphaValue = 0
            }
        }
    }

    private var surfaces: [CGDirectDisplayID: Surface] = [:]
    private var dim: CGFloat = 0.45
    private var material: NSVisualEffectView.Material = .hudWindow
    private var targetOpacity: CGFloat = 1

    /// Themable strength, material, and overall presence
    /// (config.json → drape.dim / drape.material / drape.opacity).
    func applyTheme(dim: Double, material: NSVisualEffectView.Material, opacity: Double) {
        self.dim = max(0, min(1, CGFloat(dim)))
        self.material = material
        targetOpacity = max(0, min(1, CGFloat(opacity)))
        for surface in surfaces.values {
            surface.applyTheme(dim: self.dim, material: material)
        }
    }

    /// Show one drape surface on each display occupied by a visible note. This
    /// also retires surfaces for displays that no longer contain notes, so
    /// moving the last note between monitors moves the stage with it.
    func show(on screens: [NSScreen]) {
        var desired: [CGDirectDisplayID: NSScreen] = [:]
        for (index, screen) in screens.enumerated() {
            // NSScreenNumber is the stable CG display id. The index fallback is
            // only for unusual virtual screens that omit the device key.
            let fallback = CGDirectDisplayID.max - CGDirectDisplayID(index)
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber)?.uint32Value ?? fallback
            desired[id] = screen
        }

        for (id, screen) in desired {
            let surface: Surface
            if let existing = surfaces[id] {
                surface = existing
            } else {
                surface = Surface()
                surface.applyTheme(dim: dim, material: material)
                surfaces[id] = surface
            }
            surface.show(frame: screen.frame, opacity: targetOpacity)
        }

        for (id, surface) in surfaces where desired[id] == nil {
            surface.hide()
        }
    }

    /// Fade out every allocated display surface. They stay click-through and
    /// reusable, avoiding window churn when notes blink or cross displays.
    func hide() {
        for surface in surfaces.values { surface.hide() }
    }
}
