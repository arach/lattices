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

    private var session: HudVoxLiveSession?
    private var pumpTask: Task<Void, Never>?
    private var stopTimeoutTask: Task<Void, Never>?
    private var activeCaptureID: String?
    private var finalDelivered = false
    private static let stopTimeoutNanoseconds: UInt64 = 10_000_000_000

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
    func start() {
        guard session == nil else {
            DiagnosticLog.shared.warn("WorkspaceVoiceInput: start ignored; existing capture \(activeCaptureID ?? "unknown") is still \(stateLabel)")
            return
        }
        partial = ""
        finalDelivered = false
        let captureID = UUID().uuidString.prefix(8).lowercased()
        activeCaptureID = String(captureID)
        state = .starting

        guard let runtime = HudsonVoiceRuntimeResolver.resolve(clientId: "lattices") else {
            DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: HudsonVoice runtime unavailable")
            activeCaptureID = nil
            state = .unavailable(reason: "Hudson Voice runtime is unavailable.")
            return
        }
        let endpoint = runtime.endpoint
        DiagnosticLog.shared.info("WorkspaceVoiceInput[\(captureID)]: starting voice session at \(endpoint.url.absoluteString)")
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
            DiagnosticLog.shared.warn("WorkspaceVoiceInput: stop ignored while \(stateLabel)")
            return
        }
        let captureID = activeCaptureID ?? "unknown"
        DiagnosticLog.shared.info("WorkspaceVoiceInput[\(captureID)]: stopping voice session")
        state = .processing
        let session = self.session
        stopTimeoutTask?.cancel()
        stopTimeoutTask = Task { [weak self, captureID] in
            try? await Task.sleep(nanoseconds: Self.stopTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stopTimedOut(captureID: captureID) }
        }
        Task { [weak self, captureID] in
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
        DiagnosticLog.shared.info("WorkspaceVoiceInput[\(captureID)]: cancelling voice session")
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
            DiagnosticLog.shared.info("WorkspaceVoiceInput[\(captureID)]: session -> \(s.state)")
            switch s.state {
            case .recording:
                state = .recording
            case .processing:
                state = .processing
            case .error:
                DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: voice runtime reported a session error state")
                state = .unavailable(reason: "Voice runtime reported a session error.")
                clearCapture(closeSession: true)
            case .cancelled:
                if !state.isUnavailable { state = .idle }
                clearCapture(closeSession: true)
            case .starting:
                if state != .recording { state = .starting }
            case .done:
                if !finalDelivered {
                    DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: session ended without a final transcript")
                    state = .unavailable(reason: "No speech detected. Try again.")
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
        DiagnosticLog.shared.info("WorkspaceVoiceInput[\(captureID)]: final transcript length=\(trimmed.count) elapsed=\(final.elapsedMs)ms")
        if trimmed.isEmpty {
            DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: empty transcript from voice runtime")
            state = .unavailable(reason: "No speech detected. Try again.")
        } else {
            lastFinalText = trimmed
            state = .idle
        }
        clearCapture(closeSession: true)
    }

    @MainActor
    private func streamEnded(error: Error?, captureID: String) {
        guard isCurrentCapture(captureID) else { return }
        if let error, !finalDelivered {
            DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: session stream ended with error — \(error.localizedDescription)")
            state = .unavailable(reason: error.localizedDescription)
        } else if !finalDelivered, !state.isUnavailable {
            DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: stream ended without final transcript")
            state = .idle
        }
        clearCapture(closeSession: false)
    }

    @MainActor
    private func stopTimedOut(captureID: String) {
        guard isCurrentCapture(captureID), state.isProcessing else { return }
        DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: stop timed out waiting for final transcript")
        state = .unavailable(reason: "Transcription timed out. Try again.")
        let session = self.session
        clearCapture(closeSession: false)
        Task { try? await session?.cancel() }
    }

    @MainActor
    private func stopFailed(_ error: Error, captureID: String) {
        guard isCurrentCapture(captureID) else { return }
        DiagnosticLog.shared.warn("WorkspaceVoiceInput[\(captureID)]: stop failed — \(error.localizedDescription)")
        state = .unavailable(reason: error.localizedDescription)
        clearCapture(closeSession: true)
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
        if closeSession {
            currentSession?.close()
        }
    }

    private func isCurrentCapture(_ captureID: String) -> Bool {
        activeCaptureID == captureID
    }

    private var stateLabel: String {
        switch state {
        case .idle:
            return "idle"
        case .starting:
            return "starting"
        case .recording:
            return "recording"
        case .processing:
            return "processing"
        case .unavailable(let reason):
            return "unavailable(\(reason))"
        }
    }
}

#endif
