import AppKit
import CoreGraphics

private enum SpotlightConfig {
    static let overlayAlpha: CGFloat = 0.75
    static let dimAlpha: CGFloat = 0.85
    static let spotlightRadius: CGFloat = 200
    static let sonarDelay: TimeInterval = 1.0
    static let totalDuration: TimeInterval = 2.5
    static let fadeInDuration: TimeInterval = 0.15
    static let fadeOutDuration: TimeInterval = 0.4
    static let accentColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
}

private struct DotMatrixConfig {
    var dotRadius: CGFloat = 2.2
    var dotSpacing: CGFloat = 6.0
    var arrowCols: Int = 13
    var arrowRows: Int = 7   // must be odd

    static let shared: DotMatrixConfig = {
        let path = NSHomeDirectory() + "/.lattices/mouse-finder.json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return DotMatrixConfig() }

        var config = DotMatrixConfig()
        if let v = json["dotRadius"] as? Double { config.dotRadius = CGFloat(v) }
        if let v = json["dotSpacing"] as? Double { config.dotSpacing = CGFloat(v) }
        if let v = json["arrowCols"] as? Int { config.arrowCols = max(3, v) }
        if let v = json["arrowRows"] as? Int { config.arrowRows = max(3, v | 1) }
        return config
    }()

    func generatePattern() -> [(col: Int, row: Int)] {
        let center = arrowRows / 2
        let shaftHalf = center / 2
        var dots: [(Int, Int)] = []

        for r in 0..<arrowRows {
            let d = abs(r - center)
            if d <= shaftHalf {
                for c in 0...(arrowCols - 1 - d) { dots.append((c, r)) }
            } else {
                let headTip = arrowCols - 1 - d
                let headStart = max(0, headTip - 1)
                for c in headStart...headTip { dots.append((c, r)) }
            }
        }
        return dots
    }
}

/// Locates the mouse cursor with a spotlight + sonar pulse effect.
/// Dims all screens, spotlights the cursor area, shows directional arrows on off-screens,
/// then plays sonar rings on top.
final class MouseFinder {
    static let shared = MouseFinder()

    private var overlayWindows: [NSWindow] = []
    private var sonarWindows: [NSWindow] = []
    private var dismissTimer: Timer?
    private var animationTimer: Timer?
    private var sonarDelayTimer: Timer?
    private var animationStart: CFTimeInterval = 0
    private let animationDuration: CFTimeInterval = 1.5
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    // MARK: - Find (highlight current position)

    func find() {
        let pos = NSEvent.mouseLocation
        showSpotlight(at: pos)
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

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: target.x, y: primaryHeight - target.y)
        CGWarpMouseCursorPosition(cgPoint)
        CGAssociateMouseAndMouseCursorPosition(1)

        showSpotlight(at: target)
    }

    // MARK: - Spotlight Effect

    private func showSpotlight(at nsPoint: NSPoint) {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let cursorScreen = screens.first(where: { $0.frame.contains(nsPoint) }) ?? screens[0]
        let otherScreens = screens.filter { $0 !== cursorScreen }
        let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))

        // Spotlight overlay on cursor screen
        let localCursor = NSPoint(
            x: nsPoint.x - cursorScreen.frame.origin.x,
            y: nsPoint.y - cursorScreen.frame.origin.y
        )
        let spotlightWindow = makeOverlayWindow(frame: cursorScreen.frame, level: windowLevel)
        spotlightWindow.contentView = SpotlightView(
            frame: NSRect(origin: .zero, size: cursorScreen.frame.size),
            cursorPoint: localCursor
        )
        overlayWindows.append(spotlightWindow)

        // Dim overlays with directional arrows on other screens
        for screen in otherScreens {
            let screenCenter = NSPoint(
                x: screen.frame.midX,
                y: screen.frame.midY
            )
            let angle = atan2(nsPoint.y - screenCenter.y, nsPoint.x - screenCenter.x)

            let dimWindow = makeOverlayWindow(frame: screen.frame, level: windowLevel)
            dimWindow.contentView = DimOverlayView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                cursorAngle: angle
            )
            overlayWindows.append(dimWindow)
        }

        // Fade all in
        for window in overlayWindows {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = SpotlightConfig.fadeInDuration
                window.animator().alphaValue = 1.0
            }
        }

        installEventMonitors()

        // Start sonar after delay
        sonarDelayTimer = Timer.scheduledTimer(withTimeInterval: SpotlightConfig.sonarDelay, repeats: false) { [weak self] _ in
            self?.showSonar(at: nsPoint)
        }

        // Auto-dismiss
        dismissTimer = Timer.scheduledTimer(withTimeInterval: SpotlightConfig.totalDuration, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    // MARK: - Sonar Animation (plays on top of spotlight)

    private func showSonar(at nsPoint: NSPoint) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let ringCount = 3
        let maxRadius: CGFloat = 120
        let totalSize = maxRadius * 2 + 20
        let sonarLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)

        for screen in screens {
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
            window.level = sonarLevel
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
            sonarWindows.append(window)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                window.animator().alphaValue = 1.0
            }
        }

        animationStart = CACurrentMediaTime()
        let interval = 1.0 / 60.0

        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - self.animationStart
            let progress = CGFloat(min(elapsed / self.animationDuration, 1.0))

            for window in self.sonarWindows {
                (window.contentView as? SonarView)?.progress = progress
                window.contentView?.needsDisplay = true
            }

            if progress >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
            }
        }
    }

    // MARK: - Lifecycle

    private func fadeOut() {
        let allWindows = overlayWindows + sonarWindows
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = SpotlightConfig.fadeOutDuration
            for window in allWindows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }

    func dismiss() {
        removeEventMonitors()
        animationTimer?.invalidate()
        animationTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        sonarDelayTimer?.invalidate()
        sonarDelayTimer = nil
        for window in overlayWindows + sonarWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        sonarWindows.removeAll()
    }

    // MARK: - Event Monitors

    private func installEventMonitors() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] _ in
            self?.dismiss()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            self?.dismiss()
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = globalEventMonitor { NSEvent.removeMonitor(m); globalEventMonitor = nil }
        if let m = localEventMonitor { NSEvent.removeMonitor(m); localEventMonitor = nil }
    }

    // MARK: - Helpers

    private func makeOverlayWindow(frame: NSRect, level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = level
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        return window
    }

    private func mouseScreen() -> NSScreen {
        let pos = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.screens[0]
    }
}

// MARK: - Spotlight View (radial gradient cutout on cursor screen)

private class SpotlightView: NSView {
    let cursorPoint: CGPoint
    private let config = DotMatrixConfig.shared
    private lazy var dotPattern = config.generatePattern()

    init(frame: NSRect, cursorPoint: CGPoint) {
        self.cursorPoint = cursorPoint
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(SpotlightConfig.overlayAlpha).cgColor)
        ctx.fill(bounds)

        // Punch a radial gradient hole using destinationOut blend mode
        ctx.setBlendMode(.destinationOut)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let components: [CGFloat] = [
            1, 1, 1, 1.0,
            1, 1, 1, 0.8,
            1, 1, 1, 0.0,
        ]
        let locations: [CGFloat] = [0.0, 0.3, 1.0]

        guard let gradient = CGGradient(
            colorSpace: colorSpace,
            colorComponents: components,
            locations: locations,
            count: 3
        ) else { return }

        ctx.drawRadialGradient(
            gradient,
            startCenter: cursorPoint,
            startRadius: 0,
            endCenter: cursorPoint,
            endRadius: SpotlightConfig.spotlightRadius,
            options: []
        )

        // Dot matrix arrow at screen center pointing toward cursor
        ctx.setBlendMode(.normal)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let angle = atan2(cursorPoint.y - center.y, cursorPoint.x - center.x)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)

        let originX = -CGFloat(config.arrowCols - 1) * config.dotSpacing / 2
        let originY = -CGFloat(config.arrowRows - 1) * config.dotSpacing / 2

        for (col, row) in dotPattern {
            let x = originX + CGFloat(col) * config.dotSpacing
            let y = originY + CGFloat(row) * config.dotSpacing

            let t = CGFloat(col) / CGFloat(max(1, config.arrowCols - 1))
            let alpha = 0.35 + t * 0.5

            ctx.setFillColor(SpotlightConfig.accentColor.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: x - config.dotRadius,
                y: y - config.dotRadius,
                width: config.dotRadius * 2,
                height: config.dotRadius * 2
            ))
        }

        ctx.restoreGState()
    }
}

// MARK: - Dim Overlay View (dark fill + dot matrix arrow centered on off-screens)

private class DimOverlayView: NSView {
    let cursorAngle: CGFloat
    private let config = DotMatrixConfig.shared
    private lazy var dotPattern = config.generatePattern()

    init(frame: NSRect, cursorAngle: CGFloat) {
        self.cursorAngle = cursorAngle
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(SpotlightConfig.dimAlpha).cgColor)
        ctx.fill(bounds)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: cursorAngle)

        let originX = -CGFloat(config.arrowCols - 1) * config.dotSpacing / 2
        let originY = -CGFloat(config.arrowRows - 1) * config.dotSpacing / 2

        for (col, row) in dotPattern {
            let x = originX + CGFloat(col) * config.dotSpacing
            let y = originY + CGFloat(row) * config.dotSpacing

            let t = CGFloat(col) / CGFloat(max(1, config.arrowCols - 1))
            let alpha = 0.35 + t * 0.5

            ctx.setFillColor(SpotlightConfig.accentColor.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: x - config.dotRadius,
                y: y - config.dotRadius,
                width: config.dotRadius * 2,
                height: config.dotRadius * 2
            ))
        }

        ctx.restoreGState()
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

        for i in 0..<ringCount {
            let ringDelay = CGFloat(i) * 0.15
            let denom = 1.0 - ringDelay * CGFloat(ringCount - 1) / CGFloat(ringCount)
            let ringProgress = max(0, min(1, (progress - ringDelay) / denom))

            guard ringProgress > 0 else { continue }

            let eased = 1.0 - pow(1.0 - ringProgress, 3)
            let radius = maxRadius * eased
            let alpha = (1.0 - eased) * 0.8

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

        let dotRadius: CGFloat = 6
        let dotAlpha = max(0.3, 1.0 - progress * 0.5)
        ctx.setFillColor(NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: dotAlpha).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

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
