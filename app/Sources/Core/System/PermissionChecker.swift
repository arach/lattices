import AppKit
import SwiftUI
import Combine
import ScreenCaptureKit

final class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()

    @Published var accessibility: Bool = false
    @Published var screenRecording: Bool = false

    private var pollTimer: Timer?
    private var hasLoggedInitial = false

    var allGranted: Bool { accessibility && screenRecording }

    var isSimulatingMissingPermissions: Bool {
        CommandLine.arguments.contains("--simulate-missing-permissions")
            || UserDefaults.standard.bool(forKey: "permissions.simulateMissing")
    }

    /// Check current permission state without prompting.
    func check(pollIfMissing: Bool = false) {
        let diag = DiagnosticLog.shared

        let realAX = AXIsProcessTrusted()
        let realSR = CGPreflightScreenCaptureAccess()
        let simulating = isSimulatingMissingPermissions
        let ax = simulating ? false : realAX
        let sr = simulating ? false : realSR

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
