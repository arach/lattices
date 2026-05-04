import AppKit
import Combine
import CoreGraphics

final class KeyboardRemapController: ObservableObject {
    static let shared = KeyboardRemapController()

    /// Live state of the event-tap circuit breaker. SettingsView observes
    /// this to surface "paused" / "disabled" status and a re-arm button.
    @Published private(set) var breakerState: EventTapBreaker.State = .armed

    private static let syntheticMarker: Int64 = 0x4C4B524D

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var subscriptions: Set<AnyCancellable> = []
    private var installedObservers = false
    private var capsLayerActive = false
    private var capsUsedAsModifier = false
    private var capsLayerActivatedAt: CFAbsoluteTime?
    private var capsLayerLastEventAt: CFAbsoluteTime?
    private var bypassUntil: CFAbsoluteTime = 0
    private var lastCapsLayerStaleLogAt: CFAbsoluteTime = 0
    private var pressedKeyCodes = Set<Int64>()
    private let breaker = EventTapBreaker(label: "KeyboardRemap")
    private let budgetMeter = TapBudgetMeter(label: "KeyboardRemap")
    private let maxCapsLayerIdleDuration: TimeInterval = 2.0
    private let maxCapsLayerHeldDuration: TimeInterval = 20.0
    private let emergencyBypassDuration: TimeInterval = 3.0

    private init() {
        breaker.onStateChanged = { [weak self] newState in
            self?.breakerState = newState
        }
    }

    /// Re-enable the tap after a breaker trip, clearing trip history.
    /// Settings UI calls this when the user explicitly chooses to recover
    /// from a `disabled` state.
    func reArmAfterBreakerTrip() {
        dispatchPrecondition(condition: .onQueue(.main))
        breaker.reset()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func start() {
        installObserversIfNeeded()
        refresh()
    }

    func stop() {
        removeEventTap()
        clearCapsLayer()
    }

    func resetForSystemInputBoundary(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        clearCapsLayer()
        pressedKeyCodes.removeAll()
        breaker.reset()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            refresh()
        }
        DiagnosticLog.shared.warn("KeyboardRemap: reset for \(reason)")
    }

    private func installObserversIfNeeded() {
        guard !installedObservers else { return }
        installedObservers = true

        Preferences.shared.$keyboardRemapsEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)

        PermissionChecker.shared.$accessibility
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    private func refresh() {
        guard Preferences.shared.keyboardRemapsEnabled,
              PermissionChecker.shared.accessibility else {
            removeEventTap()
            return
        }

        KeyboardRemapStore.shared.ensureConfigFile()
        if eventTap == nil {
            installEventTap()
        } else if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func installEventTap() {
        // Fresh install is a clean slate — drop any stale trip history so
        // the new tap's first failure is judged on its own merits.
        breaker.reset()

        var mask = CGEventMask(0)
        mask |= CGEventMask(1) << CGEventType.keyDown.rawValue
        mask |= CGEventMask(1) << CGEventType.keyUp.rawValue
        mask |= CGEventMask(1) << CGEventType.flagsChanged.rawValue

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let tap else {
            DiagnosticLog.shared.warn("KeyboardRemap: failed to install keyboard event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        if let source {
            EventTapThread.shared.add(source: source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        breaker.rearm = { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        DiagnosticLog.shared.info("KeyboardRemap: keyboard event tap installed")
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            EventTapThread.shared.remove(source: source)
        }
        runLoopSource = nil
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<KeyboardRemapController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
            budgetMeter.record(durationMs: elapsedMs)
        }

        if type == .tapDisabledByTimeout {
            // OS killed the tap because a callback was too slow. Run through
            // the breaker — it backs off in escalating cooldowns rather than
            // re-enabling immediately and getting killed again.
            clearCapsLayer()
            breaker.recordTrip()
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            // User-driven disable (rare). Re-enable directly, no cooldown.
            clearCapsLayer()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        updatePressedKeys(type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode))
        if shouldTriggerEmergencyReset(type: type, event: event) {
            emergencyClear(now: started)
            InputCaptureResetCenter.reset(reason: "keyboard emergency chord")
            return Unmanaged.passUnretained(event)
        }

        if started < bypassUntil {
            return Unmanaged.passUnretained(event)
        }

        KeyboardRemapStore.shared.scheduleReloadCheckIfNeeded()
        guard let rule = KeyboardRemapStore.shared.capsLockRule,
              rule.toIfHeld == .hyper else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged, keyCode == rule.from.keyCode {
            return handleCapsLockFlagsChanged(event, rule: rule)
        }

        reconcileCapsLayer(event: event, type: type, now: started)
        guard capsLayerActive else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            if keyCode == 53 {
                emergencyClear(now: started)
                return Unmanaged.passUnretained(event)
            }
            capsUsedAsModifier = true
            capsLayerLastEventAt = started
            event.flags = normalizedFlags(event.flags).union(.latticesHyper)
            return Unmanaged.passUnretained(event)
        case .keyUp:
            capsLayerLastEventAt = started
            event.flags = normalizedFlags(event.flags).union(.latticesHyper)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleCapsLockFlagsChanged(_ event: CGEvent, rule: KeyboardRemapRule) -> Unmanaged<CGEvent>? {
        let isDown = event.flags.contains(.maskAlphaShift)
        if isDown {
            capsLayerActive = true
            capsUsedAsModifier = false
            let now = CFAbsoluteTimeGetCurrent()
            capsLayerActivatedAt = now
            capsLayerLastEventAt = now
            DiagnosticLog.shared.info("KeyboardRemap: Caps Lock layer active")
        } else {
            let shouldTap = capsLayerActive && !capsUsedAsModifier && rule.toIfAlone == .escape
            clearCapsLayer()
            if shouldTap {
                postKeyTap(keyCode: 53)
            }
            DiagnosticLog.shared.info("KeyboardRemap: Caps Lock layer inactive")
        }

        return nil
    }

    private func clearCapsLayer() {
        capsLayerActive = false
        capsUsedAsModifier = false
        capsLayerActivatedAt = nil
        capsLayerLastEventAt = nil
    }

    private func reconcileCapsLayer(event: CGEvent, type: CGEventType, now: CFAbsoluteTime) {
        guard capsLayerActive else { return }

        // If a release event was dropped, later key events often arrive
        // without the physical Caps flag. Treat that as an input boundary and
        // fail open before rewriting the user's key.
        if type == .keyDown || type == .keyUp,
           !event.flags.contains(.maskAlphaShift) {
            clearCapsLayer(reason: "physical Caps flag cleared", now: now)
            return
        }

        if let lastEventAt = capsLayerLastEventAt,
           now - lastEventAt > maxCapsLayerIdleDuration {
            clearCapsLayer(reason: "idle", now: now)
            return
        }

        if let activatedAt = capsLayerActivatedAt,
           now - activatedAt > maxCapsLayerHeldDuration {
            clearCapsLayer(reason: "held too long", now: now)
        }
    }

    private func clearCapsLayer(reason: String, now: CFAbsoluteTime) {
        clearCapsLayer()
        if now - lastCapsLayerStaleLogAt > 1 {
            lastCapsLayerStaleLogAt = now
            DiagnosticLog.shared.warn("KeyboardRemap: Caps Lock layer cleared (\(reason))")
        }
    }

    private func emergencyClear(now: CFAbsoluteTime) {
        clearCapsLayer()
        pressedKeyCodes.removeAll()
        bypassUntil = now + emergencyBypassDuration
        DiagnosticLog.shared.warn("KeyboardRemap: emergency bypass via Escape")
    }

    private func updatePressedKeys(type: CGEventType, keyCode: Int64) {
        switch type {
        case .keyDown:
            pressedKeyCodes.insert(keyCode)
        case .keyUp:
            pressedKeyCodes.remove(keyCode)
        default:
            break
        }
    }

    private func shouldTriggerEmergencyReset(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        return keyCode == 40
            && pressedKeyCodes.contains(53)
            && flags.contains(.maskShift)
    }

    private func normalizedFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var normalized = flags
        normalized.remove(.maskAlphaShift)
        return normalized
    }

    private func postKeyTap(keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
