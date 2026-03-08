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
    @Published var provider: (any AudioProvider)?
    @Published var providerName: String = "none"

    private init() {
        // Try to discover Talkie on startup
        let talkie = TalkieAudioProvider()
        talkie.checkHealth { available in
            DispatchQueue.main.async {
                if available {
                    self.provider = talkie
                    self.providerName = "talkie"
                    DiagnosticLog.shared.info("AudioLayer: Talkie discovered")
                } else {
                    DiagnosticLog.shared.info("AudioLayer: no audio provider found")
                }
            }
        }

        // Listen for Talkie coming online via DistributedNotification
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.jdi.talkie.agent.live.ready"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard self?.provider == nil else { return }
            let talkie = TalkieAudioProvider()
            talkie.checkHealth { available in
                DispatchQueue.main.async {
                    if available {
                        self?.provider = talkie
                        self?.providerName = "talkie"
                        DiagnosticLog.shared.info("AudioLayer: Talkie came online")
                    }
                }
            }
        }
    }

    /// Start a voice command capture. Transcription is piped to the intent engine.
    func startVoiceCommand() {
        guard let provider = provider, !isListening else { return }

        isListening = true
        lastTranscript = nil
        matchedIntent = nil
        matchedSlots = [:]
        matchConfidence = 0
        executionResult = nil

        provider.startListening { [weak self] transcription in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if transcription.isPartial {
                    self.lastTranscript = transcription.text
                    return
                }

                // Final transcript — execute intent
                self.lastTranscript = transcription.text
                self.isListening = false

                DiagnosticLog.shared.info("AudioLayer: received '\(transcription.text)' (confidence: \(transcription.confidence))")

                // Post as event so connected agents can see it
                EventBus.shared.post(.voiceCommand(text: transcription.text, confidence: transcription.confidence))

                // Route to intent engine
                self.executeVoiceIntent(transcription)
            }
        }
    }

    func stopVoiceCommand() {
        guard let provider = provider, isListening else { return }

        provider.stopListening { [weak self] transcription in
            DispatchQueue.main.async {
                self?.isListening = false
                if let t = transcription {
                    self?.lastTranscript = t.text
                    self?.executeVoiceIntent(t)
                }
            }
        }
    }

    private func executeVoiceIntent(_ transcription: Transcription) {
        let extracted = IntentExtractor.extract(
            text: transcription.text,
            catalog: IntentEngine.shared.catalog()
        )

        guard let intent = extracted else {
            DiagnosticLog.shared.info("AudioLayer: no intent matched for '\(transcription.text)'")
            matchedIntent = nil
            executionResult = "No intent matched"
            return
        }

        matchedIntent = intent.name
        matchConfidence = intent.confidence
        // Flatten slots to string for display
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
            executionResult = "ok"
            DiagnosticLog.shared.info("AudioLayer: executed '\(intent.name)' → \(result)")
        } catch {
            executionResult = error.localizedDescription
            DiagnosticLog.shared.info("AudioLayer: intent error — \(error.localizedDescription)")
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
            ]),
            ("list_windows", [
                "what windows are open", "show all windows", "list windows",
                "what's on screen", "which windows are visible",
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
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

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
            return extractTargetSlot(from: text, prefixes: ["search for", "find", "look for", "where is", "where does it say"], slotName: "query")
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

// MARK: - Talkie Audio Provider (WebSocket Bridge)
//
// Connects to TalkieAgent (port 19821 engine, DistributedNotification for state)
// via the JSON-RPC WebSocket bridges that Talkie exposes on localhost.
// This avoids XPC entitlement issues between independently built apps.

final class TalkieAudioProvider: AudioProvider {
    private let enginePort = 19821
    private var onTranscript: ((Transcription) -> Void)?
    private var _isAvailable = false
    private var _isListening = false
    private var recordingTimer: Timer?

    var isAvailable: Bool { _isAvailable }
    var isListening: Bool { _isListening }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        // Ping the engine bridge to see if Talkie is up
        bridgeCall(port: enginePort, method: "status", params: nil) { [weak self] result, error in
            let ok = error == nil && result != nil
            self?._isAvailable = ok
            completion(ok)
        }
    }

    func startListening(onTranscript: @escaping (Transcription) -> Void) {
        self.onTranscript = onTranscript
        _isListening = true

        // Tell TalkieAgent to start recording via DistributedNotification
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.jdi.talkie.lattices.startRecording"),
            object: nil,
            userInfo: ["source": "lattices"],
            deliverImmediately: true
        )

        DiagnosticLog.shared.info("TalkieAudioProvider: requested recording start via notification")

        // Listen for transcription result
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleTranscriptionResult(_:)),
            name: Notification.Name("com.jdi.talkie.agent.dictation.new"),
            object: nil
        )
    }

    func stopListening(completion: @escaping (Transcription?) -> Void) {
        _isListening = false

        // Tell TalkieAgent to stop recording
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.jdi.talkie.lattices.stopRecording"),
            object: nil,
            userInfo: ["source": "lattices"],
            deliverImmediately: true
        )

        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Notification.Name("com.jdi.talkie.agent.dictation.new"),
            object: nil
        )

        // The transcription will arrive async via handleTranscriptionResult
        // For now, return nil — the callback handles it
        completion(nil)
    }

    @objc private func handleTranscriptionResult(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let text = userInfo["transcript"] as? String else {
            DiagnosticLog.shared.info("TalkieAudioProvider: got notification but no transcript")
            return
        }

        let confidence = (userInfo["confidence"] as? Double) ?? 0.9
        let transcription = Transcription(
            text: text,
            confidence: confidence,
            source: "talkie",
            isPartial: false,
            durationMs: userInfo["durationMs"] as? Int
        )

        _isListening = false
        onTranscript?(transcription)

        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Notification.Name("com.jdi.talkie.agent.dictation.new"),
            object: nil
        )
    }

    /// Transcribe an audio file directly via the engine bridge
    func transcribeFile(path: String, completion: @escaping (String?) -> Void) {
        bridgeCall(port: enginePort, method: "transcribe", params: ["audioPath": path]) { result, error in
            if let result = result,
               let transcript = (result as? [String: Any])?["transcript"] as? String {
                completion(transcript)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - WebSocket Bridge RPC

    private func bridgeCall(port: Int, method: String, params: [String: Any]?, completion: @escaping (Any?, String?) -> Void) {
        // Use a raw TCP socket to do a single WebSocket RPC call
        // (Same pattern as Lattices' own daemon client)
        let id = UUID().uuidString
        var payload: [String: Any] = ["id": id, "method": method]
        if let params = params { payload["params"] = params }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            completion(nil, "JSON serialization failed")
            return
        }

        // Open TCP connection to bridge
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            completion(nil, "socket() failed")
            return
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard connectResult == 0 else {
            close(fd)
            completion(nil, "connect() failed")
            return
        }

        // Send WebSocket upgrade
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let upgrade = "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        upgrade.utf8.withContiguousStorageIfAvailable { buf in
            _ = send(fd, buf.baseAddress, buf.count, 0)
        }

        // Read upgrade response (simplified — just drain until \r\n\r\n)
        var headerBuf = [UInt8](repeating: 0, count: 4096)
        _ = recv(fd, &headerBuf, headerBuf.count, 0)

        // Send WebSocket text frame with mask
        let frameData = Array(jsonStr.utf8)
        var frame = [UInt8]()
        frame.append(0x81) // FIN + text
        let mask: [UInt8] = (0..<4).map { _ in UInt8.random(in: 0...255) }
        if frameData.count < 126 {
            frame.append(UInt8(frameData.count) | 0x80)
        } else {
            frame.append(126 | 0x80)
            frame.append(UInt8(frameData.count >> 8))
            frame.append(UInt8(frameData.count & 0xFF))
        }
        frame.append(contentsOf: mask)
        for (i, byte) in frameData.enumerated() {
            frame.append(byte ^ mask[i % 4])
        }
        _ = send(fd, frame, frame.count, 0)

        // Read response frame
        DispatchQueue.global().async {
            var respBuf = [UInt8](repeating: 0, count: 65536)
            let n = recv(fd, &respBuf, respBuf.count, 0)
            close(fd)

            guard n > 2 else {
                completion(nil, "empty response")
                return
            }

            // Parse WebSocket frame (server frames are unmasked)
            var offset = 2
            var payloadLen = Int(respBuf[1] & 0x7F)
            if payloadLen == 126 {
                payloadLen = Int(respBuf[2]) << 8 | Int(respBuf[3])
                offset = 4
            }

            guard offset + payloadLen <= n else {
                completion(nil, "truncated frame")
                return
            }

            let payloadBytes = Array(respBuf[offset..<(offset + payloadLen)])
            if let str = String(bytes: payloadBytes, encoding: .utf8),
               let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] as? String {
                    completion(nil, error)
                } else {
                    completion(json["result"], nil)
                }
            } else {
                completion(nil, "parse failed")
            }
        }
    }
}
