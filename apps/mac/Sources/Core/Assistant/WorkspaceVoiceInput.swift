import Combine
import Foundation
#if LATTICES_VOICE && canImport(HudsonVoice)
import HudsonVoice
#endif

// Voice-enabled message input for the Workspace Assistant — powered by HudsonVoice.
//
// Modeled on OpenScout's HUD dictation (HUDDockState + MicButton):
// tap-to-start, live `session.partial` preview, `session.final` spliced once into
// the composer draft. The difference is the transport: instead of OpenScout's
// hand-rolled HTTP/NDJSON wrapper, this drives HudsonKit's native HudVoxLiveSession
// through the Lattices-hosted HudsonVoice runtime capability.
//
// Mic capture is owned by Lattices because Lattices embeds the HudsonVoice runtime.

enum WorkspaceVoiceState: Equatable {
    case idle
    case starting
    case recording
    case processing
    case unavailable(reason: String)

    /// Mic is hot (recording or spinning up) — tapping again commits.
    var isCaptureActive: Bool { self == .starting || self == .recording }
    var isProcessing: Bool { self == .processing }
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

/// One-line outcome shown under the composer after a dictation turn.
struct WorkspaceVoiceOutcome: Equatable {
    enum Kind: Equatable {
        case heard
        case empty
        case failed
    }

    let kind: Kind
    let message: String
    let transcript: String?
    let at: Date

    static func heard(_ text: String) -> WorkspaceVoiceOutcome {
        WorkspaceVoiceOutcome(
            kind: .heard,
            message: "Heard: \(Self.preview(text))",
            transcript: text,
            at: Date()
        )
    }

    static func empty(detail: String) -> WorkspaceVoiceOutcome {
        WorkspaceVoiceOutcome(kind: .empty, message: detail, transcript: nil, at: Date())
    }

    static func failed(_ reason: String) -> WorkspaceVoiceOutcome {
        WorkspaceVoiceOutcome(kind: .failed, message: reason, transcript: nil, at: Date())
    }

    private static func preview(_ text: String, limit: Int = 80) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return "“\(trimmed)”" }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return "“\(trimmed[..<end])…”"
    }
}

/// Splice a dictated phrase into an existing buffer: empty → set; non-empty →
/// append with a single separating space. Mirrors OpenScout's ScoutDictationBuffer.
enum WorkspaceDictationBuffer {
    static func appending(_ phrase: String, to current: String) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current }
        guard !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return trimmed }
        let trailingSpace = current.last?.isWhitespace ?? false
        return current + (trailingSpace ? "" : " ") + trimmed
    }
}

#if LATTICES_VOICE && canImport(HudsonVoice)

/// One-session-at-a-time dictation controller backed by HudVoxLiveSession.
/// Tap the mic to start; tap again to commit and surface the transcript on
/// `lastFinalText`, which the chat session drains into the composer draft.
final class WorkspaceVoiceInput: ObservableObject {
    static let shared = WorkspaceVoiceInput()

    /// Mic-button visual state.
    @Published private(set) var state: WorkspaceVoiceState = .idle
    /// Live partial transcript while recording. Cleared on commit.
    @Published private(set) var partial: String = ""
    /// Most recent final transcript. The chat session observes this and splices
    /// it into the draft, then calls `consumeFinalText()` so it fires once.
    @Published private(set) var lastFinalText: String = ""
    /// Human-readable result of the last completed turn (success, empty, fail).
    @Published private(set) var lastOutcome: WorkspaceVoiceOutcome?

    private var session: HudVoxLiveSession?
    private var pumpTask: Task<Void, Never>?
    private var stopTimeoutTask: Task<Void, Never>?
    private var outcomeClearTask: Task<Void, Never>?
    private var activeCaptureID: String?
    private var turnStartedAt: Date?
    /// When the runtime first reported `.recording` (mic actually hot).
    private var recordingStartedAt: Date?
    private var finalDelivered = false
    private static let stopTimeoutNanoseconds: UInt64 = 10_000_000_000
    private static let outcomeVisibleNanoseconds: UInt64 = 8_000_000_000
    /// AVCapture often needs a short settle after start; stopping too early yields
    /// a near-empty WAV and a useless empty transcript.
    private static let minimumRecordingNanoseconds: UInt64 = 700_000_000

    private init() {}

    /// Mic-tap action: idle/unavailable → start, hot → stop, processing → ignore.
    @MainActor
    func toggle() {
        switch state {
        case .idle, .unavailable:
            start()
        case .starting, .recording:
            stop()
        case .processing:
            break
        }
    }

    @MainActor
    func dismissOutcome() {
        lastOutcome = nil
        outcomeClearTask?.cancel()
        outcomeClearTask = nil
    }

    @MainActor
    func start() {
        guard session == nil else {
            voiceLog("already listening — ignored", level: .info)
            return
        }
        partial = ""
        finalDelivered = false
        lastOutcome = nil
        recordingStartedAt = nil
        outcomeClearTask?.cancel()
        let captureID = UUID().uuidString.prefix(8).lowercased()
        activeCaptureID = String(captureID)
        turnStartedAt = Date()
        state = .starting

        guard let runtime = HudsonVoiceRuntimeResolver.resolve(clientId: "lattices") else {
            finishTurn(
                .failed("Voice runtime is not running. Restart Lattices."),
                captureID: String(captureID),
                asUnavailable: true
            )
            return
        }
        let endpoint = runtime.endpoint
        voiceLog("listening on \(endpoint.url.absoluteString)", level: .info, id: String(captureID))
        let session = HudVoxLiveSession(
            endpoint: endpoint,
            options: runtime.options
        )
        self.session = session

        pumpTask = Task { [weak self] in
            do {
                let stream = try await session.start()
                for try await event in stream {
                    await MainActor.run { [weak self] in self?.handle(event, captureID: String(captureID)) }
                }
                await MainActor.run { [weak self] in self?.streamEnded(error: nil, captureID: String(captureID)) }
            } catch {
                await MainActor.run { [weak self] in self?.streamEnded(error: error, captureID: String(captureID)) }
            }
        }
    }

    @MainActor
    func stop() {
        guard state.isCaptureActive else {
            voiceLog("stop ignored (not recording)", level: .info)
            return
        }
        // Wait until the runtime is actually recording — stop during `.starting`
        // is a common source of empty WAVs.
        guard state == .recording, recordingStartedAt != nil else {
            voiceLog("still starting mic — hold a moment, then tap again", level: .info)
            lastOutcome = .empty(detail: "Mic is still starting — hold a beat, then tap to finish.")
            scheduleOutcomeClear()
            return
        }
        let captureID = activeCaptureID ?? "unknown"
        voiceLog("transcribing…", level: .info, id: captureID)
        state = .processing
        let session = self.session
        let recordedFor = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        stopTimeoutTask?.cancel()
        stopTimeoutTask = Task { [weak self, captureID] in
            try? await Task.sleep(nanoseconds: Self.stopTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stopTimedOut(captureID: captureID) }
        }
        Task { [weak self, captureID, recordedFor] in
            // Give AVCapture a minimum window so the file isn't just a header.
            let minSeconds = Double(Self.minimumRecordingNanoseconds) / 1_000_000_000
            if recordedFor < minSeconds {
                let remaining = minSeconds - recordedFor
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            do {
                try await session?.stop()
            } catch {
                await MainActor.run { self?.stopFailed(error, captureID: captureID) }
            }
        }
    }

    @MainActor
    func cancel() {
        let captureID = activeCaptureID ?? "unknown"
        voiceLog("cancelled", level: .info, id: captureID)
        let session = self.session
        finalDelivered = true   // suppress any trailing final
        partial = ""
        if !state.isUnavailable { state = .idle }
        clearCapture(closeSession: false)
        Task { try? await session?.cancel() }
    }

    /// Drain the one-shot final signal after the consumer has appended it.
    @MainActor
    func consumeFinalText() {
        lastFinalText = ""
    }

    // MARK: - Event handling (main actor)

    @MainActor
    private func handle(_ event: HudVoiceEvent, captureID: String) {
        guard isCurrentCapture(captureID) else { return }
        switch event {
        case .state(let s):
            // Only surface user-meaningful states — skip noisy starting/done chatter.
            switch s.state {
            case .recording:
                if state != .recording {
                    voiceLog("recording", level: .info, id: captureID)
                    recordingStartedAt = Date()
                }
                state = .recording
            case .processing:
                state = .processing
            case .error:
                finishTurn(
                    .failed("Voice engine reported an error. Try again."),
                    captureID: captureID,
                    asUnavailable: true
                )
                clearCapture(closeSession: true)
            case .cancelled:
                if !state.isUnavailable { state = .idle }
                clearCapture(closeSession: true)
            case .starting:
                if state != .recording { state = .starting }
            case .done:
                if !finalDelivered {
                    finishTurn(
                        .empty(detail: "No speech detected."),
                        captureID: captureID,
                        asUnavailable: false
                    )
                    state = .idle
                }
                clearCapture(closeSession: true)
            }
        case .partial(let p):
            partial = p.text
        case .final(let f):
            deliverFinal(f, captureID: captureID)
        case .raw:
            break
        }
    }

    @MainActor
    private func deliverFinal(_ final: HudVoiceFinalEvent, captureID: String) {
        guard isCurrentCapture(captureID) else { return }
        guard !finalDelivered else { return }
        finalDelivered = true
        partial = ""
        let trimmed = final.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = final.elapsedMs
        if trimmed.isEmpty {
            // Empty is usually a truncated/empty capture (mic wrote almost no samples),
            // not a hard system failure — keep out of red status-bar sticky.
            finishTurn(
                .empty(detail: "No audio captured — check the mic and speak for a second or two."),
                captureID: captureID,
                asUnavailable: false
            )
            state = .idle
        } else {
            lastFinalText = trimmed
            // Success lands in the draft; still surface a brief confirmation so it
            // doesn't feel like the mic did nothing.
            finishTurn(
                .heard(trimmed),
                captureID: captureID,
                asUnavailable: false,
                elapsedMs: elapsed,
                surfaceOutcome: true
            )
            state = .idle
        }
        clearCapture(closeSession: true)
    }

    @MainActor
    private func streamEnded(error: Error?, captureID: String) {
        guard isCurrentCapture(captureID) else { return }
        if let error, !finalDelivered {
            let detail = Self.friendlyConnectionError(error)
            finishTurn(.failed(detail), captureID: captureID, asUnavailable: true)
        } else if !finalDelivered, !state.isUnavailable {
            state = .idle
        }
        clearCapture(closeSession: false)
    }

    @MainActor
    private func stopTimedOut(captureID: String) {
        guard isCurrentCapture(captureID), state.isProcessing else { return }
        finishTurn(
            .failed("Transcription timed out. Try again."),
            captureID: captureID,
            asUnavailable: true
        )
        let session = self.session
        clearCapture(closeSession: false)
        Task { try? await session?.cancel() }
    }

    @MainActor
    private func stopFailed(_ error: Error, captureID: String) {
        guard isCurrentCapture(captureID) else { return }
        finishTurn(
            .failed(Self.friendlyConnectionError(error)),
            captureID: captureID,
            asUnavailable: true
        )
        clearCapture(closeSession: true)
    }

    @MainActor
    private func finishTurn(
        _ outcome: WorkspaceVoiceOutcome,
        captureID: String,
        asUnavailable: Bool,
        elapsedMs: Int? = nil,
        surfaceOutcome: Bool = true
    ) {
        if surfaceOutcome {
            lastOutcome = outcome
            scheduleOutcomeClear()
        } else {
            lastOutcome = nil
            outcomeClearTask?.cancel()
            outcomeClearTask = nil
        }
        if asUnavailable {
            state = .unavailable(reason: outcome.message)
        }

        let holdMs: String = {
            if let elapsedMs { return "\(elapsedMs)ms" }
            if let started = turnStartedAt {
                return "\(Int(Date().timeIntervalSince(started) * 1000))ms"
            }
            return "?"
        }()

        switch outcome.kind {
        case .heard:
            let text = outcome.transcript ?? ""
            DiagnosticLog.shared.success("Voice · heard (\(holdMs)): \(text)")
        case .empty:
            // Soft outcome — not a system fault; keep out of red status-bar sticky.
            DiagnosticLog.shared.info("Voice · \(outcome.message)")
        case .failed:
            DiagnosticLog.shared.warn("Voice · \(outcome.message)")
        }

        _ = captureID
    }

    @MainActor
    private func scheduleOutcomeClear() {
        outcomeClearTask?.cancel()
        outcomeClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.outcomeVisibleNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.lastOutcome = nil
                if case .unavailable = self?.state {
                    self?.state = .idle
                }
            }
        }
    }

    @MainActor
    private func clearCapture(closeSession: Bool) {
        let currentSession = session
        session = nil
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        pumpTask?.cancel()
        pumpTask = nil
        activeCaptureID = nil
        turnStartedAt = nil
        recordingStartedAt = nil
        if closeSession {
            currentSession?.close()
        }
    }

    private func isCurrentCapture(_ captureID: String) -> Bool {
        activeCaptureID == captureID
    }

    private func voiceLog(_ message: String, level: DiagnosticLog.Entry.Level, id: String? = nil) {
        let prefix = id.map { "Voice[\($0)] · " } ?? "Voice · "
        switch level {
        case .info: DiagnosticLog.shared.info(prefix + message)
        case .success: DiagnosticLog.shared.success(prefix + message)
        case .warning: DiagnosticLog.shared.warn(prefix + message)
        case .error: DiagnosticLog.shared.error(prefix + message)
        }
    }

    private static func friendlyConnectionError(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.localizedCaseInsensitiveContains("could not connect")
            || raw.localizedCaseInsensitiveContains("connection refused")
            || raw.localizedCaseInsensitiveContains("network connection was lost") {
            return "Could not reach the voice runtime on \(LatticesLocalEndpoints.voiceRuntimeWebSocketURL). Restart Lattices."
        }
        if raw.isEmpty { return "Voice session failed." }
        return raw
    }
}

#endif
