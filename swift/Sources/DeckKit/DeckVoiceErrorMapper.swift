import Foundation

/// Maps Mac voice-runtime strings onto the shared `DeckVoiceError` model.
/// Pure logic — safe to unit test without the macOS app target.
public enum DeckVoiceErrorMapper {
    public static func resolve(
        phase: DeckVoicePhase,
        executionResult: String?,
        executionError: String?,
        providerError: String?,
        isWarmingUp: Bool
    ) -> DeckVoiceError? {
        if isWarmingUp || isProgressMessage(executionResult) {
            return nil
        }

        if let executionError, !executionError.isEmpty {
            return map(message: executionError, detail: executionError)
        }

        if let providerError, !providerError.isEmpty, phase == .idle {
            return map(message: providerError, detail: providerError)
        }

        if let result = normalized(executionResult), isErrorMessage(result) {
            return map(message: result, detail: result)
        }

        return nil
    }

    public static func isProgressMessage(_ value: String?) -> Bool {
        guard let value = normalized(value) else { return false }
        switch value {
        case "Connecting to voice runtime...",
             "Transcribing...",
             "thinking...",
             "fixing...":
            return true
        default:
            return false
        }
    }

    public static func isErrorMessage(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("couldn't run:") { return true }
        if lower.hasPrefix("transcription failed:") { return true }
        if lower.contains("voice runtime") { return true }
        if lower.contains("no voice provider") { return true }
        if lower == "no speech detected" { return true }
        if lower == "transcription timed out" { return true }
        if lower.contains("mic in use") || lower.contains("mic busy") { return true }
        if lower.contains("live_session_busy") { return true }
        if lower.contains("unauthorized") { return true }
        if lower.contains("access denied") || lower.contains("accessibility") { return true }
        if lower.contains("intent not found") || lower.contains("intent unresolved") { return true }
        if lower == "voice cancelled" { return true }
        if lower.contains("no active live session") { return true }
        return false
    }

    public static func map(message: String, detail: String?) -> DeckVoiceError {
        let lower = message.lowercased()

        if lower.contains("live_session_busy") {
            return DeckVoiceError(
                code: .micBusy,
                severity: .warning,
                recoverable: true,
                retry: .immediate,
                source: .vox,
                owner: "Lattices",
                message: "Voice session still open — tap Cancel, then try again",
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower.contains("no active live session") {
            return DeckVoiceError(
                code: .transcriptionFailed,
                severity: .warning,
                recoverable: true,
                retry: .immediate,
                source: .vox,
                message: "Voice capture wasn't ready — wait for listening, then try again",
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower.contains("mic in use") || lower.contains("mic busy") {
            let owner = micOwner(from: message) ?? "another app"
            return DeckVoiceError(
                code: .micBusy,
                severity: .warning,
                recoverable: true,
                retry: .userAction,
                source: .vox,
                owner: owner,
                message: "Mic in use by \(owner) — finish recording first",
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower.contains("mic denied") || (lower.contains("microphone") && lower.contains("denied")) {
            return DeckVoiceError(
                code: .micDenied,
                severity: .blocked,
                recoverable: false,
                retry: .userAction,
                source: .mac,
                message: "Microphone access denied on your Mac",
                remediation: .openSystemSettings(kind: "microphone"),
                detail: detail
            )
        }

        if lower.contains("accessibility") && (lower.contains("denied") || lower.contains("access")) {
            return DeckVoiceError(
                code: .accessibilityDenied,
                severity: .blocked,
                recoverable: false,
                retry: .userAction,
                source: .mac,
                message: "Accessibility access required on your Mac",
                remediation: .openSystemSettings(kind: "accessibility"),
                detail: detail
            )
        }

        if lower.contains("no voice provider") {
            return DeckVoiceError(
                code: .voxNotRunning,
                severity: .error,
                recoverable: true,
                retry: .afterLaunch,
                source: .mac,
                message: "Voice runtime not available in this build",
                remediation: .openDiagnostics,
                detail: detail
            )
        }

        if lower.contains("unauthorized") {
            return DeckVoiceError(
                code: .voxUnreachable,
                severity: .error,
                recoverable: true,
                retry: .afterLaunch,
                source: .vox,
                message: "Voice runtime rejected Lattices",
                remediation: .openVox,
                detail: detail
            )
        }

        if lower.contains("voice runtime unavailable") || lower.contains("voice runtime not running") {
            return DeckVoiceError(
                code: .voxUnreachable,
                severity: .error,
                recoverable: true,
                retry: .afterLaunch,
                source: .vox,
                message: "Voice runtime offline — starting",
                remediation: .openVox,
                detail: detail
            )
        }

        if lower.contains("connection lost") || lower.contains("network connection was lost") {
            return DeckVoiceError(
                code: .connectionLost,
                severity: .error,
                recoverable: true,
                retry: .immediate,
                source: .vox,
                message: "Connection lost — press again",
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower == "no speech detected" {
            return DeckVoiceError(
                code: .emptyTranscript,
                severity: .warning,
                recoverable: true,
                retry: .immediate,
                source: .vox,
                message: "No speech detected — try again",
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower == "transcription timed out" || lower.hasPrefix("transcription failed:") {
            return DeckVoiceError(
                code: .transcriptionFailed,
                severity: .warning,
                recoverable: true,
                retry: .immediate,
                source: .vox,
                message: "Transcription failed — try again",
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower.hasPrefix("couldn't run:") {
            return DeckVoiceError(
                code: .actionFailed,
                severity: .error,
                recoverable: true,
                retry: .immediate,
                source: .intent,
                message: message,
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower.contains("intent not found") || lower.contains("intent unresolved") {
            return DeckVoiceError(
                code: .intentUnresolved,
                severity: .warning,
                recoverable: true,
                retry: .immediate,
                source: .intent,
                message: "Intent not found — try rephrasing",
                remediation: .retryVoice,
                detail: detail
            )
        }

        if lower == "voice cancelled" {
            return DeckVoiceError(
                code: .emptyTranscript,
                severity: .info,
                recoverable: true,
                retry: .immediate,
                source: .mac,
                message: "Voice cancelled",
                remediation: .retryVoice,
                detail: detail
            )
        }

        return DeckVoiceError(
            code: .actionFailed,
            severity: .error,
            recoverable: true,
            retry: .immediate,
            source: .mac,
            message: message,
            remediation: .retryVoice,
            detail: detail
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func micOwner(from message: String) -> String? {
        if let range = message.range(of: "by ", options: .caseInsensitive) {
            let tail = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { return tail }
        }
        return nil
    }
}
