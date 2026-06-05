import Combine
import Foundation
#if canImport(HudsonVoice)
import HudsonVoice
#endif

// Voice-enabled message input for the Workspace Assistant — powered by HudsonVoice.
//
// Modeled on OpenScout's HUD dictation (ScoutVoxService + HUDDockState + MicButton):
// tap-to-start, live `session.partial` preview, `session.final` spliced once into
// the composer draft. The difference is the transport: instead of OpenScout's
// hand-rolled HTTP/NDJSON wrapper, this drives HudsonKit's native HudVoxLiveSession,
// whose default endpoint (127.0.0.1:42137) is exactly the voxd daemon Lattices
// already runs — so it lights up with no extra wiring.
//
// Mic capture lives entirely in the Vox daemon process, so the Lattices app needs
// no NSMicrophoneUsageDescription — the OS prompt belongs to Vox.

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

#if canImport(HudsonVoice)

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
    private var finalDelivered = false

    private init() {}

    /// Mic-tap action: idle/unavailable → start, hot → stop, processing → ignore.
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

    func start() {
        guard session == nil else { return }
        partial = ""
        finalDelivered = false
        state = .starting

        let session = HudVoxLiveSession(
            options: HudVoxLiveSessionOptions(clientId: "lattices", mode: .pushToTalk)
        )
        self.session = session

        pumpTask = Task { [weak self] in
            do {
                let stream = try await session.start()
                for try await event in stream {
                    await MainActor.run { self?.handle(event) }
                }
                await MainActor.run { self?.streamEnded(error: nil) }
            } catch {
                await MainActor.run { self?.streamEnded(error: error) }
            }
        }
    }

    func stop() {
        guard state.isCaptureActive else { return }
        state = .processing
        let session = self.session
        Task { try? await session?.stop() }
    }

    func cancel() {
        let session = self.session
        finalDelivered = true   // suppress any trailing final
        partial = ""
        if !state.isUnavailable { state = .idle }
        self.session = nil
        pumpTask?.cancel()
        pumpTask = nil
        Task { try? await session?.cancel() }
    }

    /// Drain the one-shot final signal after the consumer has appended it.
    func consumeFinalText() {
        lastFinalText = ""
    }

    // MARK: - Event handling (main actor)

    @MainActor
    private func handle(_ event: HudVoiceEvent) {
        switch event {
        case .state(let s):
            switch s.state {
            case .recording:
                state = .recording
            case .processing:
                state = .processing
            case .error:
                state = .unavailable(reason: "Vox reported a session error.")
            case .cancelled:
                if !state.isUnavailable { state = .idle }
            case .starting:
                if state != .recording { state = .starting }
            case .done:
                break
            }
        case .partial(let p):
            partial = p.text
        case .final(let f):
            deliverFinal(f.text)
        case .raw:
            break
        }
    }

    @MainActor
    private func deliverFinal(_ text: String) {
        guard !finalDelivered else { return }
        finalDelivered = true
        partial = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lastFinalText = text }
        state = .idle
        session?.close()
    }

    @MainActor
    private func streamEnded(error: Error?) {
        if let error, !finalDelivered {
            state = .unavailable(reason: error.localizedDescription)
        } else if !finalDelivered, !state.isUnavailable {
            state = .idle
        }
        session = nil
        pumpTask = nil
    }
}

#endif
