import Foundation

// MARK: - Voice error model
//
// Shared across Mac (capture + execution) and iPad (relay + status).
// Stable raw string values so codes survive JSON, JSONL logs, and the bridge
// snapshot. See `docs/voice-error-model.md` for the design rationale.

public struct DeckVoiceError: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var code: DeckVoiceErrorCode
    public var severity: DeckErrorSeverity
    public var recoverable: Bool
    public var retry: DeckRetryHint?
    public var source: DeckErrorSource
    public var owner: String?                  // e.g. "Vox" for mic_busy
    public var message: String                 // cockpit copy, human-readable
    public var remediation: DeckRemediationAction?
    public var occurredAt: Date
    public var detail: String?                 // diagnostic-only, not displayed

    public init(
        id: String = UUID().uuidString,
        code: DeckVoiceErrorCode,
        severity: DeckErrorSeverity,
        recoverable: Bool,
        retry: DeckRetryHint? = nil,
        source: DeckErrorSource,
        owner: String? = nil,
        message: String,
        remediation: DeckRemediationAction? = nil,
        occurredAt: Date = .now,
        detail: String? = nil
    ) {
        self.id = id
        self.code = code
        self.severity = severity
        self.recoverable = recoverable
        self.retry = retry
        self.source = source
        self.owner = owner
        self.message = message
        self.remediation = remediation
        self.occurredAt = occurredAt
        self.detail = detail
    }
}

public enum DeckVoiceErrorCode: String, Codable, CaseIterable, Sendable {
    case voxUnreachable      = "vox_unreachable"
    case daemonUnreachable   = "daemon_unreachable"
    case network             = "network"
    case connectionLost      = "connection_lost"
    case micDenied           = "mic_denied"
    case accessibilityDenied = "accessibility_denied"
    case micBusy             = "mic_busy"
    case noActiveTarget      = "no_active_target"
    case voxNotRunning       = "vox_not_running"
    case voxLoading          = "vox_loading"
    case intentUnresolved    = "intent_unresolved"
    case actionFailed        = "action_failed"
    case transcriptionFailed = "transcription_failed"
    case emptyTranscript     = "empty_transcript"
    case languageUnsupported = "language_unsupported"
}

public enum DeckErrorSeverity: String, Codable, CaseIterable, Sendable {
    case info, warning, error, blocked
}

public enum DeckRetryHint: String, Codable, CaseIterable, Sendable {
    case silent                      // reconnect quietly, log only
    case immediate                   // safe to auto-retry now
    case afterLaunch  = "after_launch"  // retry after launching a dependency (e.g. Vox)
    case userAction   = "user_action"   // user must do something first
}

public enum DeckErrorSource: String, Codable, CaseIterable, Sendable {
    case mac, ipad, vox, daemon, intent, bridge
}

public enum DeckRemediationAction: Codable, Equatable, Sendable {
    case openVox
    case openSystemSettings(kind: String)
    case retryVoice
    case openDiagnostics
    case chooseTarget
}
