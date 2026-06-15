import AppKit
#if canImport(HudsonVoice)
import HudsonVoice
#endif

// MARK: - Audio Provider Protocol

/// A provider that can capture audio and return transcriptions.
/// Lattices doesn't do transcription itself — it delegates to an external
/// service (Vox, Whisper, etc.) and maps the result to intents.
protocol AudioProvider: AnyObject {
    var isAvailable: Bool { get }
    var isListening: Bool { get }

    /// Start listening. Transcription arrives via the callback.
    func startListening(onTranscript: @escaping (Transcription) -> Void)

    /// Stop listening and return the final transcription.
    func stopListening(completion: @escaping (Transcription?) -> Void)

    /// Check if the provider service is reachable.
    func checkHealth(completion: @escaping (Bool) -> Void)
}

struct Transcription {
    let text: String
    let confidence: Double
    let source: String           // "vox", "whisper", etc.
    let isPartial: Bool          // true for streaming partial results
    let durationMs: Int?
}

// MARK: - Audio Layer (coordinates provider + intent engine)

final class AudioLayer: ObservableObject {
    static let shared = AudioLayer()

    @Published var isListening = false
    @Published var lastTranscript: String?
    @Published var matchedIntent: String?
    @Published var matchedSlots: [String: String] = [:]
    @Published var matchConfidence: Double = 0
    @Published var executionResult: String?   // "ok" or error message
    @Published var executionData: JSON?       // Full result data from intent execution
    @Published var executionError: String?    // Set when an intent failed to run, so the UI can flag it
    @Published var provider: (any AudioProvider)?
    @Published var providerName: String = "none"
    @Published var agentResponse: AgentResponse?

    private var pendingVoiceStart = false
    private var voiceConnectionRetry: DispatchWorkItem?

    private init() {
        #if canImport(HudsonVoice)
        provider = HudVoxAudioProvider()
        providerName = "vox"
        #else
        provider = nil
        providerName = "none"
        #endif
        // Voice entry points can arrive from the desktop UI, daemon, or iOS
        // bridge, so the live session is opened lazily when capture starts.
    }

    /// Start a voice command capture. Transcription is piped to the intent engine.
    func startVoiceCommand() {
        guard !isListening else { return }

        // Clear previous state
        lastTranscript = nil
        matchedIntent = nil
        matchedSlots = [:]
        matchConfidence = 0
        executionResult = nil
        executionData = nil
        executionError = nil
        agentResponse = nil
        didExecuteIntent = false
        DiagnosticLog.shared.info("AudioLayer: voice capture starting")

        guard let provider = provider else {
            setFinalResult("No voice provider — install Vox", warning: true)
            return
        }

        pendingVoiceStart = true
        voiceConnectionRetry?.cancel()
        startVoiceCommandWhenReady(provider: provider, attempt: 0)
    }

    private func startVoiceCommandWhenReady(provider: any AudioProvider, attempt: Int) {
        guard pendingVoiceStart, !isListening else { return }

        // `isAvailable` reflects whether voxd is discoverable. HudsonVoice opens its
        // own socket on capture start, so there's nothing to pre-connect — we just
        // wait (and nudge Vox.app open once) until the daemon shows up.
        if provider.isAvailable {
            pendingVoiceStart = false
            DiagnosticLog.shared.info("AudioLayer: voice provider ready")
            beginVoiceCommand(provider: provider)
            return
        }

        if attempt == 0 {
            let launched = launchVoxIfNeeded()
            executionResult = launched ? "Starting Vox..." : "Connecting to Vox..."
        }

        guard attempt < 40 else {
            pendingVoiceStart = false
            DiagnosticLog.shared.warn("AudioLayer: Vox daemon not reachable before voice start")
            setFinalResult("Vox unavailable — open Vox and try again", warning: true)
            return
        }

        let retry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startVoiceCommandWhenReady(provider: provider, attempt: attempt + 1)
        }
        voiceConnectionRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: retry)
    }

    private func beginVoiceCommand(provider: any AudioProvider) {
        isListening = true
        DiagnosticLog.shared.info("AudioLayer: listening for voice command")

        provider.startListening { [weak self] transcription in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if transcription.isPartial {
                    self.lastTranscript = transcription.text
                    return
                }

                // Final transcript (e.g. from streaming providers)
                self.lastTranscript = transcription.text
                self.isListening = false

                // Empty transcript = transcription failed, don't try to execute
                guard !transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    if self.executionResult == nil || self.executionResult == "Transcribing..." {
                        self.setFinalResult("No speech detected", warning: true)
                    }
                    return
                }

                DiagnosticLog.shared.info("AudioLayer: heard final transcript — \(transcription.text)")
                EventBus.shared.post(.voiceCommand(text: transcription.text, confidence: transcription.confidence))
                self.executeVoiceIntent(transcription)
            }
        }
    }

    private func launchVoxIfNeeded() -> Bool {
        guard !VoxDaemon.isRunning else { return false }

        let candidates = [
            "/Applications/Vox.app",
            NSHomeDirectory() + "/Applications/Vox.app",
        ]

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            DiagnosticLog.shared.warn("AudioLayer: Vox daemon unavailable and Vox.app was not found")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { _, error in
            if let error {
                DiagnosticLog.shared.warn("AudioLayer: failed to open Vox — \(error.localizedDescription)")
            } else {
                DiagnosticLog.shared.info("AudioLayer: opened Vox for voice command")
            }
        }
        return true
    }

    /// Track whether we already executed for this recording session.
    private var didExecuteIntent = false

    func stopVoiceCommand() {
        if pendingVoiceStart, !isListening {
            pendingVoiceStart = false
            voiceConnectionRetry?.cancel()
            voiceConnectionRetry = nil
            setFinalResult("Voice cancelled")
            return
        }

        guard let provider = provider, isListening else { return }

        pendingVoiceStart = false
        isListening = false
        executionResult = "Transcribing..."
        DiagnosticLog.shared.info("AudioLayer: voice capture stopping; waiting for transcript")

        provider.stopListening { [weak self] transcription in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let t = transcription,
                   !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.lastTranscript = t.text
                    // Skip if the streaming callback already executed the intent
                    guard !self.didExecuteIntent else { return }
                    DiagnosticLog.shared.info("AudioLayer: heard final transcript — \(t.text)")
                    EventBus.shared.post(.voiceCommand(text: t.text, confidence: t.confidence))
                    self.executeVoiceIntent(t)
                } else if !self.didExecuteIntent {
                    self.setFinalResult("No speech detected", warning: true)
                }
            }
        }
    }

    private func executeVoiceIntent(_ transcription: Transcription) {
        didExecuteIntent = true
        let matcher = PhraseMatcher.shared

        // Clear previous agent response + any stale failure flag
        agentResponse = nil
        executionError = nil
        executionData = nil

        DiagnosticLog.shared.info("AudioLayer: resolving voice request")

        if let match = matcher.match(text: transcription.text) {
            DiagnosticLog.shared.info("AudioLayer: route → local intent")
            matchedIntent = match.intentName
            matchConfidence = match.confidence
            matchedSlots = match.slots.reduce(into: [:]) { dict, pair in
                dict[pair.key] = pair.value.stringValue ?? "\(pair.value)"
            }
            DiagnosticLog.shared.info("AudioLayer: matched '\(match.intentName)' via '\(match.matchedPhrase)' slots=\(matchedSlots)")

            do {
                let result = try matcher.execute(match)
                DiagnosticLog.shared.info("AudioLayer: executed '\(match.intentName)'")
                setFinalResult(voiceResultSummary(for: match, result: result), data: result)
            } catch {
                DiagnosticLog.shared.info("AudioLayer: intent error — \(error.localizedDescription), asking Assistant provider")
                executionResult = "thinking..."
                executionData = nil
                assistantFallback(transcription: transcription)
            }

            // Fire parallel provider-backed advisor for 5+ word utterances.
            fireAdvisor(transcript: transcription.text, matched: "\(match.intentName)(\(matchedSlots))")

        } else if shouldAnswerWithAssistant(transcription.text) {
            DiagnosticLog.shared.info("AudioLayer: route → Assistant question")
            DiagnosticLog.shared.info("AudioLayer: question-like voice request, asking Assistant provider")
            matchedIntent = nil
            matchedSlots = [:]
            executionResult = "thinking..."
            executionData = nil
            assistantQuestion(transcription: transcription)

        } else {
            // No local match — ask the selected Assistant provider.
            DiagnosticLog.shared.info("AudioLayer: route → Assistant intent resolver")
            DiagnosticLog.shared.info("AudioLayer: no phrase match for '\(transcription.text)', asking Assistant provider")
            matchedIntent = nil
            matchedSlots = [:]
            executionResult = "thinking..."
            executionData = nil
            assistantFallback(transcription: transcription)
        }
    }

    /// Fire the selected Assistant provider in parallel — non-blocking, result arrives later.
    private func fireAdvisor(transcript: String, matched: String) {
        let assistant = PiChatSession.shared
        guard assistant.isProviderInferenceReady else {
            DiagnosticLog.shared.info("AudioLayer: advisor skipped (Assistant provider not ready)")
            return
        }

        DiagnosticLog.shared.info("AudioLayer: firing Assistant advisor via \(assistant.currentProvider.name)")

        assistant.askVoiceAdvisor(transcript: transcript, matched: matched) { [weak self] response in
            guard let self = self, let response = response else { return }
            self.agentResponse = response
            if let commentary = response.commentary {
                DiagnosticLog.shared.info("AudioLayer: Assistant advisor says — \(commentary)")
            }
            if let suggestion = response.suggestion {
                DiagnosticLog.shared.info("AudioLayer: Assistant advisor suggests — \(suggestion.label) → \(suggestion.intent)")
            }
        }
    }

    private func assistantFallback(transcription: Transcription) {
        let assistant = PiChatSession.shared
        guard assistant.isProviderInferenceReady else {
            DiagnosticLog.shared.info("AudioLayer: Assistant provider not ready")
            setFinalResult("Connect an Assistant provider in Settings", warning: true)
            return
        }

        assistant.resolveVoiceIntent(transcript: transcription.text) { [weak self] resolved in
            guard let self else { return }
            guard let resolved else {
                DiagnosticLog.shared.info("AudioLayer: Assistant provider returned no intent")
                self.setFinalResult("Assistant couldn't resolve an action for that request", warning: true)
                return
            }

            DiagnosticLog.shared.info("AudioLayer: Assistant resolved → \(resolved.intent) \(resolved.slots)")
            self.runResolved(resolved, transcript: transcription.text, allowRepair: true)
        }
    }

    /// Normalize + validate + execute an AI-resolved intent. On failure, fires one
    /// best-effort repair pass (a second model call constrained to the catalog) before
    /// surfacing the error. `allowRepair` guards against looping on the repaired output.
    private func runResolved(_ resolved: ResolvedIntent, transcript: String, allowRepair: Bool) {
        do {
            // Normalize + validate the AI's output against the catalog before running.
            // Maps shorthand (tl→top-left, grid-2x2→distribute) and rejects values the
            // executor would silently fail on, surfacing a precise message instead.
            let normalized = try PhraseMatcher.shared.normalizeResolved(
                intentName: resolved.intent,
                slots: resolved.slots
            )
            if normalized.intent != resolved.intent {
                DiagnosticLog.shared.info("AudioLayer: Assistant intent normalized \(resolved.intent) → \(normalized.intent)")
            }

            self.matchedIntent = normalized.intent
            self.matchedSlots = normalized.slots.reduce(into: [:]) { dict, pair in
                dict[pair.key] = pair.value.stringValue ?? "\(pair.value)"
            }

            let intentMatch = IntentMatch(
                intentName: normalized.intent,
                slots: normalized.slots,
                confidence: 0.8,
                matchedPhrase: "assistant-provider"
            )

            let execResult = try PhraseMatcher.shared.execute(intentMatch)
            self.executionError = nil
            DiagnosticLog.shared.info("AudioLayer: Assistant-resolved executed")
            self.setFinalResult(self.voiceResultSummary(for: intentMatch, result: execResult), data: execResult)
        } catch {
            let message = error.localizedDescription

            // Second-chance repair: hand the model the exact failure + valid vocabulary
            // and let it correct itself once before we give up and surface the error.
            if allowRepair {
                DiagnosticLog.shared.info("AudioLayer: Assistant-resolved failed (\(message)) — attempting repair pass")
                self.executionResult = "fixing..."
                PiChatSession.shared.repairVoiceIntent(
                    transcript: transcript,
                    failedIntent: resolved.intent,
                    failedSlots: resolved.slots,
                    error: message
                ) { [weak self] repaired in
                    guard let self else { return }
                    guard let repaired else {
                        self.reportExecutionFailure(resolved, message: message)
                        return
                    }
                    DiagnosticLog.shared.info("AudioLayer: repair pass → \(repaired.intent) \(repaired.slots)")
                    self.runResolved(repaired, transcript: transcript, allowRepair: false)
                }
                return
            }

            self.reportExecutionFailure(resolved, message: message)
        }
    }

    private func reportExecutionFailure(_ resolved: ResolvedIntent, message: String) {
        matchedIntent = resolved.intent
        matchedSlots = resolved.slots.reduce(into: [:]) { dict, pair in
            dict[pair.key] = pair.value.stringValue ?? "\(pair.value)"
        }
        executionError = message
        DiagnosticLog.shared.info("AudioLayer: Assistant-resolved execution error — \(message)")
        setFinalResult("Couldn't run: \(message)", error: message, warning: true)
    }

    private func assistantQuestion(transcription: Transcription) {
        let assistant = PiChatSession.shared
        guard assistant.isProviderInferenceReady else {
            DiagnosticLog.shared.info("AudioLayer: Assistant provider not ready for question")
            setFinalResult("Connect an Assistant provider in Settings", warning: true)
            return
        }

        assistant.answerVoiceQuestion(transcription.text) { [weak self] response in
            guard let self else { return }
            guard let response else {
                DiagnosticLog.shared.info("AudioLayer: Assistant provider returned no answer")
                self.setFinalResult("Assistant couldn't answer that question", warning: true)
                return
            }
            self.agentResponse = response
            if let commentary = response.commentary {
                DiagnosticLog.shared.info("AudioLayer: Assistant answered — \(commentary.prefix(160))")
            }
            self.setFinalResult("Answered as a question; no workspace action ran.")
        }
    }

    // Question-vs-command classification lives in `IntentHeuristics` so the typed
    // command bar and this voice path stay in lock-step (one source of truth).
    private func shouldAnswerWithAssistant(_ text: String) -> Bool {
        IntentHeuristics.shouldAskAssistant(text)
    }

    fileprivate func setFinalResult(_ message: String, data: JSON? = nil, error: String? = nil, warning: Bool = false) {
        executionResult = message
        executionData = data
        executionError = error
        if warning || error != nil {
            DiagnosticLog.shared.warn("AudioLayer: final outcome — \(message)")
        } else {
            DiagnosticLog.shared.info("AudioLayer: final outcome — \(message)")
        }
    }

    private func voiceResultSummary(for match: IntentMatch, result: JSON) -> String {
        if let summary = result["summary"]?.stringValue, !summary.isEmpty {
            return summary
        }
        if let message = result["message"]?.stringValue, !message.isEmpty {
            return message
        }
        if result["ok"]?.boolValue == false {
            return result["reason"]?.stringValue ?? "Voice command did not complete"
        }

        switch match.intentName {
        case "tile_window":
            let position = match.slots["position"]?.stringValue
                ?? result["position"]?.stringValue
                ?? "requested position"
            return "Moved window to \(position)"

        case "focus":
            let target = result["focused"]?.stringValue
                ?? match.slots["app"]?.stringValue
                ?? "target"
            return "Focused \(target)"

        case "launch":
            if let launched = result["launched"]?.stringValue {
                return "Launched \(launched)"
            }
            let target = match.slots["project"]?.stringValue ?? "requested target"
            return "Opened \(target)"

        case "kill":
            let target = match.slots["session"]?.stringValue
                ?? match.slots["app"]?.stringValue
                ?? "target"
            return "Closed \(target)"

        default:
            return "ok"
        }
    }
}

// Old IntentExtractor removed — PhraseMatcher handles all intent matching now.
// See apps/mac/Sources/Intents/LatticeIntent.swift


// MARK: - HudVox Audio Provider (HudsonVoice live session)
//
// Delegates recording and transcription entirely to the Vox daemon (voxd) via
// HudsonKit's `HudVoxLiveSession`. Lattices never touches the mic — Vox owns the
// mic, recording, and transcription. We open a live session (which dials the port
// discovered from ~/.vox/runtime.json), stream `.partial` previews into the draft,
// and deliver the final transcript on `.final`.
//
// This replaces the legacy `VoxAudioProvider` (which drove the now-retired
// `VoxClient` WebSocket). Availability is "is voxd discoverable" (`VoxDaemon`),
// since HudsonVoice opens its own socket per capture rather than holding one open.

#if canImport(HudsonVoice)
final class HudVoxAudioProvider: AudioProvider {
    private var session: HudVoxLiveSession?
    private var pumpTask: Task<Void, Never>?
    private var onTranscript: ((Transcription) -> Void)?
    private var stopCompletion: ((Transcription?) -> Void)?
    private var _isListening = false
    private var finalDelivered = false

    var isAvailable: Bool { VoxDaemon.isRunning }
    var isListening: Bool { _isListening }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        let endpoint = VoxEndpointResolver.resolve()
        Task {
            let ok = (try? await HudVoxProbe.health(endpoint: endpoint, clientId: "lattices")) != nil
            await MainActor.run { completion(ok) }
        }
    }

    func startListening(onTranscript: @escaping (Transcription) -> Void) {
        guard session == nil else { return }
        self.onTranscript = onTranscript
        _isListening = true
        finalDelivered = false

        let endpoint = VoxEndpointResolver.resolve()
        DiagnosticLog.shared.info("HudVoxAudioProvider: starting session at \(endpoint.url.absoluteString)")
        let session = HudVoxLiveSession(
            endpoint: endpoint,
            options: HudVoxLiveSessionOptions(clientId: "lattices", mode: .pushToTalk)
        )
        self.session = session

        pumpTask = Task { [weak self] in
            do {
                let stream = try await session.start()
                for try await event in stream {
                    await MainActor.run { [weak self] in self?.handle(event) }
                }
                await MainActor.run { [weak self] in self?.streamEnded(error: nil) }
            } catch {
                await MainActor.run { [weak self] in self?.streamEnded(error: error) }
            }
        }
    }

    func stopListening(completion: @escaping (Transcription?) -> Void) {
        guard _isListening, let session else {
            completion(nil)
            return
        }
        DiagnosticLog.shared.info("HudVoxAudioProvider: stopping session")
        self.stopCompletion = completion
        Task { try? await session.stop() }
    }

    // MARK: - Event handling (main actor)

    @MainActor
    private func handle(_ event: HudVoiceEvent) {
        switch event {
        case .state(let s):
            DiagnosticLog.shared.info("HudVoxAudioProvider: session → \(s.state)")
        case .partial(let p):
            // Live preview — non-final, just updates the draft echo.
            onTranscript?(Transcription(text: p.text, confidence: 0.5, source: "vox", isPartial: true, durationMs: nil))
        case .final(let f):
            deliverFinal(text: f.text, elapsedMs: f.elapsedMs)
        case .raw:
            break
        }
    }

    @MainActor
    private func deliverFinal(text: String, elapsedMs: Int) {
        guard !finalDelivered else { return }
        finalDelivered = true
        _isListening = false
        let t = Transcription(text: text, confidence: 0.95, source: "vox", isPartial: false, durationMs: elapsedMs)
        DiagnosticLog.shared.info("HudVoxAudioProvider: transcribed → '\(text)' (\(elapsedMs)ms)")
        // onTranscript drives the streaming-execute path; stopCompletion the stop path.
        // AudioLayer guards against double-execution, so firing both is safe.
        onTranscript?(t)
        stopCompletion?(t)
        stopCompletion = nil
        session?.close()
        session = nil
    }

    @MainActor
    private func streamEnded(error: Error?) {
        _isListening = false
        if !finalDelivered {
            if let error {
                DiagnosticLog.shared.warn("HudVoxAudioProvider: session error — \(error.localizedDescription)")
                AudioLayer.shared.setFinalResult("Transcription failed", warning: true)
                onTranscript?(Transcription(text: "", confidence: 0, source: "vox", isPartial: false, durationMs: nil))
            }
            stopCompletion?(nil)
            stopCompletion = nil
            finalDelivered = true
        }
        session = nil
        pumpTask = nil
    }
}
#endif
