import AppKit
import Carbon
import Foundation
import IOKit

struct SecureEventInputDiagnosticSnapshot {
    let enabled: Bool
    let ownerPID: pid_t?
    let ownerName: String?
    let ownerBundleIdentifier: String?

    var traceFields: [String: Any] {
        var fields: [String: Any] = ["secureEventInput": enabled]
        if let ownerPID {
            fields["secureEventInputOwnerPID"] = Int(ownerPID)
        }
        if let ownerName {
            fields["secureEventInputOwnerName"] = ownerName
        }
        if let ownerBundleIdentifier {
            fields["secureEventInputOwnerBundle"] = ownerBundleIdentifier
        }
        return fields
    }

    var ownerDescription: String? {
        guard let ownerPID else { return nil }
        return "\(ownerName ?? ownerBundleIdentifier ?? "unknown") pid=\(ownerPID)"
    }
}

enum SecureEventInputDiagnostics {
    static func snapshot() -> SecureEventInputDiagnosticSnapshot {
        let enabled = IsSecureEventInputEnabled()
        guard enabled, let ownerPID = secureInputOwnerPID() else {
            return SecureEventInputDiagnosticSnapshot(
                enabled: enabled,
                ownerPID: nil,
                ownerName: nil,
                ownerBundleIdentifier: nil
            )
        }

        let application = NSRunningApplication(processIdentifier: ownerPID)
        return SecureEventInputDiagnosticSnapshot(
            enabled: enabled,
            ownerPID: ownerPID,
            ownerName: application?.localizedName,
            ownerBundleIdentifier: application?.bundleIdentifier
        )
    }

    private static func secureInputOwnerPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }

        guard let property = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue(),
            let sessions = property as? [[String: Any]]
        else {
            return nil
        }

        for session in sessions {
            guard let value = session["kCGSSessionSecureInputPID"] as? NSNumber else {
                continue
            }
            let pid = value.int32Value
            if pid > 0 { return pid }
        }
        return nil
    }
}

final class SecureEventInputMonitor {
    static let shared = SecureEventInputMonitor()

    private var timer: Timer?
    private var lastSnapshot = SecureEventInputDiagnostics.snapshot()

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard timer == nil else { return }

        lastSnapshot = SecureEventInputDiagnostics.snapshot()
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
        let snapshot = SecureEventInputDiagnostics.snapshot()
        let enabledChanged = snapshot.enabled != lastSnapshot.enabled
        let ownerChanged = snapshot.enabled && snapshot.ownerPID != lastSnapshot.ownerPID
        guard enabledChanged || ownerChanged else { return }

        lastSnapshot = snapshot
        let state = snapshot.enabled ? "enabled" : "disabled"
        let owner = snapshot.ownerDescription.map { " owner=\($0)" } ?? ""
        let reason = ownerChanged && !enabledChanged
            ? "Secure Event Input owner changed"
            : "Secure Event Input \(state)"
        DiagnosticLog.shared.warn("InputCapture: \(reason)\(owner)")
        HyperKeyDiagnosticRecorder.shared.record(
            kind: "secure_input.changed",
            fields: snapshot.traceFields.merging(["reason": reason]) { _, new in new }
        )
        if enabledChanged {
            InputCaptureResetCenter.reset(reason: reason)
        }
    }
}
