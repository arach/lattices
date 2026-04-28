import AppKit
import Combine
import CoreGraphics

private enum MouseGestureAccessory {
    case mic
}

final class MouseGestureController {
    static let shared = MouseGestureController()

    private struct GestureOutcome {
        let label: String
        let success: Bool
        let accessory: MouseGestureAccessory?
    }

    private final class GestureSession {
        let buttonNumber: Int64
        let startPoint: CGPoint
        let overlay: MouseGestureOverlay
        var currentPoint: CGPoint
        var lockedDirection: MouseGestureDirection?

        init(buttonNumber: Int64, startPoint: CGPoint, overlay: MouseGestureOverlay) {
            self.buttonNumber = buttonNumber
            self.startPoint = startPoint
            self.overlay = overlay
            self.currentPoint = startPoint
            self.lockedDirection = nil
        }
    }

    private static let syntheticMarker: Int64 = 0x4C474D47

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var session: GestureSession?
    private var retainedOverlays: [ObjectIdentifier: MouseGestureOverlay] = [:]
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

        if absY >= absX * axisBias {
            return delta.y >= 0 ? .down : .up
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

        MouseInputEventViewer.shared.$isCaptureActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    private func refresh() {
        let shouldCapture = MouseInputEventViewer.shared.isCaptureActive || Preferences.shared.mouseGesturesEnabled
        guard shouldCapture, PermissionChecker.shared.accessibility else {
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
        mask |= CGEventMask(1) << CGEventType.leftMouseDown.rawValue
        mask |= CGEventMask(1) << CGEventType.leftMouseUp.rawValue
        mask |= CGEventMask(1) << CGEventType.rightMouseDown.rawValue
        mask |= CGEventMask(1) << CGEventType.rightMouseUp.rawValue
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
            DiagnosticLog.shared.warn("MouseGesture: failed to install mouse shortcut event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        DiagnosticLog.shared.info("MouseGesture: mouse shortcut event tap installed")
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

        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
            return handlePassiveMouseButtonEvent(type: type, event: event)
        default:
            break
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        if buttonNumber < 2 {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .otherMouseDown:
            return handleMouseDown(event, buttonNumber: buttonNumber)
        case .otherMouseDragged:
            return handleMouseDragged(event, buttonNumber: buttonNumber)
        case .otherMouseUp:
            return handleMouseUp(event, buttonNumber: buttonNumber)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handlePassiveMouseButtonEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard MouseInputEventViewer.shared.isCaptureActive else {
            return Unmanaged.passUnretained(event)
        }

        let phase: String
        switch type {
        case .leftMouseDown, .rightMouseDown:
            phase = "down"
        case .leftMouseUp, .rightMouseUp:
            phase = "up"
        default:
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let appInfo = currentAppInfo()
        recordObservedEvent(
            phase: phase,
            button: MouseShortcutButton(rawButtonNumber: buttonNumber),
            location: event.location,
            delta: .zero,
            modifiers: event.flags,
            candidate: nil,
            match: nil,
            note: "pass-through primary button",
            appInfo: appInfo
        )
        return Unmanaged.passUnretained(event)
    }

    private func handleMouseDown(_ event: CGEvent, buttonNumber: Int64) -> Unmanaged<CGEvent>? {
        MouseShortcutStore.shared.reloadIfNeeded()
        let point = event.location
        let button = MouseShortcutButton(rawButtonNumber: Int(buttonNumber))
        let appInfo = currentAppInfo()
        let canRecognize = Preferences.shared.mouseGesturesEnabled && MouseShortcutStore.shared.watchedButtonNumbers.contains(buttonNumber)

        guard let screen = screen(containing: point) else {
            DiagnosticLog.shared.info("MouseGesture: ignored click at \(format(point)) (off-screen)")
            recordObservedEvent(
                phase: "down",
                button: button,
                location: point,
                delta: .zero,
                modifiers: event.flags,
                candidate: nil,
                match: nil,
                note: "off-screen",
                appInfo: appInfo
            )
            clearSession()
            return Unmanaged.passUnretained(event)
        }

        guard canRecognize else {
            recordObservedEvent(
                phase: "down",
                button: button,
                location: point,
                delta: .zero,
                modifiers: event.flags,
                candidate: nil,
                match: nil,
                note: "button not mapped",
                appInfo: appInfo
            )
            return Unmanaged.passUnretained(event)
        }

        clearSession()
        let overlay = MouseGestureOverlay(screen: screen)
        overlay.onDismiss = { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            self.releaseOverlay(overlay)
        }
        let newSession = GestureSession(buttonNumber: buttonNumber, startPoint: point, overlay: overlay)
        session = newSession
        DiagnosticLog.shared.info("MouseGesture: began at \(format(point)) button=\(buttonNumber)")
        recordObservedEvent(
            phase: "down",
            button: button,
            location: point,
            delta: .zero,
            modifiers: event.flags,
            candidate: nil,
            match: nil,
            note: "tracking",
            appInfo: appInfo
        )
        return nil
    }

    private func handleMouseDragged(_ event: CGEvent, buttonNumber: Int64) -> Unmanaged<CGEvent>? {
        guard let session else {
            return Unmanaged.passUnretained(event)
        }
        guard session.buttonNumber == buttonNumber else {
            return Unmanaged.passUnretained(event)
        }
        MouseShortcutStore.shared.reloadIfNeeded()

        session.currentPoint = event.location
        let delta = CGPoint(
            x: event.location.x - session.startPoint.x,
            y: event.location.y - session.startPoint.y
        )
        let tuning = MouseShortcutStore.shared.tuning
        let direction = Self.resolveDirection(delta: delta, threshold: tuning.dragThreshold, axisBias: tuning.axisBias)

        if direction != session.lockedDirection {
            session.lockedDirection = direction
            if let direction {
                let button = MouseShortcutButton(rawButtonNumber: Int(buttonNumber))
                let triggerEvent = MouseShortcutTriggerEvent(button: button, kind: .drag, direction: direction, device: nil)
                let match = MouseShortcutStore.shared.match(for: triggerEvent)
                DiagnosticLog.shared.info("MouseGesture: locked \(label(for: direction)) via \(triggerEvent.triggerName)")
                recordObservedEvent(
                    phase: "drag",
                    button: button,
                    location: event.location,
                    delta: delta,
                    modifiers: event.flags,
                    candidate: triggerEvent.triggerName,
                    match: match,
                    note: match == nil ? "no rule" : "candidate",
                    appInfo: currentAppInfo()
                )
            }
        }

        if let direction {
            let dominantDistance = max(abs(delta.x), abs(delta.y))
            let previewProgress = previewProgress(
                dominantDistance: dominantDistance,
                threshold: tuning.dragThreshold
            )
            session.overlay.track(
                origin: session.startPoint,
                direction: direction,
                label: nil,
                progress: previewProgress
            )
        } else {
            session.overlay.track(origin: session.startPoint, direction: nil, label: nil, progress: 0)
        }

        return nil
    }

    private func handleMouseUp(_ event: CGEvent, buttonNumber: Int64) -> Unmanaged<CGEvent>? {
        MouseShortcutStore.shared.reloadIfNeeded()
        let button = MouseShortcutButton(rawButtonNumber: Int(buttonNumber))
        let appInfo = currentAppInfo()

        guard let session else {
            recordObservedEvent(
                phase: "up",
                button: button,
                location: event.location,
                delta: .zero,
                modifiers: event.flags,
                candidate: nil,
                match: nil,
                note: "no active session",
                appInfo: appInfo
            )
            return Unmanaged.passUnretained(event)
        }
        guard session.buttonNumber == buttonNumber else {
            return Unmanaged.passUnretained(event)
        }

        let delta = CGPoint(
            x: event.location.x - session.startPoint.x,
            y: event.location.y - session.startPoint.y
        )
        let tuning = MouseShortcutStore.shared.tuning
        let direction = Self.resolveDirection(delta: delta, threshold: tuning.dragThreshold, axisBias: tuning.axisBias)
        self.session = nil

        guard let direction else {
            DiagnosticLog.shared.info("MouseGesture: released without a gesture at \(format(event.location))")
            recordObservedEvent(
                phase: "up",
                button: button,
                location: event.location,
                delta: delta,
                modifiers: event.flags,
                candidate: nil,
                match: nil,
                note: "replay click",
                appInfo: appInfo
            )
            DispatchQueue.main.async { [weak self] in
                session.overlay.dismiss()
                self?.replayMouseClick(buttonNumber: buttonNumber, at: session.startPoint)
            }
            return nil
        }

        let triggerEvent = MouseShortcutTriggerEvent(button: button, kind: .drag, direction: direction, device: nil)
        let match = MouseShortcutStore.shared.match(for: triggerEvent)
        let dismissBeforeAction = shouldDismissOverlayBeforeAction(match: match)
        if dismissBeforeAction {
            session.overlay.dismiss(immediately: true)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !dismissBeforeAction {
                self.retainOverlay(session.overlay)
            }
            let outcome = self.performAction(match: match, startPoint: session.startPoint)
            DiagnosticLog.shared.info("MouseGesture: \(outcome.label) -> \(outcome.success ? "ok" : "blocked")")
            self.recordObservedEvent(
                phase: "up",
                button: button,
                location: event.location,
                delta: delta,
                modifiers: event.flags,
                candidate: triggerEvent.triggerName,
                match: match,
                note: outcome.success ? "fired" : "blocked",
                appInfo: appInfo
            )
            if !dismissBeforeAction {
                session.overlay.commit(
                    origin: session.startPoint,
                    direction: direction,
                    label: outcome.label,
                    success: outcome.success,
                    accessory: outcome.accessory
                )
            }
        }
        return nil
    }

    private func performAction(match: MouseShortcutMatchResult?, startPoint: CGPoint) -> GestureOutcome {
        guard let match else {
            return GestureOutcome(label: "No Shortcut Assigned", success: false, accessory: nil)
        }

        switch match.action.type {
        case .spacePrevious:
            guard WindowTiler.adjacentSpaceTarget(offset: -1, from: startPoint) != nil else {
                return GestureOutcome(label: "No Previous Space", success: false, accessory: nil)
            }
            let switched = WindowTiler.switchToAdjacentSpace(offset: -1, from: startPoint)
            return GestureOutcome(label: switched ? "Previous Space" : "Previous Space Blocked", success: switched, accessory: nil)
        case .spaceNext:
            guard WindowTiler.adjacentSpaceTarget(offset: 1, from: startPoint) != nil else {
                return GestureOutcome(label: "No Next Space", success: false, accessory: nil)
            }
            let switched = WindowTiler.switchToAdjacentSpace(offset: 1, from: startPoint)
            return GestureOutcome(label: switched ? "Next Space" : "Next Space Blocked", success: switched, accessory: nil)
        case .screenMapToggle:
            ScreenMapWindowController.shared.showScreenMapOverview()
            return GestureOutcome(label: "Screen Map Overview", success: true, accessory: nil)
        case .dictationStart:
            let sent = sendDictationShortcut()
            return GestureOutcome(
                label: sent ? "Dictation" : "Dictation Blocked",
                success: sent,
                accessory: sent ? .mic : nil
            )
        case .shortcutSend:
            let sent = sendShortcut(match.action.shortcut)
            return GestureOutcome(
                label: sent ? match.action.label : "Shortcut Blocked",
                success: sent,
                accessory: nil
            )
        }
    }

    private func label(for direction: MouseGestureDirection) -> String {
        switch direction {
        case .left:
            return "Previous Space"
        case .right:
            return "Next Space"
        case .up:
            return "Up"
        case .down:
            return "Screen Map Overview"
        }
    }

    private func clearSession() {
        session?.overlay.dismiss(immediately: true)
        session = nil
    }

    private func replayMouseClick(buttonNumber: Int64, at point: CGPoint) {
        let events: [CGEventType] = [.otherMouseDown, .otherMouseUp]
        for type in events {
            guard let mouseButton = CGMouseButton(rawValue: UInt32(buttonNumber)) else { continue }
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: mouseButton
            ) else { continue }

            event.setIntegerValueField(CGEventField.mouseEventButtonNumber, value: buttonNumber)
            event.setIntegerValueField(CGEventField.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    private func screen(containing cgPoint: CGPoint) -> NSScreen? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPoint = NSPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
        return NSScreen.screens.first(where: { $0.frame.contains(nsPoint) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func format(_ point: CGPoint) -> String {
        "\(Int(point.x)),\(Int(point.y))"
    }

    private func shouldDismissOverlayBeforeAction(match: MouseShortcutMatchResult?) -> Bool {
        guard let match else { return false }
        switch match.action.type {
        case .spacePrevious, .spaceNext, .screenMapToggle:
            return true
        case .dictationStart, .shortcutSend:
            return false
        }
    }

    private func previewProgress(dominantDistance: CGFloat, threshold: CGFloat) -> CGFloat {
        guard dominantDistance > threshold else { return 0 }
        let overshoot = dominantDistance - threshold
        let normalized = min(1, max(0, overshoot / 90))
        return 0.32 + normalized * 0.68
    }

    private func retainOverlay(_ overlay: MouseGestureOverlay) {
        retainedOverlays[ObjectIdentifier(overlay)] = overlay
    }

    private func releaseOverlay(_ overlay: MouseGestureOverlay) {
        retainedOverlays.removeValue(forKey: ObjectIdentifier(overlay))
    }

    private func currentAppInfo() -> (name: String?, bundleId: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    private func recordObservedEvent(
        phase: String,
        button: MouseShortcutButton,
        location: CGPoint,
        delta: CGPoint,
        modifiers: CGEventFlags,
        candidate: String?,
        match: MouseShortcutMatchResult?,
        note: String?,
        appInfo: (name: String?, bundleId: String?)
    ) {
        guard MouseInputEventViewer.shared.isCaptureActive else { return }
        let sourceState = Int(modifiers.rawValue)
        MouseInputEventViewer.shared.record(
            MouseShortcutObservedEvent(
                timestamp: Date(),
                phase: phase,
                buttonNumber: button.rawButtonNumber,
                location: location,
                delta: delta,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers.rawValue)),
                frontmostAppName: appInfo.name,
                frontmostBundleId: appInfo.bundleId,
                candidateTrigger: candidate,
                device: nil,
                matchedRuleSummary: match?.rule.summary,
                willFire: match != nil,
                note: note.map { "\($0) | flags=\(sourceState)" } ?? "flags=\(sourceState)"
            )
        )
    }

    private func sendShortcut(_ shortcut: MouseShortcutKeyStroke?) -> Bool {
        guard let shortcut else { return false }
        let modifiers = shortcut.modifiers.map(\.appleScriptToken).joined(separator: ", ")
        let command: String

        if let keyCode = shortcut.keyCode {
            command = modifiers.isEmpty
                ? "key code \(keyCode)"
                : "key code \(keyCode) using {\(modifiers)}"
        } else if let key = shortcut.key {
            command = modifiers.isEmpty
                ? "keystroke \"\(key)\""
                : "keystroke \"\(key)\" using {\(modifiers)}"
        } else {
            return false
        }

        let script = """
        tell application "System Events"
            \(command)
        end tell
        return "ok"
        """
        return ProcessQuery.shell(["/usr/bin/osascript", "-e", script]) == "ok"
    }

    private func sendDictationShortcut() -> Bool {
        sendShortcut(
            MouseShortcutKeyStroke(
                key: "a",
                keyCode: nil,
                modifiers: [.command, .shift]
            )
        )
    }
}

private final class MouseGestureOverlay {
    private let committedHoldDuration: TimeInterval = 0.0
    private let fadeDuration: TimeInterval = 0.03
    private let accessoryCommittedHoldDuration: TimeInterval = 0.0
    private let accessoryAnimationDuration: TimeInterval = 0.10

    private let screen: NSScreen
    private let window: NSWindow
    private let overlayView: MouseGestureOverlayView
    private var fadeTimer: Timer?
    var onDismiss: (() -> Void)?

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

    func track(origin: CGPoint, direction: MouseGestureDirection?, label: String?, progress: CGFloat) {
        fadeTimer?.invalidate()
        window.alphaValue = 1
        if let direction {
            overlayView.state = .tracking(
                origin: localPoint(from: origin),
                direction: direction,
                label: label,
                progress: progress
            )
        } else {
            overlayView.state = .idle
        }
        overlayView.needsDisplay = true
    }

    func commit(
        origin: CGPoint,
        direction: MouseGestureDirection,
        label: String,
        success: Bool,
        accessory: MouseGestureAccessory?
    ) {
        fadeTimer?.invalidate()
        window.alphaValue = 1
        overlayView.state = .committed(
            origin: localPoint(from: origin),
            direction: direction,
            label: label,
            success: success,
            accessory: accessory,
            accessoryAnimationDuration: accessoryAnimationDuration
        )
        overlayView.needsDisplay = true

        let postReplayHoldDuration = accessory == nil ? committedHoldDuration : accessoryCommittedHoldDuration
        let totalVisibleDuration = overlayView.replayLeadInDuration + postReplayHoldDuration
        let timer = Timer(timeInterval: totalVisibleDuration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismiss(immediately: Bool = false) {
        fadeTimer?.invalidate()
        fadeTimer = nil

        if immediately {
            window.orderOut(nil)
            finishDismissal()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.finishDismissal()
        })
    }

    private func localPoint(from cgPoint: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let nsY = primaryHeight - cgPoint.y
        return CGPoint(x: cgPoint.x - screen.frame.minX, y: nsY - screen.frame.minY)
    }

    private func finishDismissal() {
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

private final class MouseGestureOverlayView: NSView {
    enum State {
        case idle
        case tracking(origin: CGPoint, direction: MouseGestureDirection?, label: String?, progress: CGFloat)
        case committed(
            origin: CGPoint,
            direction: MouseGestureDirection,
            label: String,
            success: Bool,
            accessory: MouseGestureAccessory?,
            accessoryAnimationDuration: TimeInterval
        )
    }

    var state: State = .idle {
        didSet {
            updateArrowAnimation(from: oldValue, to: state)
            updateAccessoryAnimation()
        }
    }
    private var accessoryAnimationTimer: Timer?
    private var accessoryAnimationStartedAt: Date?
    private var accessoryAnimationDuration: TimeInterval = 0
    private var arrowAnimationTimer: Timer?
    private var arrowAnimationStartedAt: Date?
    private var arrowAnimationDuration: TimeInterval = 0
    private var committedStartProgress: CGFloat = 0
    private var accessoryAnimationDelay: TimeInterval = 0
    private let committedArrowAnimationDuration: TimeInterval = 0.06
    private let arrowAnimationDelay: TimeInterval = 0.012
    private let labelRevealThreshold: CGFloat = 0.8

    var replayLeadInDuration: TimeInterval {
        if committedStartProgress >= labelRevealThreshold {
            return 0
        }
        let remainingProgress = max(0, 1 - committedStartProgress)
        return arrowAnimationDelay + committedArrowAnimationDuration * remainingProgress
    }

    override var isFlipped: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            arrowAnimationTimer?.invalidate()
            arrowAnimationTimer = nil
            accessoryAnimationTimer?.invalidate()
            accessoryAnimationTimer = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        switch state {
        case .idle:
            break
        case .tracking(let origin, let direction, let label, let progress):
            drawOrigin(at: origin, in: ctx, alpha: 0.88)
            if let direction {
                drawArrow(
                    from: origin,
                    direction: direction,
                    label: label,
                    success: true,
                    committed: false,
                    accessory: nil,
                    progressOverride: progress,
                    in: ctx
                )
            }
        case .committed(let origin, let direction, let label, let success, let accessory, _):
            drawOrigin(at: origin, in: ctx, alpha: 1.0)
            drawArrow(from: origin, direction: direction, label: label, success: success, committed: true, accessory: accessory, progressOverride: nil, in: ctx)
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
        label: String?,
        success: Bool,
        committed: Bool,
        accessory: MouseGestureAccessory?,
        progressOverride: CGFloat?,
        in ctx: CGContext
    ) {
        let baseLength: CGFloat = 118
        let arrowProgress = progressOverride ?? currentArrowProgress(committed: committed)
        let clampedProgress = min(1, max(0, arrowProgress))
        let length = baseLength * (committed ? max(0.14, clampedProgress) : (0.34 + 0.66 * clampedProgress))
        let vector = arrowVector(for: direction, length: length)
        let end = CGPoint(x: origin.x + vector.x, y: origin.y + vector.y)
        let accent = success
            ? NSColor(calibratedRed: 0.45, green: 0.80, blue: 1.0, alpha: 1.0)
            : NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.42, alpha: 1.0)
        let strokeAlpha = committed ? 0.92 : (0.48 + 0.44 * clampedProgress)
        let glowAlpha = committed ? 0.2 : (0.08 + 0.08 * clampedProgress)

        ctx.saveGState()
        ctx.setLineCap(.round)

        let glowPath = CGMutablePath()
        glowPath.move(to: origin)
        glowPath.addLine(to: end)
        ctx.addPath(glowPath)
        ctx.setLineWidth(16)
        ctx.setStrokeColor(accent.withAlphaComponent(glowAlpha).cgColor)
        ctx.strokePath()

        let linePath = CGMutablePath()
        linePath.move(to: origin)
        linePath.addLine(to: end)
        ctx.addPath(linePath)
        ctx.setLineWidth(5)
        ctx.setStrokeColor(accent.withAlphaComponent(strokeAlpha).cgColor)
        ctx.strokePath()

        drawArrowHead(at: end, direction: direction, color: accent)
        if let label, (!committed || clampedProgress >= labelRevealThreshold) {
            drawLabel(label, from: origin, to: end, direction: direction, color: accent)
        }
        if committed, let accessory, clampedProgress >= labelRevealThreshold {
            drawAccessory(accessory, from: origin, to: end, direction: direction, color: accent, in: ctx)
        }
        ctx.restoreGState()
    }

    private func drawArrowHead(at end: CGPoint, direction: MouseGestureDirection, color: NSColor) {
        let size: CGFloat = 15
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
        case .up:
            path.move(to: CGPoint(x: end.x, y: end.y + size))
            path.line(to: CGPoint(x: end.x - size * 0.72, y: end.y - size * 0.2))
            path.line(to: CGPoint(x: end.x + size * 0.72, y: end.y - size * 0.2))
        case .down:
            path.move(to: CGPoint(x: end.x, y: end.y - size))
            path.line(to: CGPoint(x: end.x - size * 0.72, y: end.y + size * 0.2))
            path.line(to: CGPoint(x: end.x + size * 0.72, y: end.y + size * 0.2))
        }

        path.close()
        color.withAlphaComponent(0.96).setFill()
        path.fill()
    }

    private func drawLabel(_ label: String, from origin: CGPoint, to end: CGPoint, direction: MouseGestureDirection, color: NSColor) {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        ]
        let attributed = NSAttributedString(string: label, attributes: attributes)
        let textSize = attributed.size()
        let paddingX: CGFloat = 10
        let paddingY: CGFloat = 6
        let bubbleSize = CGSize(
            width: textSize.width + paddingX * 2,
            height: textSize.height + paddingY * 2
        )
        let bubbleOrigin = labelOrigin(from: origin, to: end, direction: direction, bubbleSize: bubbleSize)
        let rect = CGRect(
            x: bubbleOrigin.x,
            y: bubbleOrigin.y,
            width: bubbleSize.width,
            height: bubbleSize.height
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

    private func labelOrigin(from origin: CGPoint, to end: CGPoint, direction: MouseGestureDirection, bubbleSize: CGSize) -> CGPoint {
        let midpoint = CGPoint(x: (origin.x + end.x) / 2, y: (origin.y + end.y) / 2)
        let proposedOrigin: CGPoint

        switch direction {
        case .left, .right:
            proposedOrigin = CGPoint(x: midpoint.x - bubbleSize.width / 2, y: midpoint.y + 18)
        case .up, .down:
            proposedOrigin = CGPoint(x: midpoint.x + 20, y: midpoint.y - bubbleSize.height / 2)
        }

        let minX: CGFloat = 12
        let minY: CGFloat = 12
        let maxX = max(minX, bounds.width - bubbleSize.width - 12)
        let maxY = max(minY, bounds.height - bubbleSize.height - 12)

        return CGPoint(
            x: min(max(proposedOrigin.x, minX), maxX),
            y: min(max(proposedOrigin.y, minY), maxY)
        )
    }

    private func arrowVector(for direction: MouseGestureDirection, length: CGFloat) -> CGPoint {
        switch direction {
        case .left:
            return CGPoint(x: -length, y: 0)
        case .right:
            return CGPoint(x: length, y: 0)
        case .up:
            return CGPoint(x: 0, y: length)
        case .down:
            return CGPoint(x: 0, y: -length)
        }
    }

    private func updateArrowAnimation(from oldState: State, to newState: State) {
        let oldDirection = stateDirection(from: oldState)
        let newDirection = stateDirection(from: newState)
        let oldCommitted = isCommitted(state: oldState)
        let newCommitted = isCommitted(state: newState)

        if newCommitted, newDirection != nil {
            let shouldRestart = oldDirection != newDirection || !oldCommitted
            if shouldRestart {
                let previousProgress = trackingProgress(from: oldState)
                committedStartProgress = max(0, min(1, previousProgress ?? 0))
                if committedStartProgress >= 0.94 {
                    arrowAnimationTimer?.invalidate()
                    arrowAnimationTimer = nil
                    arrowAnimationStartedAt = nil
                    arrowAnimationDuration = 0
                    committedStartProgress = 1
                } else {
                    startArrowAnimation(duration: committedArrowAnimationDuration)
                }
            }
            return
        }

        arrowAnimationTimer?.invalidate()
        arrowAnimationTimer = nil
        arrowAnimationStartedAt = nil
        arrowAnimationDuration = 0
        committedStartProgress = 0
    }

    private func startArrowAnimation(duration: TimeInterval) {
        arrowAnimationTimer?.invalidate()
        arrowAnimationStartedAt = Date()
        arrowAnimationDuration = duration

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.needsDisplay = true
            let elapsed = Date().timeIntervalSince(self.arrowAnimationStartedAt ?? Date())
            if elapsed >= self.replayLeadInDuration {
                timer.invalidate()
                self.arrowAnimationTimer = nil
            }
        }
        arrowAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func currentArrowProgress(committed: Bool) -> CGFloat {
        guard committed,
              let startedAt = arrowAnimationStartedAt,
              arrowAnimationDuration > 0 else {
            return committed ? (committedStartProgress > 0 ? committedStartProgress : 1) : 1
        }

        let delayedElapsed = Date().timeIntervalSince(startedAt) - arrowAnimationDelay
        guard delayedElapsed > 0 else { return committedStartProgress }
        let normalized = min(1, max(0, delayedElapsed / arrowAnimationDuration))
        let animated = easeOut(normalized)
        return committedStartProgress + (1 - committedStartProgress) * animated
    }

    private func updateAccessoryAnimation() {
        accessoryAnimationTimer?.invalidate()
        accessoryAnimationTimer = nil
        accessoryAnimationStartedAt = nil
        accessoryAnimationDuration = 0
        accessoryAnimationDelay = 0

        if case .committed(_, _, _, _, let accessory, let duration) = state, accessory != nil {
            accessoryAnimationStartedAt = Date()
            accessoryAnimationDuration = duration
            accessoryAnimationDelay = replayLeadInDuration * 0.86
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.needsDisplay = true
                let elapsed = Date().timeIntervalSince(self.accessoryAnimationStartedAt ?? Date())
                if elapsed >= self.accessoryAnimationDelay + self.accessoryAnimationDuration {
                    timer.invalidate()
                    self.accessoryAnimationTimer = nil
                }
            }
            accessoryAnimationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func drawAccessory(
        _ accessory: MouseGestureAccessory,
        from origin: CGPoint,
        to end: CGPoint,
        direction: MouseGestureDirection,
        color: NSColor,
        in ctx: CGContext
    ) {
        guard let startedAt = accessoryAnimationStartedAt, accessoryAnimationDuration > 0 else { return }
        let delayedElapsed = Date().timeIntervalSince(startedAt) - accessoryAnimationDelay
        guard delayedElapsed > 0 else { return }
        let progress = min(1, max(0, delayedElapsed / accessoryAnimationDuration))
        let scale = 0.82 + 0.18 * easeOut(progress)
        let fadeStart: CGFloat = 0.58
        let alphaProgress = progress <= fadeStart ? 1 : 1 - ((progress - fadeStart) / (1 - fadeStart))
        let alpha = max(0, min(1, alphaProgress))
        guard alpha > 0 else { return }

        let center = accessoryCenter(from: end, direction: direction)
        let badgeDiameter: CGFloat = 34 * scale
        let badgeRect = CGRect(
            x: center.x - badgeDiameter / 2,
            y: center.y - badgeDiameter / 2,
            width: badgeDiameter,
            height: badgeDiameter
        )

        let badge = NSBezierPath(ovalIn: badgeRect)
        NSColor.black.withAlphaComponent(0.46 * alpha).setFill()
        badge.fill()

        color.withAlphaComponent(0.32 * alpha).setStroke()
        badge.lineWidth = 1
        badge.stroke()

        switch accessory {
        case .mic:
            drawMicGlyph(in: badgeRect.insetBy(dx: badgeDiameter * 0.26, dy: badgeDiameter * 0.2), color: color.withAlphaComponent(0.96 * alpha), in: ctx)
        }
    }

    private func accessoryCenter(from end: CGPoint, direction: MouseGestureDirection) -> CGPoint {
        switch direction {
        case .up:
            return CGPoint(x: end.x, y: end.y + 34)
        case .down:
            return CGPoint(x: end.x, y: end.y - 34)
        case .left:
            return CGPoint(x: end.x - 34, y: end.y)
        case .right:
            return CGPoint(x: end.x + 34, y: end.y)
        }
    }

    private func drawMicGlyph(in rect: CGRect, color: NSColor, in ctx: CGContext) {
        ctx.saveGState()
        color.setStroke()
        color.withAlphaComponent(0.22).setFill()

        let bodyWidth = rect.width * 0.42
        let bodyHeight = rect.height * 0.54
        let bodyRect = CGRect(
            x: rect.midX - bodyWidth / 2,
            y: rect.maxY - bodyHeight,
            width: bodyWidth,
            height: bodyHeight
        )
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: bodyWidth / 2, yRadius: bodyWidth / 2)
        body.lineWidth = 1.6
        body.fill()
        body.stroke()

        let stem = NSBezierPath()
        stem.move(to: CGPoint(x: rect.midX, y: bodyRect.minY))
        stem.line(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.24))
        stem.lineWidth = 1.8
        stem.lineCapStyle = .round
        stem.stroke()

        let arcRect = CGRect(
            x: rect.midX - rect.width * 0.28,
            y: rect.minY + rect.height * 0.18,
            width: rect.width * 0.56,
            height: rect.height * 0.42
        )
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: CGPoint(x: arcRect.midX, y: arcRect.midY + arcRect.height * 0.08),
            radius: arcRect.width / 2,
            startAngle: 200,
            endAngle: -20,
            clockwise: true
        )
        arc.lineWidth = 1.6
        arc.lineCapStyle = .round
        arc.stroke()

        let base = NSBezierPath()
        base.move(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.minY + rect.height * 0.14))
        base.line(to: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.minY + rect.height * 0.14))
        base.lineWidth = 1.6
        base.lineCapStyle = .round
        base.stroke()
        ctx.restoreGState()
    }

    private func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    private func stateDirection(from state: State) -> MouseGestureDirection? {
        switch state {
        case .idle:
            return nil
        case .tracking(_, let direction, _, _):
            return direction
        case .committed(_, let direction, _, _, _, _):
            return direction
        }
    }

    private func isCommitted(state: State) -> Bool {
        if case .committed = state {
            return true
        }
        return false
    }

    private func trackingProgress(from state: State) -> CGFloat? {
        if case .tracking(_, _, _, let progress) = state {
            return progress
        }
        return nil
    }
}
