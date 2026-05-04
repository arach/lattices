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
    private var lastCapsLayerStaleLogAt: CFAbsoluteTime = 0
    private let breaker = EventTapBreaker(label: "KeyboardRemap")
    private let budgetMeter = TapBudgetMeter(label: "KeyboardRemap")
    private let maxCapsLayerDuration: TimeInterval = 2.0

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
            breaker.recordTrip()
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            // User-driven disable (rare). Re-enable directly, no cooldown.
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        KeyboardRemapStore.shared.reloadIfNeeded()
        guard let rule = KeyboardRemapStore.shared.capsLockRule,
              rule.toIfHeld == .hyper else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged, keyCode == rule.from.keyCode {
            return handleCapsLockFlagsChanged(event, rule: rule)
        }

        clearStaleCapsLayerIfNeeded(now: started)
        guard capsLayerActive else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            capsUsedAsModifier = true
            event.flags = normalizedFlags(event.flags).union(.latticesHyper)
            return Unmanaged.passUnretained(event)
        case .keyUp:
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
            capsLayerActivatedAt = CFAbsoluteTimeGetCurrent()
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
    }

    private func clearStaleCapsLayerIfNeeded(now: CFAbsoluteTime) {
        guard capsLayerActive,
              let activatedAt = capsLayerActivatedAt,
              now - activatedAt > maxCapsLayerDuration else { return }

        clearCapsLayer()
        if now - lastCapsLayerStaleLogAt > 1 {
            lastCapsLayerStaleLogAt = now
            DiagnosticLog.shared.warn("KeyboardRemap: stale Caps Lock layer cleared after \(String(format: "%.1f", maxCapsLayerDuration))s")
        }
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
