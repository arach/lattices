import Foundation

/// Self-healing circuit breaker for session-wide `CGEventTap`s.
///
/// macOS disables a tap (`tapDisabledByTimeout`) when its callback exceeds
/// the OS budget. The naive recovery — re-enable and continue — fights the
/// OS in a loop when the underlying cause is still present, and the system
/// input pipeline keeps stuttering.
///
/// This breaker counts trips inside a rolling window and backs off in
/// escalating cooldowns: 30s → 2 min → permanent (until app restart).
/// During cooldown the tap stays disabled — input flows through the OS
/// without our interference. On cooldown expiry, `rearm` fires on the main
/// queue to re-enable the tap.
///
/// Thread-safe; `recordTrip()` is safe to call from the event-tap thread.
final class EventTapBreaker {
    private let label: String
    private let trippedWindow: TimeInterval = 600          // 10 min
    private let cooldowns: [TimeInterval] = [30, 120]      // trip 1 → 30s, trip 2 → 2 min, trip 3+ → permanent

    private let lock = NSLock()
    private var tripsInWindow: [Date] = []
    private var permanentlyDisabled = false
    private var pendingRearm: DispatchWorkItem?

    /// Called on the main queue when a cooldown elapses. Caller wires this
    /// to `CGEvent.tapEnable(tap:, enable: true)`.
    var rearm: (() -> Void)?

    init(label: String) {
        self.label = label
    }

    /// Record that the OS just delivered `.tapDisabledByTimeout`. Schedules
    /// a re-enable after the appropriate cooldown, or marks the breaker
    /// permanently open after too many trips.
    ///
    /// Returns `true` if the caller should re-enable the tap immediately
    /// (always `false` once we're on a cooldown path — keeping it false
    /// is what stops the re-enable loop).
    @discardableResult
    func recordTrip() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if permanentlyDisabled { return false }

        let now = Date()
        tripsInWindow.removeAll { now.timeIntervalSince($0) > trippedWindow }
        tripsInWindow.append(now)

        let count = tripsInWindow.count
        if count > cooldowns.count {
            permanentlyDisabled = true
            pendingRearm?.cancel()
            pendingRearm = nil
            DiagnosticLog.shared.error("\(label): tap tripped \(count)× in \(Int(trippedWindow))s — disabled until app restart")
            return false
        }

        let cooldown = cooldowns[count - 1]
        DiagnosticLog.shared.warn("\(label): tap disabled by OS (trip #\(count)) — paused for \(Int(cooldown))s")

        pendingRearm?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DiagnosticLog.shared.info("\(self.label): tap auto-recovering")
            self.rearm?()
        }
        pendingRearm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldown, execute: work)
        return false
    }

    var isPermanentlyDisabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return permanentlyDisabled
    }
}
