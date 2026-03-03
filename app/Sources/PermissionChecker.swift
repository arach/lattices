import AppKit
import SwiftUI
import Combine

final class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()

    @Published var accessibility: Bool = false
    @Published var screenRecording: Bool = false

    private var pollTimer: Timer?
    private var hasLoggedInitial = false

    var allGranted: Bool { accessibility && screenRecording }

    /// Check current permission state, prompting on first launch if not granted.
    func check() {
        let diag = DiagnosticLog.shared

        let ax = AXIsProcessTrusted()
        let sr = CGPreflightScreenCaptureAccess()

        // First check: log identity info and prompt if needed
        if !hasLoggedInitial {
            hasLoggedInitial = true
            let bundleId = Bundle.main.bundleIdentifier ?? "<no bundle id>"
            let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "<unknown>"
            let pid = ProcessInfo.processInfo.processIdentifier
            diag.info("PermissionChecker: bundleId=\(bundleId) pid=\(pid)")
            diag.info("PermissionChecker: exec=\(execPath)")
            diag.info("AXIsProcessTrusted() → \(ax)")
            diag.info("CGPreflightScreenCaptureAccess() → \(sr)")

            // Prompt for missing permissions on first check
            if !ax {
                requestAccessibility()
                return
            }
            if !sr {
                requestScreenRecording()
                return
            }
        }

        // Log on state changes
        if ax != accessibility || sr != screenRecording {
            diag.info("Permissions: Accessibility \(ax ? "✓" : "✗"), Screen Recording \(sr ? "✓" : "✗")")
        }

        accessibility = ax
        screenRecording = sr

        // If not all granted, start polling so we detect changes while user is in Settings.
        // Once all granted, stop polling.
        if allGranted {
            stopPolling()
        } else {
            startPolling()
        }
    }

    /// Request Accessibility permission — shows the system dialog if not yet granted,
    /// which adds lattices to the Accessibility list and asks the user to toggle it on.
    func requestAccessibility() {
        let diag = DiagnosticLog.shared
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
        }
    }

    /// Request Screen Recording permission — triggers the system prompt on first call,
    /// which adds lattices to the Screen Recording list. The user toggles it on in Settings.
    func requestScreenRecording() {
        let diag = DiagnosticLog.shared
        let beforeCheck = CGPreflightScreenCaptureAccess()
        diag.info("requestScreenRecording: before=\(beforeCheck), prompting…")
        let result = CGRequestScreenCaptureAccess()
        diag.info("CGRequestScreenCaptureAccess() → \(result)")
        screenRecording = result
        if !result {
            diag.warn("Screen Recording not granted — opening System Settings. Toggle ON in Privacy → Screen Recording.")
            openScreenRecordingSettings()
            startPolling()
        }
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

    // MARK: - Polling

    /// Poll every 2 seconds to detect permission changes made in System Settings.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.check()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
