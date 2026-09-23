import AppKit
import QuartzCore

/// Gives an instant Space switch a hint of the system slide without playing
/// it: a small swoosh of speed streaks at the pointer, whipping the way the
/// content travels and dropping out. Nothing is captured and nothing covers
/// the desktop, so the switch stays a clean cut. At the edge the streaks lean
/// toward the wall and snap back instead.
///
/// Main-thread only.
final class SpaceSwitchGlide {
    static let shared = SpaceSwitchGlide()

    private var panel: NSPanel?
    private var streaks: [CAGradientLayer] = []
    /// Bumped on every fire so a stale completion can't order out a newer one.
    private var generation = 0

    private static let panelSize = CGSize(width: 360, height: 120)
    /// Fixed lanes (y offset from the pointer, length, delay) so the pattern
    /// reads as one gesture rather than noise.
    private static let lanes: [(y: CGFloat, length: CGFloat, delay: CFTimeInterval)] = [
        (22, 44, 0.000),
        (8, 78, 0.014),
        (-6, 96, 0.004),
        (-20, 58, 0.022),
    ]

    /// When off (setting or Reduce Motion) the bezel falls back to the
    /// top-edge sweep.
    var isEnabled: Bool {
        Preferences.shared.spaceSwitchGlideEnabled
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `direction` is the Space direction (+1 = next). `steps` is how many
    /// Spaces the press travelled; bursts merge, so a bigger jump throws
    /// farther. `edge` plays the lean-and-return instead.
    func fire(direction: Int, steps: Int, edge: Bool) {
        guard isEnabled else { return }
        generation &+= 1
        let mine = generation
        let p = panel ?? makePanel()

        let pointer = NSEvent.mouseLocation
        let size = Self.panelSize
        p.setFrame(CGRect(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2,
                          width: size.width, height: size.height), display: false)

        // Content moves opposite the Space direction, like a real swipe.
        let heading = -CGFloat(direction)
        let throwScale = CGFloat(min(max(steps, 1), 3))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, lane) in zip(streaks, Self.lanes) {
            layer.removeAllAnimations()
            layer.bounds = CGRect(x: 0, y: 0, width: lane.length, height: 2)
            // Start just behind the pointer so the streaks pass through it.
            layer.position = CGPoint(x: center.x - heading * 34, y: center.y + lane.y)
            // Bright head on the leading side, tail trailing behind it.
            layer.startPoint = CGPoint(x: heading < 0 ? 1 : 0, y: 0.5)
            layer.endPoint = CGPoint(x: heading < 0 ? 0 : 1, y: 0.5)
            layer.opacity = 0
        }
        CATransaction.commit()

        p.alphaValue = 1
        p.orderFrontRegardless()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == mine else { return }
            self.panel?.orderOut(nil)
        }
        let now = CACurrentMediaTime()
        for (layer, lane) in zip(streaks, Self.lanes) {
            let move: CAAnimation
            if edge {
                let lean = heading * 16
                let bump = CAKeyframeAnimation(keyPath: "transform.translation.x")
                bump.values = [0, lean, lean * 0.2]
                bump.keyTimes = [0, 0.5, 1]
                bump.timingFunctions = [
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .easeIn),
                ]
                move = bump
            } else {
                let slide = CABasicAnimation(keyPath: "transform.translation.x")
                slide.fromValue = 0
                slide.toValue = heading * (84 + 26 * (throwScale - 1))
                slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.7, 0.35, 1)
                move = slide
            }

            let flash = CAKeyframeAnimation(keyPath: "opacity")
            flash.values = [0, 1, 0]
            flash.keyTimes = [0, 0.25, 1]

            let group = CAAnimationGroup()
            group.animations = [move, flash]
            group.duration = edge ? 0.22 : 0.2
            group.beginTime = now + lane.delay
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            layer.add(group, forKey: "streak")
        }
        CATransaction.commit()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: .zero,
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
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        for _ in Self.lanes {
            let layer = CAGradientLayer()
            layer.colors = [
                NSColor.white.withAlphaComponent(0).cgColor,
                NSColor.white.withAlphaComponent(0.55).cgColor,
                NSColor.white.withAlphaComponent(0.95).cgColor,
            ]
            layer.locations = [0, 0.7, 1]
            layer.cornerRadius = 1
            // Soft dark halo keeps the streaks legible on light windows.
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.4
            layer.shadowRadius = 2
            layer.shadowOffset = .zero
            layer.opacity = 0
            view.layer?.addSublayer(layer)
            streaks.append(layer)
        }
        p.contentView = view
        panel = p
        return p
    }
}
