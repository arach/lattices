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

    private var pendingVoiceStart = false
    private var voiceConnectionRetry: DispatchWorkItem?

    private init() {
        let vox = VoxAudioProvider()
        provider = vox
        providerName = "vox"
        // Voice entry points can arrive from the desktop UI, daemon, or iOS
        // bridge, so connection setup is handled lazily when capture starts.
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

        pendingVoiceStart = true
        voiceConnectionRetry?.cancel()
        startVoiceCommandWhenReady(provider: provider, attempt: 0)
    }

    private func startVoiceCommandWhenReady(provider: any AudioProvider, attempt: Int) {
        guard pendingVoiceStart, !isListening else { return }

        if provider.isAvailable {
            pendingVoiceStart = false
            beginVoiceCommand(provider: provider)
            return
        }

        let client = VoxClient.shared
        if attempt == 0 {
            let launched = launchVoxIfNeeded()
            executionResult = launched ? "Starting Vox..." : "Connecting to Vox..."
            client.connect()
        } else if case .disconnected = client.connectionState {
            client.connect()
        } else if case .unavailable = client.connectionState {
            client.connect()
        }

        guard attempt < 40 else {
            pendingVoiceStart = false
            executionResult = "Vox unavailable — open Vox and try again"
            DiagnosticLog.shared.warn("AudioLayer: Vox connection failed before voice start")
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
                        self.executionResult = "No speech detected"
                    }
                    return
                }

                EventBus.shared.post(.voiceCommand(text: transcription.text, confidence: transcription.confidence))
                self.executeVoiceIntent(transcription)
            }
        }
    }

    private func launchVoxIfNeeded() -> Bool {
        guard VoxClient.shared.discoverDaemon() == nil else { return false }

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
            executionResult = "Voice cancelled"
            return
        }

        guard let provider = provider, isListening else { return }

        pendingVoiceStart = false
        isListening = false
        executionResult = "Transcribing..."

        provider.stopListening { [weak self] transcription in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let t = transcription,
                   !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                executionResult = voiceResultSummary(for: match, result: result)
                executionData = result
                DiagnosticLog.shared.info("AudioLayer: executed '\(match.intentName)' → \(executionResult ?? "ok")")
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
                    self.executionResult = self.voiceResultSummary(for: intentMatch, result: execResult)
                    self.executionData = execResult
                    DiagnosticLog.shared.info("AudioLayer: Claude-resolved executed → \(self.executionResult ?? "\(execResult)")")
                } catch {
                    self.executionResult = error.localizedDescription
                    self.executionData = nil
                    DiagnosticLog.shared.info("AudioLayer: Claude-resolved execution error — \(error.localizedDescription)")
                }
            }
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

        case "switch_layer":
            let target = match.slots["layer"]?.stringValue ?? "layer"
            return "Switched to \(target)"

        case "distribute_windows":
            return "Distributed visible windows"

        case "scan":
            return "Scanned the screen"

        default:
            return "Handled \(readableIntentName(match.intentName))"
        }
    }

    private func readableIntentName(_ intentName: String) -> String {
        intentName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
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
