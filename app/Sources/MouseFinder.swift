import AppKit
import CoreGraphics

/// Locates the mouse cursor with an animated sonar pulse overlay.
/// "Find" shows rings at the current cursor position.
/// "Summon" warps the cursor to screen center (or a given point).
final class MouseFinder {
    static let shared = MouseFinder()

    private var overlayWindows: [NSWindow] = []
    private var dismissTimer: Timer?
    private var animationTimer: Timer?
    private var animationStart: CFTimeInterval = 0
    private let animationDuration: CFTimeInterval = 1.5

    // MARK: - Find (highlight current position)

    func find() {
        let pos = NSEvent.mouseLocation
        showSonar(at: pos)
    }

    // MARK: - Summon (warp to center of the screen the mouse is on, or a specific point)

    func summon(to point: CGPoint? = nil) {
        let target: NSPoint
        if let point {
            target = point
        } else {
            let screen = mouseScreen()
            let frame = screen.frame
            target = NSPoint(x: frame.midX, y: frame.midY)
        }

        // CGWarpMouseCursorPosition uses top-left origin
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: target.x, y: primaryHeight - target.y)
        CGWarpMouseCursorPosition(cgPoint)
        // Re-associate mouse with cursor position after warp
        CGAssociateMouseAndMouseCursorPosition(1)

        showSonar(at: target)
    }

    // MARK: - Sonar Animation

    private func showSonar(at nsPoint: NSPoint) {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let ringCount = 3
        let maxRadius: CGFloat = 120
        let totalSize = maxRadius * 2 + 20

        for screen in screens {
            // Only show on screens near the cursor
            let extendedBounds = screen.frame.insetBy(dx: -maxRadius, dy: -maxRadius)
            guard extendedBounds.contains(nsPoint) else { continue }

            let windowFrame = NSRect(
                x: nsPoint.x - totalSize / 2,
                y: nsPoint.y - totalSize / 2,
                width: totalSize,
                height: totalSize
            )

            let window = NSWindow(
                contentRect: windowFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let sonarView = SonarView(
                frame: NSRect(origin: .zero, size: windowFrame.size),
                ringCount: ringCount,
                maxRadius: maxRadius
            )
            window.contentView = sonarView

            window.alphaValue = 0
            window.orderFrontRegardless()
            overlayWindows.append(window)

            // Fade in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                window.animator().alphaValue = 1.0
            }
        }

        // Animate the rings expanding using CACurrentMediaTime for state
        animationStart = CACurrentMediaTime()
        let interval = 1.0 / 60.0

        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - self.animationStart
            let progress = CGFloat(min(elapsed / self.animationDuration, 1.0))

            for window in self.overlayWindows {
                (window.contentView as? SonarView)?.progress = progress
                window.contentView?.needsDisplay = true
            }

            if progress >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
            }
        }

        // Auto-dismiss after animation + hold
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        let windows = overlayWindows
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            for window in windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }

    func dismiss() {
        animationTimer?.invalidate()
        animationTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func mouseScreen() -> NSScreen {
        let pos = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.screens[0]
    }
}

// MARK: - Sonar Ring View

private class SonarView: NSView {
    let ringCount: Int
    let maxRadius: CGFloat
    var progress: CGFloat = 0

    init(frame: NSRect, ringCount: Int, maxRadius: CGFloat) {
        self.ringCount = ringCount
        self.maxRadius = maxRadius
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Draw rings from outermost to innermost
        for i in 0..<ringCount {
            let ringDelay = CGFloat(i) * 0.15
            let denom = 1.0 - ringDelay * CGFloat(ringCount - 1) / CGFloat(ringCount)
            let ringProgress = max(0, min(1, (progress - ringDelay) / denom))

            guard ringProgress > 0 else { continue }

            // Ease out cubic
            let eased = 1.0 - pow(1.0 - ringProgress, 3)

            let radius = maxRadius * eased
            let alpha = (1.0 - eased) * 0.8

            // Ring stroke
            ctx.setStrokeColor(NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: alpha).cgColor)
            ctx.setLineWidth(2.5 - CGFloat(i) * 0.5)
            ctx.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.strokePath()
        }

        // Center dot — stays visible
        let dotRadius: CGFloat = 6
        let dotAlpha = max(0.3, 1.0 - progress * 0.5)
        ctx.setFillColor(NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: dotAlpha).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

        // Outer glow on center dot
        ctx.setFillColor(NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: dotAlpha * 0.2).cgColor)
        let glowRadius: CGFloat = 12
        ctx.fillEllipse(in: CGRect(
            x: center.x - glowRadius,
            y: center.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        ))
    }
}
