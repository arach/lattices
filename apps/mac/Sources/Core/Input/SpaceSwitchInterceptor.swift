import AppKit
import Combine
import CoreGraphics

/// Intercepts Ctrl+← / Ctrl+→ before Mission Control sees them and routes the
/// press through `WindowTiler.switchToAdjacentSpace` — the SkyLight path that
/// swaps the Space instantly instead of playing the slide animation. A small
/// `SpaceSwitchBezel` pill confirms the move.
///
/// The keydown is swallowed at the HID event tap. Hardware presses also reach
/// Mission Control's symbolic hotkey ahead of the tap, so
/// `SpaceSwitchHotkeys` unregisters that binding while this feature is on —
/// without it the slide animation still plays on top of the instant switch.
/// If the SkyLight request misses on a single-display setup,
/// `WindowTiler` re-posts the same chord tagged with
/// `spaceShortcutSyntheticMarker` — we let those through so the native
/// animated switch still happens as a fallback.
///
/// Only bare Ctrl+arrows are claimed: Ctrl+Opt+arrows stay owned by tiling and
/// Hyper/Cmd/Shift chords pass straight through.
final class SpaceSwitchInterceptor: ObservableObject {
    static let shared = SpaceSwitchInterceptor()

    /// Live breaker state for the settings surface.
    @Published private(set) var breakerState: EventTapBreaker.State = .armed

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var subscriptions: Set<AnyCancellable> = []
    private var installedObservers = false
    private let breaker = EventTapBreaker(label: "SpaceSwitch")
    /// Serializes the actual Space swap. `switchToSpace` can poll the CGS
    /// display list for ~0.45s on a miss — that must never run on the tap
    /// thread or on main.
    private let switchQueue = DispatchQueue(label: "dev.lattices.space-switch", qos: .userInitiated)

    private init() {
        breaker.onStateChanged = { [weak self] newState in
            self?.breakerState = newState
        }
    }

    func start() {
        installObserversIfNeeded()
        refresh()
    }

    func stop() {
        removeEventTap()
        SpaceSwitchHotkeys.restore()
    }

    func resetForSystemInputBoundary(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch breaker.state {
        case .armed:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                refresh()
            }
        case .paused, .disabled:
            return
        }
        DiagnosticLog.shared.warn("SpaceSwitch: reset for \(reason)")
    }

    /// Re-enable the tap after a breaker trip, clearing trip history.
    func reArmAfterBreakerTrip() {
        dispatchPrecondition(condition: .onQueue(.main))
        breaker.reset()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func installObserversIfNeeded() {
        guard !installedObservers else { return }
        installedObservers = true

        Preferences.shared.$spaceSwitchKeysEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)

        PermissionChecker.shared.$accessibility
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    private func refresh() {
        guard Preferences.shared.spaceSwitchKeysEnabled,
              PermissionChecker.shared.accessibility else {
            removeEventTap()
            SpaceSwitchHotkeys.restore()
            return
        }

        SpaceSwitchHotkeys.disable()

        switch breaker.state {
        case .paused, .disabled:
            return
        case .armed:
            break
        }

        if eventTap == nil {
            installEventTap()
        } else if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func installEventTap() {
        breaker.reset()

        var mask = CGEventMask(0)
        mask |= CGEventMask(1) << CGEventType.keyDown.rawValue
        mask |= CGEventMask(1) << CGEventType.keyUp.rawValue

        // HID first — that is the only insertion point that reliably beats the
        // Mission Control symbolic hotkey. Session is a degraded fallback.
        let tapCandidates: [(CGEventTapLocation, String)] = [
            (.cghidEventTap, "HID"),
            (.cgSessionEventTap, "session"),
        ]
        var installedLabel = "unknown"
        let tap = tapCandidates.lazy.compactMap { location, label -> CFMachPort? in
            let candidate = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.eventTapCallback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
            if candidate != nil { installedLabel = label }
            return candidate
        }.first

        guard let tap else {
            DiagnosticLog.shared.warn("SpaceSwitch: failed to install keyboard event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        if let source {
            EventTapThread.overlay.add(source: source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        breaker.rearm = { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        DiagnosticLog.shared.info("SpaceSwitch: keyboard event tap installed (\(installedLabel))")
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            EventTapThread.overlay.remove(source: source)
        }
        runLoopSource = nil
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<SpaceSwitchInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        return interceptor.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Same contract as KeyboardRemap: the common path does no locking,
        // logging, or store reads — a few ms here stalls all keyboard input.
        if type == .tapDisabledByTimeout {
            breaker.recordTrip()
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Our own re-posted fallback chord and synthetic keys from the remap
        // layer pass straight through.
        if event.getIntegerValueField(.eventSourceUserData) == WindowTiler.spaceShortcutSyntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 123 || keyCode == 124 else {
            return Unmanaged.passUnretained(event)
        }

        // Bare Ctrl only. Ctrl+Opt is the tiling chord; Cmd/Shift combos are
        // someone else's shortcut. maskSecondaryFn/maskNumericPad are NOT
        // rejected — real arrow keys carry them (nav cluster shares the Fn
        // layer), so filtering them out would ignore every genuine press.
        let flags = event.flags
        guard flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift) else {
            return Unmanaged.passUnretained(event)
        }

        // Swallow both halves of the press so Mission Control never sees it.
        if type == .keyDown {
            let offset = keyCode == 123 ? -1 : 1
            // Keyboard events normally carry the cursor location; if one
            // arrives empty, nil falls through to the live mouse position.
            let point = event.location
            switchQueue.async { [weak self] in
                self?.performSwitch(offset: offset, point: point == .zero ? nil : point)
            }
        }
        return nil
    }

    private func performSwitch(offset: Int, point: CGPoint?) {
        let outcome = WindowTiler.switchToAdjacentSpaceWithOutcome(offset: offset, from: point)

        // A real miss (target existed but neither path got there) stays quiet —
        // the diagnostic log has the detail. An edge bump still gets the bezel,
        // dimmed, mirroring the mouse gesture's "No Next Space" label.
        guard outcome.switched || outcome.target == nil else { return }

        DispatchQueue.main.async {
            let screen = NSScreen.screens.indices.contains(outcome.displayIndex)
                ? NSScreen.screens[outcome.displayIndex]
                : NSScreen.main
            SpaceSwitchBezel.shared.show(
                direction: offset,
                targetIndex: outcome.switched ? outcome.target?.index : nil,
                currentIndex: outcome.currentIndex,
                total: outcome.totalSpaces,
                on: screen
            )
        }
    }
}
