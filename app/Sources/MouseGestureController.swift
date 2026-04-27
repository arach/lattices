import AppKit
import Combine
import CoreGraphics

enum MouseGestureDirection: Equatable {
    case left
    case right
    case down
}

final class MouseGestureController {
    static let shared = MouseGestureController()

    private struct GestureOutcome {
        let label: String
        let success: Bool
    }

    private final class GestureSession {
        let startPoint: CGPoint
        let overlay: MouseGestureOverlay
        var currentPoint: CGPoint

        init(startPoint: CGPoint, overlay: MouseGestureOverlay) {
            self.startPoint = startPoint
            self.overlay = overlay
            self.currentPoint = startPoint
        }
    }

    private static let syntheticMarker: Int64 = 0x4C474D47

    private let minimumDistance: CGFloat = 68
    private let axisBias: CGFloat = 1.2
    private let middleButtonNumber: Int64 = 2

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var session: GestureSession?
    private var subscriptions: Set<AnyCancellable> = []
    private var installedObservers = false

    private init() {}

    func start() {
        installObserversIfNeeded()
        refresh()
    }

    func stop() {
        clearSession()
        removeEventTap()
    }

    static func resolveDirection(
        delta: CGPoint,
        threshold: CGFloat = 68,
        axisBias: CGFloat = 1.2
    ) -> MouseGestureDirection? {
        let absX = abs(delta.x)
        let absY = abs(delta.y)
        guard max(absX, absY) >= threshold else { return nil }

        if absX >= absY * axisBias {
            return delta.x >= 0 ? .right : .left
        }

        if absY >= absX * axisBias, delta.y > 0 {
            return .down
        }

        return nil
    }

    private func installObserversIfNeeded() {
        guard !installedObservers else { return }
        installedObservers = true

        Preferences.shared.$mouseGesturesEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)

        PermissionChecker.shared.$accessibility
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    private func refresh() {
        guard Preferences.shared.mouseGesturesEnabled, PermissionChecker.shared.accessibility else {
            clearSession()
            removeEventTap()
            return
        }

        if eventTap == nil {
            installEventTap()
        } else if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func installEventTap() {
        var mask = CGEventMask(0)
        mask |= CGEventMask(1) << CGEventType.otherMouseDown.rawValue
        mask |= CGEventMask(1) << CGEventType.otherMouseDragged.rawValue
        mask |= CGEventMask(1) << CGEventType.otherMouseUp.rawValue

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let tap else {
            DiagnosticLog.shared.warn("MouseGesture: failed to install middle-click event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        DiagnosticLog.shared.info("MouseGesture: middle-click event tap installed")
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<MouseGestureController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.mouseEventButtonNumber) == middleButtonNumber else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .otherMouseDown:
            return handleMouseDown(event)
        case .otherMouseDragged:
            return handleMouseDragged(event)
        case .otherMouseUp:
            return handleMouseUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let point = event.location
        guard let screen = desktopScreen(containing: point) else {
            clearSession()
            return Unmanaged.passUnretained(event)
        }

        clearSession()
        let overlay = MouseGestureOverlay(screen: screen)
        let newSession = GestureSession(startPoint: point, overlay: overlay)
        session = newSession
        overlay.track(origin: point, direction: nil, label: nil)
        return nil
    }

    private func handleMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let session else {
            return Unmanaged.passUnretained(event)
        }

        session.currentPoint = event.location
        let delta = CGPoint(
            x: event.location.x - session.startPoint.x,
            y: event.location.y - session.startPoint.y
        )
        let direction = Self.resolveDirection(delta: delta, threshold: minimumDistance, axisBias: axisBias)

        if let direction {
            session.overlay.track(origin: session.startPoint, direction: direction, label: label(for: direction))
        } else {
            session.overlay.track(origin: session.startPoint, direction: nil, label: nil)
        }

        return nil
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let session else {
            return Unmanaged.passUnretained(event)
        }

        let delta = CGPoint(
            x: event.location.x - session.startPoint.x,
            y: event.location.y - session.startPoint.y
        )
        let direction = Self.resolveDirection(delta: delta, threshold: minimumDistance, axisBias: axisBias)
        self.session = nil

        guard let direction else {
            session.overlay.dismiss()
            replayMiddleClick(at: session.startPoint)
            return nil
        }

        let outcome = performAction(for: direction, startPoint: session.startPoint)
        session.overlay.commit(origin: session.startPoint, direction: direction, label: outcome.label, success: outcome.success)
        return nil
    }

    private func performAction(for direction: MouseGestureDirection, startPoint: CGPoint) -> GestureOutcome {
        switch direction {
        case .left:
            let switched = WindowTiler.switchToAdjacentSpace(offset: -1, from: startPoint)
            return GestureOutcome(label: switched ? "Previous Space" : "No Previous Space", success: switched)
        case .right:
            let switched = WindowTiler.switchToAdjacentSpace(offset: 1, from: startPoint)
            return GestureOutcome(label: switched ? "Next Space" : "No Next Space", success: switched)
        case .down:
            ScreenMapWindowController.shared.showScreenMapOverview()
            return GestureOutcome(label: "Screen Map Overview", success: true)
        }
    }

    private func label(for direction: MouseGestureDirection) -> String {
        switch direction {
        case .left:
            return "Previous Space"
        case .right:
            return "Next Space"
        case .down:
            return "Screen Map Overview"
        }
    }

    private func clearSession() {
        session?.overlay.dismiss(immediately: true)
        session = nil
    }

    private func replayMiddleClick(at point: CGPoint) {
        let events: [CGEventType] = [.otherMouseDown, .otherMouseUp]
        for type in events {
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .center
            ) else { continue }

            event.setIntegerValueField(.mouseEventButtonNumber, value: middleButtonNumber)
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func desktopScreen(containing cgPoint: CGPoint) -> NSScreen? {
        guard let screen = screen(containing: cgPoint) else { return nil }
        guard cgVisibleRect(for: screen).contains(cgPoint) else { return nil }
        guard !hasWindowAtPoint(cgPoint) else { return nil }
        return screen
    }

    private func screen(containing cgPoint: CGPoint) -> NSScreen? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPoint = NSPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
        return NSScreen.screens.first(where: { $0.frame.contains(nsPoint) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func cgVisibleRect(for screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.minX,
            y: primaryHeight - visible.maxY,
            width: visible.width,
            height: visible.height
        )
    }

    private func hasWindowAtPoint(_ point: CGPoint) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for info in windows {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner != "Lattices",
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true
            guard layer == 0, alpha > 0.01, isOnScreen else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            guard rect.width >= 8, rect.height >= 8 else { continue }

            if rect.contains(point) {
                return true
            }
        }

        return false
    }
}

private final class MouseGestureOverlay {
    private let screen: NSScreen
    private let window: NSWindow
    private let overlayView: MouseGestureOverlayView
    private var fadeTimer: Timer?

    init(screen: NSScreen) {
        self.screen = screen
        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.overlayView = MouseGestureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = overlayView
        window.orderFrontRegardless()
    }

    func track(origin: CGPoint, direction: MouseGestureDirection?, label: String?) {
        fadeTimer?.invalidate()
        window.alphaValue = 1
        overlayView.state = .tracking(origin: localPoint(from: origin), direction: direction, label: label)
        overlayView.needsDisplay = true
    }

    func commit(origin: CGPoint, direction: MouseGestureDirection, label: String, success: Bool) {
        fadeTimer?.invalidate()
        window.alphaValue = 1
        overlayView.state = .committed(origin: localPoint(from: origin), direction: direction, label: label, success: success)
        overlayView.needsDisplay = true

        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss(immediately: Bool = false) {
        fadeTimer?.invalidate()
        fadeTimer = nil

        if immediately {
            window.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
        })
    }

    private func localPoint(from cgPoint: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let nsY = primaryHeight - cgPoint.y
        return CGPoint(x: cgPoint.x - screen.frame.minX, y: nsY - screen.frame.minY)
    }
}

private final class MouseGestureOverlayView: NSView {
    enum State {
        case tracking(origin: CGPoint, direction: MouseGestureDirection?, label: String?)
        case committed(origin: CGPoint, direction: MouseGestureDirection, label: String, success: Bool)
    }

    var state: State = .tracking(origin: .zero, direction: nil, label: nil)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        switch state {
        case .tracking(let origin, let direction, let label):
            drawOrigin(at: origin, in: ctx, alpha: 0.88)
            if let direction, let label {
                drawArrow(from: origin, direction: direction, label: label, success: true, committed: false, in: ctx)
            }
        case .committed(let origin, let direction, let label, let success):
            drawOrigin(at: origin, in: ctx, alpha: 1.0)
            drawArrow(from: origin, direction: direction, label: label, success: success, committed: true, in: ctx)
        }
    }

    private func drawOrigin(at point: CGPoint, in ctx: CGContext, alpha: CGFloat) {
        ctx.setFillColor(NSColor(calibratedRed: 0.48, green: 0.76, blue: 1.0, alpha: alpha * 0.18).cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36))

        ctx.setFillColor(NSColor(calibratedRed: 0.62, green: 0.84, blue: 1.0, alpha: alpha * 0.95).cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
    }

    private func drawArrow(
        from origin: CGPoint,
        direction: MouseGestureDirection,
        label: String,
        success: Bool,
        committed: Bool,
        in ctx: CGContext
    ) {
        let length: CGFloat = committed ? 136 : 118
        let vector = arrowVector(for: direction, length: length)
        let end = CGPoint(x: origin.x + vector.x, y: origin.y + vector.y)
        let accent = success
            ? NSColor(calibratedRed: 0.45, green: 0.80, blue: 1.0, alpha: 1.0)
            : NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.42, alpha: 1.0)

        ctx.saveGState()
        ctx.setLineCap(.round)

        let glowPath = CGMutablePath()
        glowPath.move(to: origin)
        glowPath.addLine(to: end)
        ctx.addPath(glowPath)
        ctx.setLineWidth(committed ? 20 : 16)
        ctx.setStrokeColor(accent.withAlphaComponent(committed ? 0.22 : 0.16).cgColor)
        ctx.strokePath()

        let linePath = CGMutablePath()
        linePath.move(to: origin)
        linePath.addLine(to: end)
        ctx.addPath(linePath)
        ctx.setLineWidth(committed ? 7 : 5)
        ctx.setStrokeColor(accent.withAlphaComponent(0.92).cgColor)
        ctx.strokePath()

        drawArrowHead(at: end, direction: direction, color: accent, committed: committed)
        drawLabel(label, near: end, direction: direction, color: accent)
        ctx.restoreGState()
    }

    private func drawArrowHead(at end: CGPoint, direction: MouseGestureDirection, color: NSColor, committed: Bool) {
        let size: CGFloat = committed ? 18 : 15
        let path = NSBezierPath()

        switch direction {
        case .left:
            path.move(to: CGPoint(x: end.x - size, y: end.y))
            path.line(to: CGPoint(x: end.x + size * 0.2, y: end.y + size * 0.72))
            path.line(to: CGPoint(x: end.x + size * 0.2, y: end.y - size * 0.72))
        case .right:
            path.move(to: CGPoint(x: end.x + size, y: end.y))
            path.line(to: CGPoint(x: end.x - size * 0.2, y: end.y + size * 0.72))
            path.line(to: CGPoint(x: end.x - size * 0.2, y: end.y - size * 0.72))
        case .down:
            path.move(to: CGPoint(x: end.x, y: end.y - size))
            path.line(to: CGPoint(x: end.x - size * 0.72, y: end.y + size * 0.2))
            path.line(to: CGPoint(x: end.x + size * 0.72, y: end.y + size * 0.2))
        }

        path.close()
        color.withAlphaComponent(0.96).setFill()
        path.fill()
    }

    private func drawLabel(_ label: String, near end: CGPoint, direction: MouseGestureDirection, color: NSColor) {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        ]
        let attributed = NSAttributedString(string: label, attributes: attributes)
        let textSize = attributed.size()
        let origin = labelOrigin(near: end, direction: direction, textSize: textSize)
        let paddingX: CGFloat = 10
        let paddingY: CGFloat = 6
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: textSize.width + paddingX * 2,
            height: textSize.height + paddingY * 2
        )

        let bg = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.42).setFill()
        bg.fill()

        let border = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        color.withAlphaComponent(0.26).setStroke()
        border.lineWidth = 1
        border.stroke()

        let textRect = CGRect(
            x: rect.minX + paddingX,
            y: rect.minY + paddingY,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
    }

    private func labelOrigin(near end: CGPoint, direction: MouseGestureDirection, textSize: CGSize) -> CGPoint {
        switch direction {
        case .left:
            return CGPoint(x: end.x - textSize.width - 42, y: end.y + 12)
        case .right:
            return CGPoint(x: end.x + 16, y: end.y + 12)
        case .down:
            return CGPoint(x: end.x - textSize.width / 2 - 10, y: end.y - textSize.height - 42)
        }
    }

    private func arrowVector(for direction: MouseGestureDirection, length: CGFloat) -> CGPoint {
        switch direction {
        case .left:
            return CGPoint(x: -length, y: 0)
        case .right:
            return CGPoint(x: length, y: 0)
        case .down:
            return CGPoint(x: 0, y: -length)
        }
    }
}
