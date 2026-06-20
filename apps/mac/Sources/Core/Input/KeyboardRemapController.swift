import AppKit
import Combine
import CoreGraphics
import IOKit.hidsystem

final class KeyboardRemapController: ObservableObject {
    static let shared = KeyboardRemapController()

    /// Live state of the event-tap circuit breaker. SettingsView observes
    /// this to surface "paused" / "disabled" status and a re-arm button.
    @Published private(set) var breakerState: EventTapBreaker.State = .armed
    @Published private(set) var capsLockTransportActive = false

    private static let syntheticMarker: Int64 = 0x4C4B524D

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapLocation: CGEventTapLocation = .cghidEventTap
    private var subscriptions: Set<AnyCancellable> = []
    private var installedObservers = false
    private var capsLayerActive = false
    private var capsUsedAsModifier = false
    private var capsLayerActivatedAt: CFAbsoluteTime?
    private var capsLayerLastEventAt: CFAbsoluteTime?
    private var bypassUntil: CFAbsoluteTime = 0
    private var lastCapsLayerStaleLogAt: CFAbsoluteTime = 0
    private var pressedKeyCodes: [Int64: CFAbsoluteTime] = [:]
    private let capsLockTransport = CapsLockHIDTransportController()
    private let breaker = EventTapBreaker(label: "KeyboardRemap")
    private let budgetMeter = TapBudgetMeter(label: "KeyboardRemap")
    private let maxCapsLayerIdleDuration: TimeInterval = 2.0
    private let maxCapsLayerHeldDuration: TimeInterval = 20.0
    private let maxTrackedKeyDownDuration: TimeInterval = 120.0
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

    @discardableResult
    func clearStuckCapsLockState() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        clearCapsLayer()
        pressedKeyCodes.removeAll()
        bypassUntil = CFAbsoluteTimeGetCurrent() + emergencyBypassDuration
        let cleared = clearCapsLockLatch(reason: "manual settings recovery")
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            refresh()
        }
        DiagnosticLog.shared.warn("KeyboardRemap: manual Caps Lock recovery \(cleared ? "succeeded" : "failed")")
        return cleared
    }

    func start() {
        installObserversIfNeeded()
        refresh()
    }

    func stop() {
        removeEventTap()
        capsLockTransport.disable()
        capsLockTransportActive = capsLockTransport.isActive
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

        KeyboardRemapStore.shared.$config
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
            capsLockTransport.disable()
            capsLockTransportActive = capsLockTransport.isActive
            return
        }

        KeyboardRemapStore.shared.ensureConfigFile()
        let shouldUseCapsLockTransport = KeyboardRemapStore.shared.capsLockRule?.toIfHeld == .hyper
        capsLockTransport.setEnabled(shouldUseCapsLockTransport)
        capsLockTransportActive = capsLockTransport.isActive

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

        let tapCandidates: [(CGEventTapLocation, String)] = [
            (.cghidEventTap, "HID"),
            (.cgSessionEventTap, "session"),
        ]
        var installedLabel = "unknown"
        var installedLocation: CGEventTapLocation = .cghidEventTap
        let tap = tapCandidates.lazy.compactMap { location, label -> CFMachPort? in
            let candidate = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.eventTapCallback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
            if candidate != nil {
                installedLabel = label
                installedLocation = location
            }
            return candidate
        }.first

        guard let tap else {
            DiagnosticLog.shared.warn("KeyboardRemap: failed to install keyboard event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapLocation = installedLocation
        runLoopSource = source

        if let source {
            EventTapThread.shared.add(source: source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        breaker.rearm = { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        DiagnosticLog.shared.info("KeyboardRemap: keyboard event tap installed (\(installedLabel))")
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
        capsLockTransportActive = capsLockTransport.isActive
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

        expireStalePressedKeys(now: started)
        updatePressedKeys(type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode), now: started)
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
        if capsLockTransport.isActive,
           keyCode == CapsLockHIDTransportController.transportKeyCode {
            return handleCapsLockTransportEvent(type: type, event: event, rule: rule)
        }

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
            activateCapsLayer(now: CFAbsoluteTimeGetCurrent())
            releaseCapsLockLatchIfNeeded()
            DiagnosticLog.shared.info("KeyboardRemap: Caps Lock layer active")
        } else {
            let shouldTap = capsLayerActive && !capsUsedAsModifier && rule.toIfAlone == .escape
            clearCapsLayer()
            releaseCapsLockLatchIfNeeded()
            if shouldTap {
                postKeyTap(keyCode: 53)
            }
            DiagnosticLog.shared.info("KeyboardRemap: Caps Lock layer inactive")
        }

        return nil
    }

    private func handleCapsLockTransportEvent(
        type: CGEventType,
        event: CGEvent,
        rule: KeyboardRemapRule
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                activateCapsLayer(now: CFAbsoluteTimeGetCurrent())
                DiagnosticLog.shared.info("KeyboardRemap: Caps Lock transport layer active")
            }
            return nil
        case .keyUp:
            let shouldTap = capsLayerActive && !capsUsedAsModifier && rule.toIfAlone == .escape
            clearCapsLayer()
            if shouldTap {
                postKeyTap(keyCode: 53)
            }
            DiagnosticLog.shared.info("KeyboardRemap: Caps Lock transport layer inactive")
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func activateCapsLayer(now: CFAbsoluteTime) {
        capsLayerActive = true
        capsUsedAsModifier = false
        capsLayerActivatedAt = now
        capsLayerLastEventAt = now
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
        if !capsLockTransport.isActive,
           type == .keyDown || type == .keyUp,
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

    private func updatePressedKeys(type: CGEventType, keyCode: Int64, now: CFAbsoluteTime) {
        switch type {
        case .keyDown:
            pressedKeyCodes[keyCode] = now
        case .keyUp:
            pressedKeyCodes.removeValue(forKey: keyCode)
        default:
            break
        }
    }

    private func expireStalePressedKeys(now: CFAbsoluteTime) {
        let staleKeys = pressedKeyCodes.filter { now - $0.value > maxTrackedKeyDownDuration }.map(\.key)
        guard !staleKeys.isEmpty else { return }
        for keyCode in staleKeys {
            pressedKeyCodes.removeValue(forKey: keyCode)
        }
        DiagnosticLog.shared.warn("KeyboardRemap: cleared stale key-down state for \(staleKeys.count) key(s)")
    }

    private func shouldTriggerEmergencyReset(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        return keyCode == 40
            && pressedKeyCodes[53] != nil
            && flags.contains(.maskShift)
    }

    private func normalizedFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var normalized = flags
        normalized.remove(.maskAlphaShift)
        return normalized
    }

    private func releaseCapsLockLatchIfNeeded() {
        clearCapsLockLatch(reason: "event")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.clearCapsLockLatch(reason: "settle")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            self?.clearCapsLockLatch(reason: "deferred")
        }
    }

    @discardableResult
    private func clearCapsLockLatch(reason: String) -> Bool {
        let result = IOHIDSetModifierLockState(kIOMainPortDefault, Int32(kIOHIDCapsLockState), false)
        if result != kIOReturnSuccess {
            DiagnosticLog.shared.warn("KeyboardRemap: failed to clear Caps Lock latch (\(reason), \(result))")
            return false
        }
        return true
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

private final class CapsLockHIDTransportController {
    static let transportKeyCode: Int64 = 79

    private static let capsLockUsage: Int64 = 0x700000039
    private static let f18Usage: Int64 = 0x70000006D
    private static let ownedDefaultsKey = "keyboardRemaps.capsLockHIDTransportOwned"
    private static let originalMappingsDefaultsKey = "keyboardRemaps.capsLockHIDTransportOriginalMappings"

    private var requested = false
    private(set) var isActive = false
    private var ownsMapping = false
    private var originalMappings: [HIDKeyboardModifierMapping] = []

    func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    private func enable() {
        guard !requested else { return }
        requested = true

        guard let currentMappings = readMappings() else {
            DiagnosticLog.shared.warn("KeyboardRemap: failed to read HID keyboard mappings")
            requested = false
            return
        }

        originalMappings = currentMappings

        if currentMappings.contains(where: { $0.src == Self.capsLockUsage && $0.dst == Self.f18Usage }) {
            isActive = true
            ownsMapping = UserDefaults.standard.bool(forKey: Self.ownedDefaultsKey)
            if ownsMapping {
                originalMappings = restoreOriginalMappings() ?? currentMappings.filter { $0.src != Self.capsLockUsage }
            }
            DiagnosticLog.shared.info("KeyboardRemap: Caps Lock HID transport already active")
            return
        }

        if let existing = currentMappings.first(where: { $0.src == Self.capsLockUsage }) {
            DiagnosticLog.shared.warn("KeyboardRemap: Caps Lock already has HID mapping to \(existing.dst); using legacy event-tap fallback")
            requested = false
            return
        }

        var nextMappings = currentMappings
        nextMappings.append(HIDKeyboardModifierMapping(src: Self.capsLockUsage, dst: Self.f18Usage))

        guard writeMappings(nextMappings) else {
            DiagnosticLog.shared.warn("KeyboardRemap: failed to apply Caps Lock HID transport")
            requested = false
            return
        }

        isActive = true
        ownsMapping = true
        persistOriginalMappings(currentMappings)
        DiagnosticLog.shared.info("KeyboardRemap: Caps Lock mapped to F18 transport")
    }

    func disable() {
        guard requested else { return }
        defer {
            requested = false
            isActive = false
            ownsMapping = false
            originalMappings.removeAll()
        }

        guard ownsMapping else { return }
        if writeMappings(originalMappings) {
            clearPersistedOwnership()
            DiagnosticLog.shared.info("KeyboardRemap: Caps Lock HID transport restored")
        } else {
            DiagnosticLog.shared.warn("KeyboardRemap: failed to restore HID keyboard mappings")
        }
    }

    private func readMappings() -> [HIDKeyboardModifierMapping]? {
        let result = runHIDUtil(arguments: ["property", "--get", "UserKeyMapping"])
        guard result.status == 0 else { return nil }
        return parseMappings(from: result.output)
    }

    private func writeMappings(_ mappings: [HIDKeyboardModifierMapping]) -> Bool {
        let pairs = mappings
            .map { "{\"HIDKeyboardModifierMappingSrc\":\($0.src),\"HIDKeyboardModifierMappingDst\":\($0.dst)}" }
            .joined(separator: ",")
        let payload = "{\"UserKeyMapping\":[\(pairs)]}"
        return runHIDUtil(arguments: ["property", "--set", payload]).status == 0
    }

    private func runHIDUtil(arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private func parseMappings(from output: String) -> [HIDKeyboardModifierMapping] {
        let pattern = #"HIDKeyboardModifierMappingDst\s*=\s*(\d+);\s*HIDKeyboardModifierMappingSrc\s*=\s*(\d+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        return regex.matches(in: output, range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let dstRange = Range(match.range(at: 1), in: output),
                  let srcRange = Range(match.range(at: 2), in: output),
                  let dst = Int64(output[dstRange]),
                  let src = Int64(output[srcRange]) else {
                return nil
            }
            return HIDKeyboardModifierMapping(src: src, dst: dst)
        }
    }

    private func persistOriginalMappings(_ mappings: [HIDKeyboardModifierMapping]) {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        UserDefaults.standard.set(data, forKey: Self.originalMappingsDefaultsKey)
        UserDefaults.standard.set(true, forKey: Self.ownedDefaultsKey)
    }

    private func restoreOriginalMappings() -> [HIDKeyboardModifierMapping]? {
        guard let data = UserDefaults.standard.data(forKey: Self.originalMappingsDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode([HIDKeyboardModifierMapping].self, from: data)
    }

    private func clearPersistedOwnership() {
        UserDefaults.standard.removeObject(forKey: Self.originalMappingsDefaultsKey)
        UserDefaults.standard.set(false, forKey: Self.ownedDefaultsKey)
    }
}

private struct HIDKeyboardModifierMapping: Codable, Equatable {
    var src: Int64
    var dst: Int64
}
