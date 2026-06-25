import AppKit
#if canImport(HudsonVoice)
import HudsonVoice
#endif

// MARK: - Audio Provider Protocol

/// A provider that can capture audio and return transcriptions.
/// Lattices doesn't do transcription itself. It delegates capture to Hudson
/// Voice and maps the transcript to intents.
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
    let source: String           // "hudson-voice", "voice-runtime", etc.
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
        providerName = "hudson-voice"
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
            setFinalResult("No voice provider available", warning: true)
            return
        }

        pendingVoiceStart = true
        voiceConnectionRetry?.cancel()
        startVoiceCommandWhenReady(provider: provider, attempt: 0)
    }

    private func startVoiceCommandWhenReady(provider: any AudioProvider, attempt: Int) {
        guard pendingVoiceStart, !isListening else { return }

        // `isAvailable` reflects whether a HudsonVoice endpoint can be resolved.
        // Health/session errors still surface from HudsonVoice when capture starts.
        if provider.isAvailable {
            pendingVoiceStart = false
            DiagnosticLog.shared.info("AudioLayer: voice provider ready")
            beginVoiceCommand(provider: provider)
            return
        }

        if attempt == 0 {
            executionResult = "Connecting to voice runtime..."
        }

        guard attempt < 40 else {
            pendingVoiceStart = false
            DiagnosticLog.shared.warn("AudioLayer: voice runtime not reachable before voice start")
            setFinalResult("Voice runtime unavailable", warning: true)
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
        let assistant = WorkspaceAssistantSession.shared
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
        let assistant = WorkspaceAssistantSession.shared
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
                WorkspaceAssistantSession.shared.repairVoiceIntent(
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
        let assistant = WorkspaceAssistantSession.shared
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
            if match.intentName == "focus" {
                return focusResultSummary(for: match, result: result, success: false)
            }
            return result["reason"]?.stringValue ?? "Voice command did not complete"
        }

        switch match.intentName {
        case "tile_window":
            let position = match.slots["position"]?.stringValue
                ?? result["position"]?.stringValue
                ?? "requested position"
            return "Moved window to \(position)"

        case "focus":
            return focusResultSummary(for: match, result: result, success: true)

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

    private func focusResultSummary(for match: IntentMatch, result: JSON, success: Bool) -> String {
        if let launched = nonEmpty(result["launched"]?.stringValue) {
            return "Launched \(launched)"
        }

        let app = nonEmpty(result["app"]?.stringValue ?? result["focused"]?.stringValue)
        let session = nonEmpty(result["session"]?.stringValue ?? result["latticesSession"]?.stringValue)
        let requested = nonEmpty(result["requested"]?.stringValue ?? match.slots["app"]?.stringValue)
        let rawTitle = nonEmpty(result["title"]?.stringValue)
        let title = nonEmpty(rawTitle.map(cleanWindowTitle))
        let target = app ?? session ?? title ?? requested ?? "target"

        var summary = success ? "Focused \(target)" : "Could not focus \(target)"
        if let title, title.localizedCaseInsensitiveCompare(target) != .orderedSame {
            summary += " - \"\(clipped(title))\""
        }

        var details: [String] = []
        if let session, session.localizedCaseInsensitiveCompare(target) != .orderedSame {
            details.append("session \(session)")
        }
        if let wid = result["wid"]?.intValue {
            details.append("wid \(wid)")
        }
        if let resolution = nonEmpty(result["targetResolution"]?.stringValue) {
            details.append("via \(humanFocusResolution(resolution))")
        }
        if !success, let reason = nonEmpty(result["reason"]?.stringValue) {
            details.append(reason)
        } else if success, result["raised"]?.boolValue == false {
            details.append("raise not confirmed")
        }

        if !details.isEmpty {
            summary += " (\(details.joined(separator: ", ")))"
        }
        return summary
    }

    private func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanWindowTitle(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: #"\[lattices:[^\]]+\]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? title : cleaned
    }

    private func clipped(_ text: String, limit: Int = 90) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 3))).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func humanFocusResolution(_ resolution: String) -> String {
        switch resolution {
        case "wid": return "window id"
        case "app": return "app match"
        case "search": return "search"
        case "session": return "session"
        case "session-locator": return "session locator"
        case "app-launch": return "app launch"
        default: return resolution.replacingOccurrences(of: "-", with: " ")
        }
    }
}

// Old IntentExtractor removed — PhraseMatcher handles all intent matching now.
// See apps/mac/Sources/Intents/LatticeIntent.swift


// MARK: - HudVox Audio Provider (HudsonVoice live session)
//
// Delegates recording and transcription through HudsonKit's `HudVoxLiveSession`.
// Lattices speaks HudsonVoice's Vox WebSocket contract through HudsonKit.
//
// This replaces the legacy `VoxAudioProvider` (which drove the now-retired
// `VoxClient` WebSocket). HudsonVoice opens its own socket per capture rather
// than holding one open.

#if canImport(HudsonVoice)
final class HudVoxAudioProvider: AudioProvider {
    private var session: HudVoxLiveSession?
    private var pumpTask: Task<Void, Never>?
    private var onTranscript: ((Transcription) -> Void)?
    private var stopCompletion: ((Transcription?) -> Void)?
    private var _isListening = false
    private var finalDelivered = false

    var isAvailable: Bool { HudsonVoiceRuntimeResolver.resolve(clientId: "lattices") != nil }
    var isListening: Bool { _isListening }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        guard let runtime = HudsonVoiceRuntimeResolver.resolve(clientId: "lattices") else {
            completion(false)
            return
        }
        Task {
            let ok = (try? await HudVoxProbe.health(
                endpoint: runtime.endpoint,
                clientId: runtime.options.clientId
            )) != nil
            await MainActor.run { completion(ok) }
        }
    }

    func startListening(onTranscript: @escaping (Transcription) -> Void) {
        guard session == nil else { return }
        self.onTranscript = onTranscript
        _isListening = true
        finalDelivered = false

        guard let runtime = HudsonVoiceRuntimeResolver.resolve(clientId: "lattices") else {
            DiagnosticLog.shared.warn("HudVoxAudioProvider: cannot start because HudsonVoice runtime is unavailable")
            _isListening = false
            self.onTranscript = nil
            return
        }
        let endpoint = runtime.endpoint
        DiagnosticLog.shared.info("HudVoxAudioProvider: starting session at \(endpoint.url.absoluteString)")
        let session = HudVoxLiveSession(
            endpoint: endpoint,
            options: runtime.options
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
            onTranscript?(Transcription(text: p.text, confidence: 0.5, source: "hudson-voice", isPartial: true, durationMs: nil))
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
        let t = Transcription(text: text, confidence: 0.95, source: "hudson-voice", isPartial: false, durationMs: elapsedMs)
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
                onTranscript?(Transcription(text: "", confidence: 0, source: "hudson-voice", isPartial: false, durationMs: nil))
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
