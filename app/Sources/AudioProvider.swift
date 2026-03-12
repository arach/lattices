import AppKit

// MARK: - Audio Provider Protocol

/// A provider that can capture audio and return transcriptions.
/// Lattices doesn't do transcription itself — it delegates to an external
/// service (Talkie, Whisper, etc.) and maps the result to intents.
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
    let source: String           // "talkie", "whisper", etc.
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
        let talkie = TalkieAudioProvider()
        provider = talkie
        providerName = "talkie"
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

        guard let provider = provider else {
            executionResult = "No voice provider — install Talkie"
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

    func stopVoiceCommand() {
        guard let provider = provider, isListening else { return }

        isListening = false
        executionResult = "Transcribing..."

        provider.stopListening { [weak self] transcription in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let t = transcription {
                    self.lastTranscript = t.text
                    EventBus.shared.post(.voiceCommand(text: t.text, confidence: t.confidence))
                    self.executeVoiceIntent(t)
                } else {
                    self.executionResult = "No speech detected"
                }
            }
        }
    }

    private func executeVoiceIntent(_ transcription: Transcription) {
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
        let wordCount = transcript.split(separator: " ").count
        guard wordCount >= 5 else {
            DiagnosticLog.shared.info("AudioLayer: advisor skipped (\(wordCount) words, need 5+)")
            return
        }

        let haiku = AgentPool.shared.haiku
        guard haiku.isReady else {
            DiagnosticLog.shared.info("AudioLayer: advisor skipped (haiku not ready)")
            return
        }

        let message = "Transcript: \"\(transcript)\"\nMatched: \(matched)"
        DiagnosticLog.shared.info("AudioLayer: firing haiku advisor (\(wordCount) words)")

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


// MARK: - Talkie Audio Provider (WebSocket JSON-RPC via TalkieClient)
//
// Delegates recording and transcription entirely to TalkieAgent.
// Lattices never touches the mic — TalkieAgent owns the mic lifecycle,
// recording, and Whisper transcription. We just call startDictation
// and listen for streaming events.

final class TalkieAudioProvider: AudioProvider {
    private var onTranscript: ((Transcription) -> Void)?
    private var _isListening = false
    private var startTime: Date?

    var isAvailable: Bool {
        TalkieClient.shared.connectionState == .connected
    }

    var isListening: Bool { _isListening }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        let client = TalkieClient.shared
        if client.connectionState == .connected {
            client.ping { ok in
                DispatchQueue.main.async { completion(ok) }
            }
        } else {
            completion(false)
        }
    }

    func startListening(onTranscript: @escaping (Transcription) -> Void) {
        let client = TalkieClient.shared
        guard client.connectionState == .connected else {
            DiagnosticLog.shared.warn("TalkieAudioProvider: not connected to TalkieAgent")
            onTranscript(Transcription(text: "", confidence: 0, source: "talkie", isPartial: false, durationMs: nil))
            return
        }

        self.onTranscript = onTranscript
        _isListening = true
        startTime = Date()

        DiagnosticLog.shared.info("TalkieAudioProvider: starting dictation via TalkieAgent")

        // Call startDictation as a streaming RPC — TalkieAgent records and transcribes
        client.callStreaming(
            method: "startDictation",
            params: ["persist": false, "source": "lattices"],
            onProgress: { [weak self] event, data in
                guard let self else { return }
                DispatchQueue.main.async {
                    switch event {
                    case "stateChange":
                        let state = data["state"] as? String ?? ""
                        DiagnosticLog.shared.info("TalkieAudioProvider: state → \(state)")

                    case "partialTranscript":
                        if let text = data["text"] as? String {
                            self.onTranscript?(Transcription(
                                text: text, confidence: 0.5, source: "talkie",
                                isPartial: true, durationMs: nil
                            ))
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
                    let elapsed = self.startTime.map { Int(Date().timeIntervalSince($0) * 1000) }

                    switch result {
                    case .success(let data):
                        DiagnosticLog.shared.info("TalkieAudioProvider: response keys → \(Array(data.keys))")
                        if let text = (data["transcript"] as? String) ?? (data["text"] as? String) {
                            let confidence = data["confidence"] as? Double ?? 0.9
                            let t = Transcription(
                                text: text, confidence: confidence, source: "talkie",
                                isPartial: false, durationMs: elapsed
                            )
                            DiagnosticLog.shared.info("TalkieAudioProvider: transcribed → '\(text)'")
                            self.onTranscript?(t)
                        } else {
                            DiagnosticLog.shared.info("TalkieAudioProvider: no transcript in response")
                        }

                    case .failure(let error):
                        DiagnosticLog.shared.warn("TalkieAudioProvider: dictation error — \(error.localizedDescription)")
                        if case .micBusy(let owner) = error {
                            AudioLayer.shared.executionResult = "Mic in use by \(owner)"
                        } else {
                            AudioLayer.shared.executionResult = "Transcription failed"
                        }
                        // Notify with empty transcript so the UI updates
                        self.onTranscript?(Transcription(
                            text: "", confidence: 0, source: "talkie",
                            isPartial: false, durationMs: nil
                        ))
                    }
                }
            }
        )
    }

    func stopListening(completion: @escaping (Transcription?) -> Void) {
        _isListening = false

        let client = TalkieClient.shared
        guard client.connectionState == .connected else {
            completion(nil)
            return
        }

        DiagnosticLog.shared.info("TalkieAudioProvider: stopping dictation")

        // stopDictation tells TalkieAgent to finalize — the transcript comes
        // back through the streaming call's completion handler, not here.
        // We just ack the stop.
        client.call(method: "stopDictation") { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Transcript arrives via the startDictation streaming completion
                    break
                case .failure(let error):
                    DiagnosticLog.shared.warn("TalkieAudioProvider: stopDictation error — \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
    }
}
