import AppKit
import SwiftUI
import Combine
import ScreenCaptureKit

final class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()

    @Published var accessibility: Bool = false
    @Published var screenRecording: Bool = false
    @Published private(set) var refreshInFlight: Bool = false
    @Published private(set) var lastCheckedAt: Date?

    private var pollTimer: Timer?
    private var burstRefreshTask: Task<Void, Never>?
    private var hasLoggedInitial = false
    private var screenProbeInFlight = false
    private var screenRecordingProbeGrantedUntil: Date?
    private var screenProbeCooldownUntil: Date?
    private static let deniedScreenProbeCooldown: TimeInterval = 20
    private static let successfulScreenProbeTTL: TimeInterval = 8

    var allGranted: Bool { accessibility && screenRecording }

    var isSimulatingMissingPermissions: Bool {
        CommandLine.arguments.contains("--simulate-missing-permissions")
            || UserDefaults.standard.bool(forKey: "permissions.simulateMissing")
    }

    /// Check current permission state without prompting.
    func check(pollIfMissing: Bool = false, probeScreenRecordingIfMissing: Bool = false) {
        let diag = DiagnosticLog.shared
        let now = Date()
        lastCheckedAt = now

        let realAX = AXIsProcessTrusted()
        let realSR = CGPreflightScreenCaptureAccess()
        let simulating = isSimulatingMissingPermissions
        let ax = simulating ? false : realAX
        if realSR {
            screenRecordingProbeGrantedUntil = nil
            screenProbeCooldownUntil = nil
        }
        let hasRecentProbeGrant = screenRecordingProbeGrantedUntil.map { $0 > now } ?? false
        if !realSR && !hasRecentProbeGrant {
            screenRecordingProbeGrantedUntil = nil
        }
        let sr = simulating ? false : (realSR || hasRecentProbeGrant)

        // First check: log identity info only
        if !hasLoggedInitial {
            hasLoggedInitial = true
            let bundleId = Bundle.main.bundleIdentifier ?? "<no bundle id>"
            let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "<unknown>"
            let pid = ProcessInfo.processInfo.processIdentifier
            diag.info("PermissionChecker: bundleId=\(bundleId) pid=\(pid)")
            diag.info("PermissionChecker: exec=\(execPath)")
            diag.info("AXIsProcessTrusted() → \(realAX)")
            diag.info("CGPreflightScreenCaptureAccess() → \(realSR)")
            if simulating {
                diag.warn("PermissionChecker: simulating missing permissions for UX preview")
            }
        }

        // Log on state changes
        if ax != accessibility || sr != screenRecording {
            diag.info("Permissions: Accessibility \(ax ? "✓" : "✗"), Screen Recording \(sr ? "✓" : "✗")")
        }

        accessibility = ax
        screenRecording = sr

        // Only poll after an intentional permission request. A passive launch-time
        // check should not keep nudging macOS privacy state in the background.
        if allGranted {
            stopPolling()
        } else if pollIfMissing {
            startPolling()
        }

        if probeScreenRecordingIfMissing && !sr {
            probeScreenRecordingPermissionIfNeeded()
        }
    }

    func isGranted(_ capability: Capability) -> Bool {
        switch capability {
        case .windowControl:
            return accessibility
        case .screenSearch:
            return screenRecording
        }
    }

    /// Request Accessibility permission — shows the system dialog if not yet granted,
    /// which adds lattices to the Accessibility list and asks the user to toggle it on.
    func requestAccessibility() {
        let diag = DiagnosticLog.shared
        if isSimulatingMissingPermissions {
            diag.warn("requestAccessibility: skipped because missing-permission simulation is enabled")
            accessibility = false
            return
        }
        let beforeCheck = AXIsProcessTrusted()
        diag.info("requestAccessibility: before=\(beforeCheck), prompting…")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(opts)
        diag.info("AXIsProcessTrustedWithOptions(prompt) → \(result)")
        accessibility = result
        if !result {
            diag.warn("Accessibility not granted — opening System Settings. Toggle ON in Privacy → Accessibility.")
            openAccessibilitySettings()
            startPolling()
            schedulePermissionRefresh()
        }
    }

    /// Request Screen Recording permission — triggers the system prompt on first call,
    /// which adds lattices to the Screen Recording list. The user toggles it on in Settings.
    func requestScreenRecording() {
        let diag = DiagnosticLog.shared
        if isSimulatingMissingPermissions {
            diag.warn("requestScreenRecording: skipped because missing-permission simulation is enabled")
            screenRecording = false
            return
        }
        let beforeCheck = CGPreflightScreenCaptureAccess()
        diag.info("requestScreenRecording: before=\(beforeCheck), probing…")
        let requestResult = CGRequestScreenCaptureAccess()
        diag.info("CGRequestScreenCaptureAccess() → \(requestResult)")
        if requestResult {
            screenRecording = true
            stopPolling()
            return
        }

        // On newer macOS releases TCC no longer reliably prompts for screen capture
        // through the legacy CoreGraphics request API. Warm up ScreenCaptureKit first,
        // then fall back to opening System Settings if access is still denied.
        if #available(macOS 15.0, *) {
            NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor [weak self] in
                guard let self else { return }

                let shareableProbe = await self.probeScreenCaptureShareableContent()
                diag.info("ScreenCaptureKit shareable probe → \(shareableProbe)")

                if #available(macOS 15.2, *) {
                    let afterShareable = CGPreflightScreenCaptureAccess()
                    if !afterShareable {
                        let screenshotProbe = await self.probeScreenCaptureScreenshot()
                        diag.info("ScreenCaptureKit screenshot probe → \(screenshotProbe)")
                    }
                }

                let afterCheck = CGPreflightScreenCaptureAccess()
                diag.info("requestScreenRecording: after=\(afterCheck)")
                self.screenRecording = afterCheck

                if !afterCheck {
                    diag.warn("Screen capture not granted — opening System Settings. On newer macOS versions this may require enabling Lattices in Privacy → Screen & System Audio Recording.")
                    self.openScreenRecordingSettings()
                    self.startPolling()
                    self.schedulePermissionRefresh(probeScreenRecording: true)
                }
            }
            return
        }

        diag.info("requestScreenRecording: using legacy CoreGraphics request API")
        let result = CGRequestScreenCaptureAccess()
        diag.info("CGRequestScreenCaptureAccess() → \(result)")
        screenRecording = result
        if !result {
            diag.warn("Screen capture not granted — opening System Settings. Toggle ON in Privacy → Screen Recording.")
            openScreenRecordingSettings()
            startPolling()
            schedulePermissionRefresh(probeScreenRecording: true)
        }
    }

    func openSettings(for capability: Capability) {
        switch capability {
        case .windowControl:
            openAccessibilitySettings()
        case .screenSearch:
            openScreenRecordingSettings()
        }
        passiveRecheck(reason: "open \(capability.requirementLabel)")
    }

    /// Opens System Settings → Privacy & Security → Accessibility
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings → Privacy & Security → Screen Recording
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings → Privacy & Security → Automation.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings → Privacy & Security → Input Monitoring.
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @available(macOS 15.0, *)
    private func probeScreenCaptureShareableContent() async -> String {
        await withCheckedContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
                if let error {
                    continuation.resume(returning: "error \(Self.describe(error))")
                    return
                }

                let windows = content?.windows.count ?? 0
                let displays = content?.displays.count ?? 0
                let apps = content?.applications.count ?? 0
                continuation.resume(returning: "ok windows=\(windows) displays=\(displays) apps=\(apps)")
            }
        }
    }

    @available(macOS 15.2, *)
    private func probeScreenCaptureScreenshot() async -> String {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        return await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { _, error in
                if let error {
                    continuation.resume(returning: "error \(Self.describe(error))")
                } else {
                    continuation.resume(returning: "ok")
                }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.localizedDescription.isEmpty {
            return "\(nsError.domain)#\(nsError.code)"
        }
        return "\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)"
    }

    // MARK: - Polling

    /// Poll every second to detect permission changes made in System Settings.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.check()
            }
        }
    }

    /// Short, eager recheck burst used while the macOS privacy panes are open.
    /// TCC often updates a fraction of a second after the user toggles or drops
    /// an app, so this makes the assistant turn green without a manual reopen.
    func passiveRecheck(reason: String) {
        DiagnosticLog.shared.info("PermissionChecker: passive recheck requested (\(reason))")
        check()
    }

    func recheckNow(reason: String = "manual", probeIfMissing: Bool = true) {
        let diag = DiagnosticLog.shared
        diag.info("PermissionChecker: recheck requested (\(reason))")

        burstRefreshTask?.cancel()
        refreshInFlight = true
        check(pollIfMissing: true, probeScreenRecordingIfMissing: probeIfMissing)
        schedulePermissionRefresh(probeScreenRecording: probeIfMissing)
    }

    func resetSavedApproval(for capability: Capability) {
        let bundleId = Bundle.main.bundleIdentifier ?? LatticesRuntime.releaseBundleIdentifier
        let services = tccServices(for: capability)
        let diag = DiagnosticLog.shared

        diag.info("PermissionChecker: clearing saved \(capability.requirementLabel) row for \(bundleId)")
        burstRefreshTask?.cancel()
        refreshInFlight = true

        switch capability {
        case .windowControl:
            accessibility = false
        case .screenSearch:
            screenRecording = false
            screenRecordingProbeGrantedUntil = nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = services.map { service in
                (service, Self.runTccutilReset(service: service, bundleId: bundleId))
            }

            DispatchQueue.main.async {
                guard let self else { return }

                for (service, result) in results {
                    if result.status == 0 {
                        diag.success("tccutil reset \(service) \(bundleId)")
                    } else {
                        let detail = result.output.isEmpty ? "exit \(result.status)" : result.output
                        diag.warn("tccutil reset \(service) failed: \(detail)")
                    }
                }

                switch capability {
                case .windowControl:
                    self.promptForCurrentAppRegistration(capability)
                case .screenSearch:
                    self.promptForCurrentAppRegistration(capability)
                }

                self.check(
                    pollIfMissing: true,
                    probeScreenRecordingIfMissing: capability == .screenSearch
                )
                self.schedulePermissionRefresh(probeScreenRecording: capability == .screenSearch)
            }
        }
    }

    func schedulePermissionRefresh(probeScreenRecording: Bool = false) {
        burstRefreshTask?.cancel()
        refreshInFlight = true
        let checker = self
        burstRefreshTask = Task { @MainActor in
            defer { checker.refreshInFlight = false }

            let delays: [UInt64] = [
                250_000_000,
                750_000_000,
                1_500_000_000,
                3_000_000_000,
                6_000_000_000,
                10_000_000_000
            ]

            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                checker.check(
                    pollIfMissing: true,
                    probeScreenRecordingIfMissing: probeScreenRecording
                )
            }
        }
    }

    func quitAndRelaunch() {
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = [
            "-c",
            "/bin/sleep 1; /usr/bin/open -n \"\(appURL.path)\""
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        burstRefreshTask?.cancel()
        burstRefreshTask = nil
        refreshInFlight = false
    }

    private func tccServices(for capability: Capability) -> [String] {
        switch capability {
        case .windowControl:
            return ["Accessibility"]
        case .screenSearch:
            return ["ScreenCapture"]
        }
    }

    private func promptForCurrentAppRegistration(_ capability: Capability) {
        let diag = DiagnosticLog.shared

        switch capability {
        case .windowControl:
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            let result = AXIsProcessTrustedWithOptions(options)
            diag.info("AXIsProcessTrustedWithOptions(prompt after reset) → \(result)")
            accessibility = result
            if !result {
                openAccessibilitySettings()
            }

        case .screenSearch:
            let result = CGRequestScreenCaptureAccess()
            diag.info("CGRequestScreenCaptureAccess(after reset) → \(result)")
            screenRecordingProbeGrantedUntil = result
                ? Date().addingTimeInterval(Self.successfulScreenProbeTTL)
                : nil
            screenRecording = result
            if !result {
                openScreenRecordingSettings()
            }
        }
    }

    private func probeScreenRecordingPermissionIfNeeded() {
        guard !screenProbeInFlight else { return }
        guard #available(macOS 15.0, *) else { return }
        guard !isSimulatingMissingPermissions else { return }
        if let cooldownUntil = screenProbeCooldownUntil, cooldownUntil > Date() {
            return
        }

        screenProbeInFlight = true
        screenProbeCooldownUntil = Date().addingTimeInterval(2)
        let diag = DiagnosticLog.shared

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.probeScreenCaptureShareableContent()
            self.screenProbeInFlight = false
            diag.info("ScreenCaptureKit permission recheck probe → \(result)")

            guard result.hasPrefix("ok ") else {
                self.screenRecordingProbeGrantedUntil = nil
                self.screenProbeCooldownUntil = Date().addingTimeInterval(Self.deniedScreenProbeCooldown)
                self.screenRecording = CGPreflightScreenCaptureAccess()
                return
            }

            self.screenProbeCooldownUntil = nil
            self.screenRecordingProbeGrantedUntil = Date().addingTimeInterval(Self.successfulScreenProbeTTL)
            if !self.screenRecording {
                diag.info("Permissions: Accessibility \(self.accessibility ? "✓" : "✗"), Screen Recording ✓")
            }
            self.screenRecording = true
            if self.allGranted {
                self.stopPolling()
            }
        }
    }

    private static func runTccutilReset(service: String, bundleId: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleId]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }
}
