import Foundation

/// Self-healing recovery for session-wide `CGEventTap`s after macOS delivers
/// `tapDisabledByTimeout`.
///
/// Hyper and mouse gestures have worked for months. The regression was not
/// "event taps can't work" — it was (1) keyboard/mouse sharing one run loop
/// so a slow mouse callback stalled keys, and (2) cooldowns of 30–180s (or
/// permanent disable) after a single spike, which took Hyper offline for
/// long stretches after one hitch.
///
/// Policy now:
/// - Re-enable quickly (sub-second → a few seconds) so the feature stays up.
/// - Never permanently kill the tap without the user asking (manual re-arm
///   still clears state; we do not auto-disable forever).
/// - Log trips for diagnosis.
///
/// Thread-safe; `recordTrip()` is safe to call from an event-tap thread.
final class EventTapBreaker {
    enum State: Equatable {
        case armed
        case paused(cooldownSec: Int)
        /// Reserved for explicit user/manual disable — not used for auto-trips.
        case disabled
    }

    private let label: String
    private let trippedWindow: TimeInterval = 600
    /// Brief settle only — restore Hyper/gestures, don't leave them dead.
    private let cooldowns: [TimeInterval] = [0.35, 1.0, 3.0]

    private let lock = NSLock()
    private var tripsInWindow: [Date] = []
    private var pendingRearm: DispatchWorkItem?
    private var _state: State = .armed

    /// Called on the main queue when a cooldown elapses.
    var rearm: (() -> Void)?

    /// Called on the main queue whenever `state` transitions.
    var onStateChanged: ((State) -> Void)?

    init(label: String) {
        self.label = label
    }

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    /// Record that the OS just delivered `.tapDisabledByTimeout`. Schedules a
    /// quick re-enable so Hyper/gestures recover instead of staying off.
    @discardableResult
    func recordTrip() -> Bool {
        lock.lock()

        let now = Date()
        tripsInWindow.removeAll { now.timeIntervalSince($0) > trippedWindow }
        tripsInWindow.append(now)

        let count = tripsInWindow.count
        // Cap at last cooldown; never permanent auto-disable.
        let cooldownIndex = min(count - 1, cooldowns.count - 1)
        let cooldown = cooldowns[cooldownIndex]
        _state = .paused(cooldownSec: max(1, Int(ceil(cooldown))))
        let nextState = _state

        pendingRearm?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.global(qos: .utility).async {
                DiagnosticLog.shared.info("\(self.label): tap auto-recovering")
            }
            self.lock.lock()
            self._state = .armed
            self.lock.unlock()
            self.notifyStateChanged(.armed)
            // rearm may touch CFMachPort — hop main for safety with AppKit-adjacent state.
            DispatchQueue.main.async {
                self.rearm?()
            }
        }
        pendingRearm = work
        lock.unlock()

        let pauseMessage =
            "\(label): tap disabled by OS (trip #\(count)) — recovering in \(String(format: "%.2f", cooldown))s"
        DispatchQueue.global(qos: .utility).async {
            DiagnosticLog.shared.warn(pauseMessage)
        }
        notifyStateChanged(nextState)
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldown, execute: work)
        return false
    }

    /// Clears trip history and any pending cooldown. Caller should re-enable
    /// the tap after this when appropriate.
    func reset() {
        lock.lock()
        let wasNotArmed = _state != .armed
        pendingRearm?.cancel()
        pendingRearm = nil
        tripsInWindow.removeAll()
        _state = .armed
        lock.unlock()
        if wasNotArmed {
            DispatchQueue.global(qos: .utility).async { [label] in
                DiagnosticLog.shared.info("\(label): tap state reset (armed)")
            }
            notifyStateChanged(.armed)
        }
    }

    private func notifyStateChanged(_ newState: State) {
        guard let callback = onStateChanged else { return }
        if Thread.isMainThread {
            callback(newState)
        } else {
            DispatchQueue.main.async { callback(newState) }
        }
    }
}
