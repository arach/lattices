import AppKit
import CoreGraphics
import QuartzCore

/// A reversible, system-wide spotlight for the frontmost window.
///
/// Focus Mode keeps the target window fully interactive while a cursor-level
/// panel blacks out everything around it. Window geometry is read back after
/// every AX mutation so grid-snapping apps and terminals cannot leave a bright
/// seam between the real window and the cutout.
final class FocusModeController {
    static let shared = FocusModeController()

    private struct Session {
        let application: NSRunningApplication
        let applicationElement: AXUIElement
        let window: AXUIElement
        let originalAXFrame: CGRect
        let screen: NSScreen
    }

    private let topMargin: CGFloat = 40
    private let bottomMargin: CGFloat = 40
    private let horizontalMargin: CGFloat = 40
    private let moveDuration: TimeInterval = 0.28
    private let resizeDuration: TimeInterval = 0.28

    private var session: Session?
    private var overlay: FocusModeOverlayWindow?
    private var animationTimer: Timer?
    private var trackingTimer: Timer?
    private var escapeEventTap: CFMachPort?
    private var escapeRunLoopSource: CFRunLoopSource?
    private var isTransitioning = false

    private init() {}

    var isActive: Bool { session != nil }

    func toggle() {
        isActive ? exit() : enter()
    }

    func enter() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard session == nil, !isTransitioning else { return }
        guard let captured = captureFrontmostWindow() else {
            DiagnosticLog.shared.warn("Focus Mode: no resizable frontmost window")
            return
        }

        session = captured
        isTransitioning = true
        setEnhancedUI(false, for: captured.applicationElement)

        let overlay = FocusModeOverlayWindow(screen: captured.screen)
        self.overlay = overlay
        updateOverlayCutout(for: captured.window)
        overlay.orderFrontRegardless()
        overlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = moveDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlay.animator().alphaValue = 1
        }

        installEscapeCapture()

        let original = captured.originalAXFrame
        let target = focusFrame(for: original, on: captured.screen)
        let centered = CGRect(
            x: target.midX - original.width / 2,
            y: target.midY - original.height / 2,
            width: original.width,
            height: original.height
        )

        animate(window: captured.window, from: original, to: centered, duration: moveDuration) { [weak self] in
            guard let self, self.session != nil else { return }
            self.animate(window: captured.window, from: self.readAXFrame(captured.window) ?? centered, to: target, duration: self.resizeDuration) { [weak self] in
                guard let self else { return }
                self.isTransitioning = false
                self.setEnhancedUI(true, for: captured.applicationElement)
                self.startTracking()
                DiagnosticLog.shared.success("Focus Mode: entered for \(captured.application.localizedName ?? "window")")
            }
        }
    }

    func exit(restoreWindow: Bool = true) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let captured = session else { return }

        session = nil
        isTransitioning = true
        stopTracking()
        removeEscapeCapture()
        animationTimer?.invalidate()
        animationTimer = nil

        guard restoreWindow, let current = readAXFrame(captured.window) else {
            finishExit(captured: captured)
            return
        }

        setEnhancedUI(false, for: captured.applicationElement)
        let original = captured.originalAXFrame
        let originalSizeCentered = CGRect(
            x: current.midX - original.width / 2,
            y: current.midY - original.height / 2,
            width: original.width,
            height: original.height
        )

        animate(window: captured.window, from: current, to: originalSizeCentered, duration: resizeDuration) { [weak self] in
            guard let self else { return }
            let actual = self.readAXFrame(captured.window) ?? originalSizeCentered
            self.fadeOverlayOut(duration: self.moveDuration)
            self.animate(window: captured.window, from: actual, to: original, duration: self.moveDuration) { [weak self] in
                self?.finishExit(captured: captured)
            }
        }
    }

    func resetForTermination() {
        guard let captured = session else { return }
        animationTimer?.invalidate()
        animationTimer = nil
        stopTracking()
        removeEscapeCapture()
        setAXFrame(captured.originalAXFrame, for: captured.window)
        setEnhancedUI(true, for: captured.applicationElement)
        overlay?.orderOut(nil)
        overlay = nil
        session = nil
        isTransitioning = false
    }

    // MARK: - Window capture and geometry

    private func captureFrontmostWindow() -> Session? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              !LatticesRuntime.isLatticesBundleIdentifier(application.bundleIdentifier) else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else {
            return nil
        }

        let window = focusedValue as! AXUIElement
        guard let frame = readAXFrame(window), frame.width > 1, frame.height > 1 else { return nil }
        let screen = screen(containingAXFrame: frame)
        return Session(
            application: application,
            applicationElement: applicationElement,
            window: window,
            originalAXFrame: frame,
            screen: screen
        )
    }

    private func focusFrame(for original: CGRect, on screen: NSScreen) -> CGRect {
        let full = screen.frame
        let width = min(original.width, max(1, full.width - horizontalMargin * 2))
        let height = max(1, full.height - topMargin - bottomMargin)
        let appKitFrame = CGRect(
            x: full.midX - width / 2,
            y: full.minY + bottomMargin,
            width: width,
            height: height
        )
        return axFrame(fromAppKitFrame: appKitFrame)
    }

    private func screen(containingAXFrame frame: CGRect) -> NSScreen {
        let appKitFrame = appKitFrame(fromAXFrame: frame)
        let center = CGPoint(x: appKitFrame.midX, y: appKitFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.screens.min(by: {
                hypot(center.x - $0.frame.midX, center.y - $0.frame.midY)
                    < hypot(center.x - $1.frame.midX, center.y - $1.frame.midY)
            })
            ?? NSScreen.main!
    }

    private func appKitFrame(fromAXFrame frame: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func axFrame(fromAppKitFrame frame: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func readAXFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func setAXFrame(_ frame: CGRect, for window: AXUIElement) {
        var position = frame.origin
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private func setEnhancedUI(_ enabled: Bool, for application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            enabled as CFTypeRef
        )
    }

    // MARK: - Animation and tracking

    private func animate(
        window: AXUIElement,
        from start: CGRect,
        to end: CGRect,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        animationTimer?.invalidate()
        guard duration > 0 else {
            setAXFrame(end, for: window)
            updateOverlayCutout(for: window)
            completion()
            return
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let rawProgress = min(max(elapsed / duration, 0), 1)
            let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
            let frame = CGRect(
                x: start.minX + (end.minX - start.minX) * progress,
                y: start.minY + (end.minY - start.minY) * progress,
                width: start.width + (end.width - start.width) * progress,
                height: start.height + (end.height - start.height) * progress
            )
            self.setAXFrame(frame, for: window)
            self.updateOverlayCutout(for: window)

            if rawProgress >= 1 {
                timer.invalidate()
                self.animationTimer = nil
                completion()
            }
        }
    }

    private func startTracking() {
        stopTracking()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let captured = self.session else { return }
            guard self.readAXFrame(captured.window) != nil else {
                self.exit(restoreWindow: false)
                return
            }
            self.updateOverlayCutout(for: captured.window)
        }
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updateOverlayCutout(for window: AXUIElement) {
        guard let overlay, let frame = readAXFrame(window) else { return }
        let appKitFrame = appKitFrame(fromAXFrame: frame)
        overlay.cutoutFrame = appKitFrame.offsetBy(
            dx: -overlay.screenFrame.minX,
            dy: -overlay.screenFrame.minY
        )
    }

    private func fadeOverlayOut(duration: TimeInterval) {
        guard let overlay else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlay.animator().alphaValue = 0
        }
    }

    private func finishExit(captured: Session) {
        animationTimer?.invalidate()
        animationTimer = nil
        setEnhancedUI(true, for: captured.applicationElement)
        overlay?.orderOut(nil)
        overlay = nil
        isTransitioning = false
        DiagnosticLog.shared.info("Focus Mode: exited")
    }

    // MARK: - Escape capture

    private func installEscapeCapture() {
        removeEscapeCapture()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.escapeEventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            DiagnosticLog.shared.warn("Focus Mode: could not install Escape capture")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        escapeEventTap = tap
        escapeRunLoopSource = source
        if let source { EventTapThread.shared.add(source: source) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEscapeCapture() {
        if let source = escapeRunLoopSource {
            EventTapThread.shared.remove(source: source)
        }
        escapeRunLoopSource = nil
        if let tap = escapeEventTap { CFMachPortInvalidate(tap) }
        escapeEventTap = nil
    }

    private static let escapeEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<FocusModeController>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = controller.escapeEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventKeycode) == 53 else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            DispatchQueue.main.async { controller.exit() }
        }
        return nil
    }
}

private final class FocusModeOverlayWindow: NSPanel {
    let screenFrame: CGRect
    private let backdropView = FocusModeBackdropView(frame: .zero)

    var cutoutFrame: CGRect {
        get { backdropView.cutoutFrame }
        set { backdropView.cutoutFrame = newValue }
    }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        backdropView.frame = NSRect(origin: .zero, size: screen.frame.size)
        backdropView.autoresizingMask = [.width, .height]
        contentView = backdropView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FocusModeBackdropView: NSView {
    var cutoutFrame: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let path = NSBezierPath(rect: bounds)
        let sealedCutout = cutoutFrame.insetBy(dx: 2, dy: 2)
        if sealedCutout.width > 0, sealedCutout.height > 0 {
            path.appendRoundedRect(sealedCutout, xRadius: 24, yRadius: 24)
        }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.92).setFill()
        path.fill()
    }
}
