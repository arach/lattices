import Foundation

/// Measures CGEventTap callback duration and logs throttled warnings when
/// callbacks exceed the budget. Thread-safe — designed to be invoked from
/// the event-tap thread on every event.
///
/// Logging is throttled to at most one warning per second per meter, with
/// the peak value observed in that window. This keeps the log readable
/// when something is misbehaving without losing the signal.
///
/// Why this exists: the whole point of the EventTapThread off-main move is
/// "tap callbacks are now fast." This is the measurement that confirms it
/// stays true and surfaces regressions before they cause `tapDisabledByTimeout`.
final class TapBudgetMeter {
    private let label: String
    private let warnThresholdMs: Double
    private let throttleSec: TimeInterval

    private let lock = NSLock()
    private var maxMsInWindow: Double = 0
    private var samplesInWindow: Int = 0
    private var lastLog: Date = .distantPast

    init(label: String, warnThresholdMs: Double = 5.0, throttleSec: TimeInterval = 1.0) {
        self.label = label
        self.warnThresholdMs = warnThresholdMs
        self.throttleSec = throttleSec
    }

    /// Records one callback's wall-clock duration. No-op when below the
    /// threshold. Logs at most once per `throttleSec` window.
    func record(durationMs: Double) {
        guard durationMs > warnThresholdMs else { return }

        lock.lock()
        if durationMs > maxMsInWindow { maxMsInWindow = durationMs }
        samplesInWindow += 1

        let now = Date()
        guard now.timeIntervalSince(lastLog) > throttleSec else {
            lock.unlock()
            return
        }

        let peak = maxMsInWindow
        let count = samplesInWindow
        maxMsInWindow = 0
        samplesInWindow = 0
        lastLog = now
        lock.unlock()

        DiagnosticLog.shared.warn(
            "\(label): tap callback peak \(Int(peak))ms (× \(count) over threshold \(Int(warnThresholdMs))ms in last \(Int(throttleSec))s)"
        )
    }
}
