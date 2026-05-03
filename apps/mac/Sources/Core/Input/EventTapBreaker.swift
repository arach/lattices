import Foundation

/// Self-healing circuit breaker for session-wide `CGEventTap`s.
///
/// macOS disables a tap (`tapDisabledByTimeout`) when its callback exceeds
/// the OS budget. The naive recovery — re-enable and continue — fights the
/// OS in a loop when the underlying cause is still present, and the system
/// input pipeline keeps stuttering.
///
/// This breaker counts trips inside a rolling window and backs off in
/// escalating cooldowns: 30s → 2 min → permanent (until app restart or
/// manual re-arm). During cooldown the tap stays disabled — input flows
/// through the OS without our interference. On cooldown expiry, `rearm`
/// fires on the main queue to re-enable the tap.
///
/// Thread-safe; `recordTrip()` is safe to call from the event-tap thread.
final class EventTapBreaker {
    enum State: Equatable {
        case armed
        case paused(cooldownSec: Int)
        case disabled
    }

    private let label: String
    private let trippedWindow: TimeInterval = 600          // 10 min rolling window
    private let cooldowns: [TimeInterval] = [30, 120]      // trip 1 → 30s, trip 2 → 2 min, trip 3+ → permanent

    private let lock = NSLock()
    private var tripsInWindow: [Date] = []
    private var permanentlyDisabled = false
    private var pendingRearm: DispatchWorkItem?
    private var _state: State = .armed

    /// Called on the main queue when a cooldown elapses. Caller wires this
    /// to `CGEvent.tapEnable(tap:, enable: true)`.
    var rearm: (() -> Void)?

    /// Called on the main queue whenever `state` transitions. UI uses this
    /// to surface "paused" / "disabled" messages and re-enable affordances.
    var onStateChanged: ((State) -> Void)?

    init(label: String) {
        self.label = label
    }

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    /// Record that the OS just delivered `.tapDisabledByTimeout`. Schedules
    /// a re-enable after the appropriate cooldown, or marks the breaker
    /// permanently open after too many trips.
    @discardableResult
    func recordTrip() -> Bool {
        lock.lock()
        if permanentlyDisabled { lock.unlock(); return false }

        let now = Date()
        tripsInWindow.removeAll { now.timeIntervalSince($0) > trippedWindow }
        tripsInWindow.append(now)

        let count = tripsInWindow.count
        if count > cooldowns.count {
            permanentlyDisabled = true
            pendingRearm?.cancel()
            pendingRearm = nil
            _state = .disabled
            lock.unlock()
            DiagnosticLog.shared.error("\(label): tap tripped \(count)× in \(Int(trippedWindow))s — disabled until app restart or manual re-arm")
            notifyStateChanged(.disabled)
            return false
        }

        let cooldown = cooldowns[count - 1]
        _state = .paused(cooldownSec: Int(cooldown))
        let nextState: State = .paused(cooldownSec: Int(cooldown))

        pendingRearm?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DiagnosticLog.shared.info("\(self.label): tap auto-recovering")
            self.lock.lock()
            self._state = .armed
            self.lock.unlock()
            self.notifyStateChanged(.armed)
            self.rearm?()
        }
        pendingRearm = work
        lock.unlock()

        DiagnosticLog.shared.warn("\(label): tap disabled by OS (trip #\(count)) — paused for \(Int(cooldown))s")
        notifyStateChanged(nextState)
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldown, execute: work)
        return false
    }

    /// Clears all trip history and any pending cooldown. Caller should
    /// re-enable the tap after this to actually recover.
    /// Use cases: tap (re)install, manual re-arm from Settings.
    func reset() {
        lock.lock()
        let wasNotArmed = _state != .armed
        pendingRearm?.cancel()
        pendingRearm = nil
        tripsInWindow.removeAll()
        permanentlyDisabled = false
        _state = .armed
        lock.unlock()
        if wasNotArmed {
            DiagnosticLog.shared.info("\(label): tap state reset (armed)")
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
