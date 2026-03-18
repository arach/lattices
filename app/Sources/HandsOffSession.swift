import AppKit

/// Hands-off voice mode: a warm sidecar agent with full Lattices context.
///
/// Architecture:
///   - **System prompt** (loaded once): teaches the agent everything it can do —
///     intents, tiling, stages, layers, search, focus. This is the "preparation".
///   - **Per-turn snapshot**: each user message includes a structured context snapshot
///     of the current desktop state — active stage windows, strip thumbnails, layers,
///     SM preferences. The agent sees exactly what's relevant.
///   - **Persistent session**: conversation carries over between turns. The agent
///     builds understanding of the user's workflow over time (in-context learning).
///   - **Context management**: AgentSession auto-resets at 75% context usage,
///     so the sidecar never gets stuck.
///
/// The agent responds with JSON: actions to execute + optional spoken commentary.
/// No panel, no UI. Sound feedback only.

final class HandsOffSession: ObservableObject {
    static let shared = HandsOffSession()

    enum State: Equatable {
        case idle
        case connecting
        case listening
        case thinking
        case speaking
    }

    @Published var state: State = .idle
    @Published var lastTranscript: String?
    @Published var lastResponse: String?

    private let agent: AgentSession
    private var turnCount = 0

    private init() {
        agent = AgentSession(model: "sonnet", label: "hands-off")
        agent.customSystemPrompt = { Self.buildSidecarPrompt() }
    }

    // MARK: - Lifecycle

    func start() {
        agent.start()
        DiagnosticLog.shared.info("HandsOff: sidecar agent ready")
    }

    // MARK: - Sidecar system prompt (loaded once, teaches the agent everything)

    private static func buildSidecarPrompt() -> String {
        // Gather intent catalog
        let intentList = PhraseMatcher.shared.catalog()
        var intentDocs = ""
        if case .array(let intents) = intentList {
            intentDocs = intents.compactMap { intent -> String? in
                guard let name = intent["intent"]?.stringValue else { return nil }
                let desc = intent["description"]?.stringValue ?? ""
                var slotDocs: [String] = []
                if case .array(let slots) = intent["slots"] {
                    slotDocs = slots.compactMap { slot -> String? in
                        guard let sn = slot["name"]?.stringValue else { return nil }
                        let req = slot["required"]?.boolValue == true ? " (required)" : ""
                        return "    \(sn)\(req)"
                    }
                }
                let slotStr = slotDocs.isEmpty ? "" : "\n" + slotDocs.joined(separator: "\n")
                return "  \(name): \(desc)\(slotStr)"
            }.joined(separator: "\n")
        }

        return """
        You are the Lattices hands-off sidecar — a persistent voice assistant for a macOS workspace manager.

        You receive voice transcripts (may contain typos from Whisper) with a desktop snapshot showing the current state. You can take actions and/or respond conversationally.

        # Response format
        Respond with ONLY a JSON object:
        ```
        {
          "actions": [
            {"intent": "intent_name", "slots": {"key": "value"}}
          ],
          "spoken": "Short spoken response (1-2 sentences max, conversational)"
        }
        ```
        - "actions": array of intents to execute. Empty array [] if no action needed.
        - "spoken": what to say back. null if silent execution is fine.
        - Keep spoken responses SHORT — this is voice, not text.

        # Available intents
        \(intentDocs)

        # Stage Manager
        When Stage Manager is ON, windows are grouped into "stages". The snapshot shows:
        - Active stage: windows currently visible and usable
        - Strip: thumbnail previews of other stages on the left edge
        - Other stages: apps hidden in inactive stages

        You can tile windows within the active stage using tile_window with positions:
        left, right, top, bottom, maximize, center, top-left, top-right, bottom-left, bottom-right, left-third, center-third, right-third

        The "distribute" intent arranges all visible windows in a smart grid.

        # Layers
        Lattices has workspace layers (like virtual desktops with window arrangements).
        Use switch_layer to change layers, create_layer to save current arrangement.

        # Guidelines
        - Parse voice transcripts generously — "tile chrome left" means tile_window with app=chrome, position=left
        - If the request is conversational (question, observation), just respond with spoken text, no actions
        - If the request is an action, execute it and optionally confirm with brief spoken feedback
        - You have full conversation history — refer back to prior turns naturally
        - When uncertain, ask for clarification via spoken response
        - Be terse. This is hands-off mode — the user doesn't want to look at a screen.
        """
    }

    func toggle() {
        switch state {
        case .idle:
            beginListening()
        case .listening:
            finishListening()
        case .thinking, .speaking:
            DiagnosticLog.shared.info("HandsOff: busy, ignoring toggle")
        case .connecting:
            cancel()
        }
    }

    func cancel() {
        if AudioLayer.shared.isListening {
            AudioLayer.shared.provider?.stopListening { _ in }
        }
        state = .idle
        DiagnosticLog.shared.info("HandsOff: cancelled")
    }

    // MARK: - Voice capture

    private func beginListening() {
        let client = TalkieClient.shared

        if client.connectionState != .connected {
            state = .connecting
            client.connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.retryListenIfConnected(attempts: 5)
            }
            return
        }

        startDictation()
    }

    private func retryListenIfConnected(attempts: Int) {
        if TalkieClient.shared.connectionState == .connected {
            startDictation()
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.retryListenIfConnected(attempts: attempts - 1)
            }
        } else {
            state = .idle
            DiagnosticLog.shared.warn("HandsOff: Talkie not available")
            playSound("Basso")
        }
    }

    private func startDictation() {
        state = .listening
        lastTranscript = nil
        playSound("Tink")

        DiagnosticLog.shared.info("HandsOff: listening...")

        TalkieClient.shared.callStreaming(
            method: "startDictation",
            params: ["persist": false, "source": "lattices-handsoff"],
            onProgress: { [weak self] event, data in
                DispatchQueue.main.async {
                    if event == "partialTranscript", let text = data["text"] as? String {
                        self?.lastTranscript = text
                    }
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let data):
                        let text = (data["transcript"] as? String) ?? (data["text"] as? String) ?? ""
                        if text.isEmpty {
                            self.state = .idle
                            DiagnosticLog.shared.info("HandsOff: no speech detected")
                        } else {
                            self.lastTranscript = text
                            DiagnosticLog.shared.info("HandsOff: heard → '\(text)'")
                            self.sendToClaude(text)
                        }
                    case .failure(let error):
                        self.state = .idle
                        DiagnosticLog.shared.warn("HandsOff: dictation error — \(error.localizedDescription)")
                        self.playSound("Basso")
                    }
                }
            }
        )
    }

    func finishListening() {
        guard state == .listening else { return }
        TalkieClient.shared.call(method: "stopDictation") { _ in }
    }

    // MARK: - Claude sidecar conversation

    private func sendToClaude(_ text: String) {
        state = .thinking
        turnCount += 1

        let message = buildTurnMessage(text)

        agent.send(message: message) { [weak self] response in
            guard let self else { return }

            if let response {
                self.lastResponse = response.raw
                DiagnosticLog.shared.info("HandsOff: Claude → \(response.raw.prefix(300))")

                // Execute any actions
                self.executeActions(from: response.raw)

                // Speak commentary
                let spoken = response.commentary ?? self.extractSpoken(from: response.raw)
                if let spoken, !spoken.isEmpty {
                    self.speakResponse(spoken)
                } else {
                    self.state = .idle
                    self.playSound("Pop")
                }
            } else {
                self.lastResponse = nil
                self.state = .idle
                DiagnosticLog.shared.warn("HandsOff: Claude returned nil")
                self.playSound("Basso")
            }
        }
    }

    // MARK: - Per-turn context snapshot

    private func buildTurnMessage(_ userText: String) -> String {
        var msg = ""

        // The user's request (voice transcript, may have typos)
        msg += "USER: \"\(userText)\"\n\n"

        // Desktop snapshot — only include what's relevant
        msg += "--- DESKTOP SNAPSHOT ---\n"

        let allWindows = Array(DesktopModel.shared.windows.values)

        // Stage Manager state
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        if smEnabled {
            let grouping = UserDefaults(suiteName: "com.apple.WindowManager")?.integer(forKey: "AppWindowGroupingBehavior") ?? 0

            // Active stage windows (large, onscreen)
            let activeStage = allWindows.filter { $0.isOnScreen && $0.frame.w > 250 }
            // Strip thumbnails (small, onscreen, left edge)
            let stripThumbs = allWindows.filter {
                $0.isOnScreen && $0.frame.w < 250 && $0.frame.w > 50 && $0.frame.x < 220 && $0.frame.x >= 0
            }
            // Hidden in other stages
            let hidden = allWindows.filter { !$0.isOnScreen && $0.frame.w > 250 }
            let hiddenApps = Set(hidden.map(\.app)).sorted()

            msg += "Stage Manager: ON (grouping: \(grouping == 0 ? "all-at-once" : "one-at-a-time"))\n"
            msg += "\nActive stage (\(activeStage.count) windows):\n"
            for w in activeStage {
                msg += "  [\(w.wid)] \(w.app): \"\(w.title)\" — \(Int(w.frame.x)),\(Int(w.frame.y)) \(Int(w.frame.w))x\(Int(w.frame.h))\n"
            }
            msg += "\nStrip (\(stripThumbs.count) thumbnails): \(Set(stripThumbs.map(\.app)).sorted().joined(separator: ", "))\n"
            msg += "Other stages: \(hiddenApps.joined(separator: ", "))\n"
        } else {
            let onscreen = allWindows.filter { $0.isOnScreen }
            msg += "Stage Manager: OFF\n"
            msg += "Visible windows (\(onscreen.count)):\n"
            for w in onscreen.prefix(20) {
                msg += "  [\(w.wid)] \(w.app): \"\(w.title)\" — \(Int(w.frame.x)),\(Int(w.frame.y)) \(Int(w.frame.w))x\(Int(w.frame.h))\n"
            }
        }

        // Layers
        let layerStore = SessionLayerStore.shared
        if layerStore.activeIndex >= 0 && layerStore.activeIndex < layerStore.layers.count {
            let current = layerStore.layers[layerStore.activeIndex]
            msg += "\nCurrent layer: \(current.name) (index: \(layerStore.activeIndex))\n"
        }

        // Screen info
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            msg += "\nScreen: \(Int(screen.frame.width))x\(Int(screen.frame.height)), usable: \(Int(v.width))x\(Int(v.height))\n"
        }

        msg += "--- END SNAPSHOT ---\n"

        return msg
    }

    // MARK: - Action execution

    /// Parse and execute actions from Claude's response.
    /// Expected format: JSON with "actions" array and optional "spoken" text.
    private func executeActions(from raw: String) {
        guard let jsonStr = extractJSON(from: raw),
              let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Single action
        if let intent = json["intent"] as? String {
            executeIntent(intent, slots: json["slots"] as? [String: Any] ?? [:])
            return
        }

        // Multiple actions
        if let actions = json["actions"] as? [[String: Any]] {
            for action in actions {
                guard let intent = action["intent"] as? String else { continue }
                executeIntent(intent, slots: action["slots"] as? [String: Any] ?? [:])
            }
        }
    }

    private func executeIntent(_ intentName: String, slots: [String: Any]) {
        let jsonSlots = slots.reduce(into: [String: JSON]()) { dict, pair in
            if let s = pair.value as? String {
                dict[pair.key] = .string(s)
            } else if let n = pair.value as? Int {
                dict[pair.key] = .int(n)
            } else if let b = pair.value as? Bool {
                dict[pair.key] = .bool(b)
            }
        }

        let match = IntentMatch(
            intentName: intentName,
            slots: jsonSlots,
            confidence: 0.95,
            matchedPhrase: "hands-off-sidecar"
        )

        do {
            let result = try PhraseMatcher.shared.execute(match)
            DiagnosticLog.shared.info("HandsOff: executed '\(intentName)' → ok")

            // Log result summary
            if case .object(let obj) = result, let ok = obj["ok"]?.boolValue, ok {
                DiagnosticLog.shared.success("HandsOff: \(intentName) succeeded")
            }
        } catch {
            DiagnosticLog.shared.warn("HandsOff: \(intentName) failed — \(error.localizedDescription)")
        }
    }

    /// Extract the "spoken" field from a JSON response, or return nil.
    private func extractSpoken(from raw: String) -> String? {
        guard let jsonStr = extractJSON(from: raw),
              let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Not JSON — treat the whole response as spoken text
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        return json["spoken"] as? String
    }

    private func extractJSON(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }
        return String(cleaned[start...end])
    }

    // MARK: - TTS

    private func speakResponse(_ text: String) {
        state = .speaking

        let client = TalkieClient.shared
        if client.connectionState == .connected {
            client.call(method: "speak", params: ["text": text, "source": "lattices-handsoff"]) { [weak self] result in
                DispatchQueue.main.async {
                    if case .failure = result {
                        // Talkie TTS not available — system fallback
                        let synth = NSSpeechSynthesizer()
                        synth.startSpeaking(text)
                    }
                    self?.state = .idle
                    self?.playSound("Pop")
                }
            }
        } else {
            let synth = NSSpeechSynthesizer()
            synth.startSpeaking(text)
            state = .idle
            playSound("Pop")
        }
    }

    // MARK: - Sound feedback

    private func playSound(_ name: NSSound.Name) {
        NSSound(named: name)?.play()
    }
}
