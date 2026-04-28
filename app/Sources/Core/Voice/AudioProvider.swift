import AppKit

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
    @Published var provider: (any AudioProvider)?
    @Published var providerName: String = "none"
    @Published var agentResponse: AgentResponse?


    private init() {
        let vox = VoxAudioProvider()
        provider = vox
        providerName = "vox"
        // Connection is managed by VoiceCommandWindow — not here.
        // Connecting here would race with (and destroy) the existing WebSocket.
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
        didExecuteIntent = false

        guard let provider = provider else {
            executionResult = "No voice provider — install Vox"
            return
        }

        isListening = true

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
                guard !transcription.text.isEmpty else {
                    if self.executionResult == nil || self.executionResult == "Transcribing..." {
                        self.executionResult = "No speech detected"
                    }
                    return
                }

                EventBus.shared.post(.voiceCommand(text: transcription.text, confidence: transcription.confidence))
                self.executeVoiceIntent(transcription)
            }
        }
    }

    /// Track whether we already executed for this recording session.
    private var didExecuteIntent = false

    func stopVoiceCommand() {
        guard let provider = provider, isListening else { return }

        isListening = false
        executionResult = "Transcribing..."

        provider.stopListening { [weak self] transcription in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let t = transcription {
                    self.lastTranscript = t.text
                    // Skip if the streaming callback already executed the intent
                    guard !self.didExecuteIntent else { return }
                    EventBus.shared.post(.voiceCommand(text: t.text, confidence: t.confidence))
                    self.executeVoiceIntent(t)
                } else if !self.didExecuteIntent {
                    self.executionResult = "No speech detected"
                }
            }
        }
    }

    private func executeVoiceIntent(_ transcription: Transcription) {
        didExecuteIntent = true
        let matcher = PhraseMatcher.shared

        // Clear previous agent response
        agentResponse = nil

        if let match = matcher.match(text: transcription.text) {
            matchedIntent = match.intentName
            matchConfidence = match.confidence
            matchedSlots = match.slots.reduce(into: [:]) { dict, pair in
                dict[pair.key] = pair.value.stringValue ?? "\(pair.value)"
            }
            DiagnosticLog.shared.info("AudioLayer: matched '\(match.intentName)' via '\(match.matchedPhrase)' slots=\(matchedSlots)")

            do {
                let result = try matcher.execute(match)
                executionResult = "ok"
                executionData = result
                DiagnosticLog.shared.info("AudioLayer: executed '\(match.intentName)' → ok")
            } catch {
                DiagnosticLog.shared.info("AudioLayer: intent error — \(error.localizedDescription), falling back to Claude")
                executionResult = "thinking..."
                executionData = nil
                claudeFallback(transcription: transcription)
            }

            // Fire parallel Haiku advisor for 5+ word utterances
            fireAdvisor(transcript: transcription.text, matched: "\(match.intentName)(\(matchedSlots))")

        } else {
            // No local match — Claude fallback
            DiagnosticLog.shared.info("AudioLayer: no phrase match for '\(transcription.text)', falling back to Claude")
            matchedIntent = nil
            matchedSlots = [:]
            executionResult = "thinking..."
            executionData = nil
            claudeFallback(transcription: transcription)
        }
    }

    /// Fire the Haiku advisor in parallel — non-blocking, result arrives later.
    private func fireAdvisor(transcript: String, matched: String) {
        let haiku = AgentPool.shared.haiku
        guard haiku.isReady else {
            DiagnosticLog.shared.info("AudioLayer: advisor skipped (haiku not ready)")
            return
        }

        let message = "Transcript: \"\(transcript)\"\nMatched: \(matched)"
        DiagnosticLog.shared.info("AudioLayer: firing haiku advisor")

        haiku.send(message: message) { [weak self] response in
            guard let self = self, let response = response else { return }
            self.agentResponse = response
            if let commentary = response.commentary {
                DiagnosticLog.shared.info("AudioLayer: haiku says — \(commentary)")
            }
            if let suggestion = response.suggestion {
                DiagnosticLog.shared.info("AudioLayer: haiku suggests — \(suggestion.label) → \(suggestion.intent)")
            }
        }
    }

    private func claudeFallback(transcription: Transcription) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let result = ClaudeFallback.resolve(
                transcript: transcription.text,
                windows: DesktopModel.shared.windows.values.map { $0 },
                intentCatalog: PhraseMatcher.shared.catalog()
            )

            DispatchQueue.main.async {
                guard let resolved = result else {
                    self.executionResult = "Claude couldn't resolve intent"
                    DiagnosticLog.shared.info("AudioLayer: Claude fallback returned nil")
                    return
                }

                DiagnosticLog.shared.info("AudioLayer: Claude resolved → \(resolved.intent) \(resolved.slots)")
                self.matchedIntent = resolved.intent
                self.matchedSlots = resolved.slots.reduce(into: [:]) { dict, pair in
                    dict[pair.key] = pair.value.stringValue ?? "\(pair.value)"
                }

                let intentMatch = IntentMatch(
                    intentName: resolved.intent,
                    slots: resolved.slots,
                    confidence: 0.8,
                    matchedPhrase: "claude-fallback"
                )

                do {
                    let execResult = try PhraseMatcher.shared.execute(intentMatch)
                    self.executionResult = "ok"
                    self.executionData = execResult
                    DiagnosticLog.shared.info("AudioLayer: Claude-resolved executed → \(execResult)")
                } catch {
                    self.executionResult = error.localizedDescription
                    self.executionData = nil
                    DiagnosticLog.shared.info("AudioLayer: Claude-resolved execution error — \(error.localizedDescription)")
                }
            }
        }
    }
}

// Old IntentExtractor removed — PhraseMatcher handles all intent matching now.
// See app/Sources/Intents/LatticeIntent.swift


// MARK: - Vox Audio Provider (WebSocket JSON-RPC via VoxClient)
//
// Delegates recording and transcription entirely to the Vox daemon (voxd).
// Lattices never touches the mic — Vox owns the mic, recording, and
// transcription. We call transcribe.startSession to begin recording
// and transcribe.stopSession to stop and get the transcript.
//
// Session events flow on the startSession call ID:
//   session.state: {state, sessionId, previous}
//   session.final: {sessionId, text, words[], elapsedMs, metrics}

final class VoxAudioProvider: AudioProvider {
    private var onTranscript: ((Transcription) -> Void)?
    private var stopCompletion: ((Transcription?) -> Void)?
    private var _isListening = false
    private var startTime: Date?

    var isAvailable: Bool {
        VoxClient.shared.connectionState == .connected
    }

    var isListening: Bool { _isListening }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        let client = VoxClient.shared
        if client.connectionState == .connected {
            client.call(method: "health") { result in
                switch result {
                case .success: DispatchQueue.main.async { completion(true) }
                case .failure: DispatchQueue.main.async { completion(false) }
                }
            }
        } else {
            completion(false)
        }
    }

    func startListening(onTranscript: @escaping (Transcription) -> Void) {
        let client = VoxClient.shared
        guard client.connectionState == .connected else {
            DiagnosticLog.shared.warn("VoxAudioProvider: not connected to Vox")
            onTranscript(Transcription(text: "", confidence: 0, source: "vox", isPartial: false, durationMs: nil))
            return
        }

        self.onTranscript = onTranscript
        _isListening = true
        startTime = Date()

        DiagnosticLog.shared.info("VoxAudioProvider: starting session via Vox")

        // transcribe.startSession — Vox records from mic, emits session events on this call ID
        client.startSession(
            onProgress: { [weak self] event, data in
                guard let self else { return }
                DispatchQueue.main.async {
                    switch event {
                    case "session.state":
                        let state = data["state"] as? String ?? ""
                        DiagnosticLog.shared.info("VoxAudioProvider: session → \(state)")

                    case "session.final":
                        // Final transcript arrived — deliver it
                        if let text = data["text"] as? String, !text.isEmpty {
                            let elapsed = data["elapsedMs"] as? Int
                            let t = Transcription(
                                text: text, confidence: 0.95, source: "vox",
                                isPartial: false, durationMs: elapsed
                            )
                            DiagnosticLog.shared.info("VoxAudioProvider: transcribed → '\(text)' (\(elapsed ?? 0)ms)")
                            self.onTranscript?(t)
                            self.stopCompletion?(t)
                            self.stopCompletion = nil
                        }

                    default:
                        break
                    }
                }
            },
            completion: { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    self._isListening = false

                    switch result {
                    case .success(let data):
                        // Final result also comes here (same data as session.final)
                        if let text = data["text"] as? String, !text.isEmpty,
                           self.stopCompletion != nil {
                            // Only deliver if session.final didn't already
                            let elapsed = data["elapsedMs"] as? Int
                            let t = Transcription(
                                text: text, confidence: 0.95, source: "vox",
                                isPartial: false, durationMs: elapsed
                            )
                            self.onTranscript?(t)
                            self.stopCompletion?(t)
                            self.stopCompletion = nil
                        } else if self.stopCompletion != nil {
                            self.stopCompletion?(nil)
                            self.stopCompletion = nil
                        }

                    case .failure(let error):
                        DiagnosticLog.shared.warn("VoxAudioProvider: session error — \(error.localizedDescription)")
                        if case .sessionBusy = error {
                            AudioLayer.shared.executionResult = "Session already active"
                        } else {
                            AudioLayer.shared.executionResult = "Transcription failed"
                        }
                        self.onTranscript?(Transcription(
                            text: "", confidence: 0, source: "vox",
                            isPartial: false, durationMs: nil
                        ))
                        self.stopCompletion?(nil)
                        self.stopCompletion = nil
                    }
                }
            }
        )
    }

    func stopListening(completion: @escaping (Transcription?) -> Void) {
        _isListening = false

        let client = VoxClient.shared
        guard client.connectionState == .connected else {
            completion(nil)
            return
        }

        DiagnosticLog.shared.info("VoxAudioProvider: stopping session")

        // Store completion — the startSession's session.final event delivers the transcript
        self.stopCompletion = completion

        client.stopSession { result in
            if case .failure(let error) = result {
                DiagnosticLog.shared.warn("VoxAudioProvider: stopSession error — \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.stopCompletion?(nil)
                    self.stopCompletion = nil
                }
            }
        }
    }
}
