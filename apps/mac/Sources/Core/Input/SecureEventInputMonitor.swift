import Carbon
import Foundation

final class SecureEventInputMonitor {
    static let shared = SecureEventInputMonitor()

    private var timer: Timer?
    private var lastEnabled = IsSecureEventInputEnabled()

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard timer == nil else { return }

        lastEnabled = IsSecureEventInputEnabled()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let enabled = IsSecureEventInputEnabled()
        guard enabled != lastEnabled else { return }

        lastEnabled = enabled
        let reason = enabled ? "Secure Event Input enabled" : "Secure Event Input disabled"
        DiagnosticLog.shared.warn("InputCapture: \(reason)")
        InputCaptureResetCenter.reset(reason: reason)
    }
}
