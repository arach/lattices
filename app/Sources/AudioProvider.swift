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
        let extracted = IntentExtractor.extract(
            text: transcription.text,
            catalog: IntentEngine.shared.catalog()
        )

        if let intent = extracted {
            matchedIntent = intent.name
            matchConfidence = intent.confidence
            matchedSlots = intent.slots.reduce(into: [:]) { dict, pair in
                dict[pair.key] = pair.value.stringValue ?? "\(pair.value)"
            }

            let request = IntentRequest(
                intent: intent.name,
                slots: intent.slots,
                rawText: transcription.text,
                confidence: transcription.confidence,
                source: transcription.source
            )

            do {
                let result = try IntentEngine.shared.execute(request)
                // If search returned empty, fall back to Claude
                if intent.name == "search", case .array(let items) = result, items.isEmpty {
                    DiagnosticLog.shared.info("AudioLayer: search returned 0 results, falling back to Claude")
                    executionResult = "searching..."
                    executionData = nil
                    claudeFallback(transcription: transcription)
                    return
                }
                executionResult = "ok"
                executionData = result
                DiagnosticLog.shared.info("AudioLayer: executed '\(intent.name)' → \(result)")
            } catch {
                // Local execution failed — try Claude
                DiagnosticLog.shared.info("AudioLayer: intent error — \(error.localizedDescription), falling back to Claude")
                executionResult = "thinking..."
                executionData = nil
                claudeFallback(transcription: transcription)
            }
        } else {
            // No local match at all — Claude fallback
            DiagnosticLog.shared.info("AudioLayer: no local match for '\(transcription.text)', falling back to Claude")
            matchedIntent = nil
            matchedSlots = [:]
            executionResult = "thinking..."
            executionData = nil
            claudeFallback(transcription: transcription)
        }
    }

    private func claudeFallback(transcription: Transcription) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let result = ClaudeFallback.resolve(
                transcript: transcription.text,
                windows: DesktopModel.shared.windows.values.map { $0 },
                intentCatalog: IntentEngine.shared.catalog()
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

                let request = IntentRequest(
                    intent: resolved.intent,
                    slots: resolved.slots,
                    rawText: transcription.text,
                    confidence: 0.8,
                    source: "claude"
                )

                do {
                    let execResult = try IntentEngine.shared.execute(request)
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

// MARK: - Intent Extractor (NLEmbedding + keyword fallback)

import NaturalLanguage

struct ExtractedIntent {
    let name: String
    let slots: [String: JSON]
    let confidence: Double
}

/// Three-tier intent extraction using Apple NaturalLanguage framework:
/// 1. Exact/substring match (confidence 1.0 / 0.95)
/// 2. NLEmbedding semantic similarity (confidence = cosine similarity)
/// 3. Returns nil if nothing matches above threshold
final class IntentExtractor {
    static let shared = IntentExtractor()

    private let embedding: NLEmbedding?
    private let threshold: Double = 0.6

    // Pre-computed: (phrase, intentName, phraseVector)
    private var phraseIndex: [(phrase: String, intent: String, vector: [Double])] = []

    // Intents that take a free-text slot extracted from the utterance
    private static let slotExtractors: [String: SlotExtractor] = [
        "tile_window": .tilePosition,
        "focus": .appTarget,
        "launch": .projectTarget,
        "switch_layer": .layerTarget,
        "search": .queryTarget,
        "kill": .sessionTarget,
        "create_layer": .nameTarget,
    ]

    private init() {
        embedding = NLEmbedding.wordEmbedding(for: .english)
        buildIndex()

        if embedding != nil {
            DiagnosticLog.shared.info("IntentExtractor: NLEmbedding loaded, \(phraseIndex.count) phrases indexed")
        } else {
            DiagnosticLog.shared.info("IntentExtractor: NLEmbedding unavailable, using keyword fallback only")
        }
    }

    // MARK: - Index Building

    private func buildIndex() {
        // All intent → example phrase mappings
        let intentPhrases: [(intent: String, phrases: [String])] = [
            ("tile_window", [
                "tile left", "snap left", "move to the left", "put it on the left",
                "tile right", "snap right", "move to the right", "put it on the right",
                "maximize", "full screen", "make it big", "go full screen",
                "center the window", "put it in the center",
                "top left corner", "upper left", "top right corner", "upper right",
                "bottom left corner", "lower left", "bottom right corner", "lower right",
                "tile this window", "snap this window", "arrange the window",
            ]),
            ("focus", [
                "switch to", "focus on", "go to", "show me", "bring up",
                "switch to chrome", "focus the terminal", "show slack",
                "open finder", "go to safari", "bring up xcode",
            ]),
            ("launch", [
                "launch the project", "start working on", "open project",
                "launch frontend", "start the api", "open my app",
                "work on the backend", "begin coding",
            ]),
            ("switch_layer", [
                "switch to layer", "go to layer", "layer one", "layer two",
                "switch workspace", "change layer", "activate layer",
                "switch to the web layer", "go to mobile", "layer review",
            ]),
            ("search", [
                "search for", "find text", "look for", "where does it say",
                "search the screen", "find on screen", "where is the error",
                "find todo", "search error message",
                "find all", "find terminal", "find chrome", "find safari",
                "find windows", "find all windows", "find all terminal windows",
                "search windows", "search for windows",
            ]),
            ("list_windows", [
                "what windows are open", "show all windows", "list windows",
                "what's on screen", "which windows are visible",
                "list all windows", "show me all the windows",
            ]),
            ("list_sessions", [
                "what sessions are running", "list sessions", "show my projects",
                "what's running", "whats running", "which projects are active",
                "show me whats running", "show me what is running",
            ]),
            ("distribute", [
                "distribute windows", "spread out the windows", "organize windows",
                "clean up the layout", "arrange everything evenly",
                "tidy up the desktop", "even out the windows",
                "arrange my windows", "arrange windows neatly", "organize my windows",
            ]),
            ("create_layer", [
                "save this layout", "create a layer", "make a new layer",
                "save as layer", "snapshot this arrangement",
            ]),
            ("kill", [
                "kill the session", "stop the project", "shut it down",
                "close the session", "terminate", "kill the frontend",
            ]),
            ("scan", [
                "scan the screen", "read the screen", "ocr scan",
                "update screen text", "capture screen text",
                "what's on my screen", "read all windows",
            ]),
        ]

        for (intent, phrases) in intentPhrases {
            for phrase in phrases {
                let vec = sentenceVector(phrase)
                phraseIndex.append((phrase: phrase.lowercased(), intent: intent, vector: vec))
            }
        }
    }

    // MARK: - Extraction

    static func extract(text: String, catalog: JSON) -> ExtractedIntent? {
        shared.classify(text: text)
    }

    func classify(text: String) -> ExtractedIntent? {
        var lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing punctuation (Whisper adds periods)
        lower = lower.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
        // Strip speech disfluencies
        let disfluencies = ["um ", "uh ", "like ", "no sorry ", "sorry ", "no wait ", "wait ", "actually ", "okay ", "ok "]
        for d in disfluencies {
            lower = lower.replacingOccurrences(of: d, with: "")
        }
        lower = lower.trimmingCharacters(in: .whitespaces)

        // Tier 1: Exact match
        for entry in phraseIndex {
            if lower == entry.phrase {
                return buildResult(intent: entry.intent, text: lower, confidence: 1.0)
            }
        }

        // Tier 2: Substring match (phrase must be >3 chars to avoid false positives)
        // Pick the longest matching phrase to avoid partial matches winning
        var bestSubstring: (intent: String, phraseLen: Int)? = nil
        for entry in phraseIndex where entry.phrase.count > 3 {
            if lower.contains(entry.phrase) {
                if bestSubstring == nil || entry.phrase.count > bestSubstring!.phraseLen {
                    bestSubstring = (entry.intent, entry.phrase.count)
                }
            }
        }
        if let sub = bestSubstring {
            return buildResult(intent: sub.intent, text: lower, confidence: 0.95)
        }

        // Tier 3: Semantic similarity via NLEmbedding
        if embedding != nil {
            let inputVec = sentenceVector(lower)
            guard !inputVec.isEmpty else { return nil }

            var bestIntent = ""
            var bestScore = 0.0

            for entry in phraseIndex {
                guard !entry.vector.isEmpty else { continue }
                let score = cosineSimilarity(inputVec, entry.vector)
                if score > bestScore {
                    bestScore = score
                    bestIntent = entry.intent
                }
            }

            if bestScore >= threshold {
                return buildResult(intent: bestIntent, text: lower, confidence: bestScore)
            }
        }

        return nil
    }

    // MARK: - Slot Extraction

    private func buildResult(intent: String, text: String, confidence: Double) -> ExtractedIntent {
        let slots: [String: JSON]
        if let extractor = Self.slotExtractors[intent] {
            slots = extractor.extract(from: text)
        } else {
            slots = [:]
        }
        return ExtractedIntent(name: intent, slots: slots, confidence: confidence)
    }

    // MARK: - Embedding Math

    private func sentenceVector(_ text: String) -> [Double] {
        guard let emb = embedding else { return [] }
        let words = text.lowercased().split(separator: " ").map(String.init)
        var sum: [Double]? = nil
        var count = 0

        for word in words {
            guard let vec = emb.vector(for: word) else { continue }
            if sum == nil { sum = [Double](repeating: 0, count: vec.count) }
            for i in 0..<vec.count { sum![i] += vec[i] }
            count += 1
        }

        guard var result = sum, count > 0 else { return [] }
        for i in 0..<result.count { result[i] /= Double(count) }
        return result
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}

// MARK: - Slot Extractors

private enum SlotExtractor {
    case tilePosition
    case appTarget
    case projectTarget
    case layerTarget
    case queryTarget
    case sessionTarget
    case nameTarget

    func extract(from text: String) -> [String: JSON] {
        switch self {
        case .tilePosition:
            return extractTileSlots(from: text)
        case .appTarget:
            return extractTargetSlot(from: text, prefixes: ["switch to", "focus on", "focus", "go to", "show", "open", "bring up"], slotName: "app")
        case .projectTarget:
            return extractTargetSlot(from: text, prefixes: ["open my", "open", "launch", "start working on", "start", "work on", "begin coding on", "begin"], slotName: "project")
        case .layerTarget:
            return extractTargetSlot(from: text, prefixes: ["switch to layer", "go to layer", "switch to", "go to", "activate layer", "activate", "change to layer", "change to", "layer"], slotName: "layer")
        case .queryTarget:
            var result = extractTargetSlot(from: text, prefixes: [
                "search for all instances of", "search for all", "search for",
                "search all the", "search all",
                "find all instances of", "find all the", "find all",
                "find instances of", "find the", "find",
                "look for all", "look for",
                "where is the", "where is",
                "where does it say",
            ], slotName: "query", stripSuffixes: ["windows", "instances", "apps", "applications", "terminals", "on screen", "on my screen"])
            // Clean up extracted query — strip filler phrases
            if var q = result["query"]?.stringValue {
                let fillerPhrases = [
                    "instances of ", "all the ", "all ",
                    "that mentioned ", "that mention ", "that say ", "that says ",
                    "talking about ", "related to ", "about ", "with ",
                    "alternate ", "alternative ",
                ]
                for filler in fillerPhrases {
                    q = q.replacingOccurrences(of: filler, with: "")
                }
                q = q.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty { result["query"] = .string(q) }
            }
            return result
        case .sessionTarget:
            return extractTargetSlot(from: text, prefixes: ["kill", "stop", "shut down", "close", "terminate"], slotName: "session", stripSuffixes: ["session", "project"])
        case .nameTarget:
            return extractTargetSlot(from: text, prefixes: ["create a layer called", "create layer called", "create a layer", "create layer", "save layout as", "save as", "make a layer called", "make layer called", "make a layer", "make layer"], slotName: "name")
        }
    }

    private func extractTileSlots(from text: String) -> [String: JSON] {
        let positionMap: [(keywords: [String], position: String)] = [
            (["top left", "upper left", "top-left"], "top-left"),
            (["top right", "upper right", "top-right"], "top-right"),
            (["bottom left", "lower left", "bottom-left"], "bottom-left"),
            (["bottom right", "lower right", "bottom-right"], "bottom-right"),
            (["left half", "tile left", "snap left", "to the left", "on the left", " left"], "left"),
            (["right half", "tile right", "snap right", "to the right", "on the right", " right"], "right"),
            (["maximize", "full screen", "make it big", "go full"], "maximize"),
            (["center", "in the center", "middle"], "center"),
        ]

        var slots: [String: JSON] = [:]
        for (keywords, position) in positionMap {
            if keywords.contains(where: { text.contains($0) }) {
                slots["position"] = .string(position)
                break
            }
        }
        // Default to "center" if no position detected
        if slots["position"] == nil { slots["position"] = .string("center") }

        // Extract app name
        let knownApps = ["chrome", "safari", "terminal", "iterm", "slack",
                         "discord", "figma", "xcode", "vscode", "code",
                         "finder", "notes", "messages", "mail", "cursor",
                         "warp", "ghostty", "kitty", "arc", "firefox"]
        for app in knownApps {
            if text.contains(app) {
                slots["app"] = .string(app.prefix(1).uppercased() + app.dropFirst())
                break
            }
        }
        return slots
    }

    private func extractTargetSlot(from text: String, prefixes: [String], slotName: String, stripSuffixes: [String] = []) -> [String: JSON] {
        for prefix in prefixes {
            if text.hasPrefix(prefix) || text.contains(prefix) {
                var target = text
                // Remove prefix (take the part after the prefix)
                if let range = text.range(of: prefix) {
                    target = String(text[range.upperBound...])
                }
                target = target.trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip leading articles
                for article in ["the ", "my ", "a ", "an "] {
                    if target.hasPrefix(article) {
                        target = String(target.dropFirst(article.count))
                    }
                }
                // Strip trailing noise words
                for suffix in stripSuffixes {
                    if target.hasSuffix(" " + suffix) {
                        target = String(target.dropLast(suffix.count + 1))
                    }
                }
                target = target.trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip trailing punctuation (Whisper often adds periods)
                target = target.trimmingCharacters(in: .punctuationCharacters)
                target = target.trimmingCharacters(in: .whitespacesAndNewlines)
                // Also strip "project" suffix for project targets
                if slotName == "project" && target.hasSuffix(" project") {
                    target = String(target.dropLast(8)).trimmingCharacters(in: .whitespaces)
                }
                if !target.isEmpty {
                    return [slotName: .string(target)]
                }
            }
        }
        return [:]
    }
}

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
