import AppKit

// MARK: - Intent Definition

struct IntentDef {
    let name: String
    let description: String
    let examples: [String]           // Example phrases that map to this intent
    let slots: [IntentSlot]          // Named parameters extracted from the utterance
    let handler: (IntentRequest) throws -> JSON
}

struct IntentSlot {
    let name: String
    let type: String                 // "string", "int", "position", "query"
    let required: Bool
    let description: String
    let enumValues: [String]?        // For constrained slots like tile positions
}

struct IntentRequest {
    let intent: String
    let slots: [String: JSON]
    let rawText: String?             // Original transcription, for fallback matching
    let confidence: Double?          // Transcription confidence from voice service
    let source: String?              // "vox", "siri", "cli", etc.
}

// MARK: - Intent Engine

final class IntentEngine {
    static let shared = IntentEngine()

    private var intents: [String: IntentDef] = [:]
    private var intentOrder: [String] = []

    private init() {
        registerBuiltins()
    }

    func register(_ intent: IntentDef) {
        intents[intent.name] = intent
        if !intentOrder.contains(intent.name) {
            intentOrder.append(intent.name)
        }
    }

    func definitions() -> [IntentDef] {
        intentOrder.compactMap { intents[$0] }
    }

    // MARK: - Execution

    func execute(_ request: IntentRequest) throws -> JSON {
        // 1. Direct match by intent name
        if let def = intents[request.intent] {
            return try def.handler(request)
        }

        // 2. Fuzzy match by intent name (handle voice transcription typos)
        let normalized = request.intent.lowercased().replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        if let def = intents[normalized] {
            return try def.handler(request)
        }

        // 3. No match
        throw IntentError.unknownIntent(request.intent, available: Array(intents.keys).sorted())
    }

    // MARK: - Discovery

    func catalog() -> JSON {
        .array(intentOrder.compactMap { name in
            guard let def = intents[name] else { return nil }
            return .object([
                "intent": .string(def.name),
                "description": .string(def.description),
                "examples": .array(def.examples.map { .string($0) }),
                "slots": .array(def.slots.map { slot in
                    var obj: [String: JSON] = [
                        "name": .string(slot.name),
                        "type": .string(slot.type),
                        "required": .bool(slot.required),
                        "description": .string(slot.description),
                    ]
                    if let vals = slot.enumValues {
                        obj["values"] = .array(vals.map { .string($0) })
                    }
                    return .object(obj)
                })
            ])
        })
    }

    // MARK: - Built-in Intents

    /// Track recently tiled wids so batch operations (e.g. "tile iTerm left, iTerm right")
    /// don't pick the same window twice. Resets after 2 seconds.
    private static var recentlyTiledWids: Set<UInt32> = []
    private static var recentlyTiledTimer: Timer?

    private static func markTiled(_ wid: UInt32) {
        recentlyTiledWids.insert(wid)
        recentlyTiledTimer?.invalidate()
        recentlyTiledTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            recentlyTiledWids.removeAll()
        }
    }

    private func registerBuiltins() {

        // ── Window Tiling ───────────────────────────────────────

        register(IntentDef(
            name: "tile_window",
            description: "Tile a window to a screen position",
            examples: [
                "tile this left",
                "snap to the right half",
                "maximize the window",
                "put it in the top left corner",
                "center the window",
                "make it full screen"
            ],
            slots: [
                IntentSlot(name: "position", type: "position", required: true,
                           description: "Target tile position. Named positions or grid:CxR:C,R syntax.",
                           enumValues: TilePosition.allCases.map(\.rawValue)),
                IntentSlot(name: "app", type: "string", required: false,
                           description: "Target app name (defaults to frontmost)", enumValues: nil),
                IntentSlot(name: "wid", type: "int", required: false,
                           description: "Target window ID", enumValues: nil),
                IntentSlot(name: "session", type: "string", required: false,
                           description: "Target session name", enumValues: nil),
            ],
            handler: { req in
                guard let posStr = req.slots["position"]?.stringValue else {
                    throw IntentError.missingSlot("position")
                }
                // Try named position first, then grid string
                let position: TilePosition? = TilePosition(rawValue: posStr)
                let gridFractions: (CGFloat, CGFloat, CGFloat, CGFloat)? = position == nil ? parseGridString(posStr) : nil
                guard position != nil || gridFractions != nil else {
                    throw IntentError.invalidSlot("Unknown position: \(posStr)")
                }

                // Resolve target: explicit session, wid, app name, or frontmost
                if let session = req.slots["session"]?.stringValue {
                    return try LatticesApi.shared.dispatch(
                        method: "window.tile",
                        params: .object(["session": .string(session), "position": .string(posStr)])
                    )
                }

                // For wid/app/frontmost: use WindowTiler directly
                func tileEntry(_ entry: WindowEntry) {
                    IntentEngine.markTiled(entry.wid)
                    DispatchQueue.main.async {
                        if let pos = position {
                            WindowTiler.tileWindowById(wid: entry.wid, pid: entry.pid, to: pos)
                        } else if let fracs = gridFractions {
                            WindowTiler.tileWindowById(wid: entry.wid, pid: entry.pid, fractions: fracs)
                        }
                    }
                }

                if let wid = req.slots["wid"]?.uint32Value,
                   let entry = DesktopModel.shared.windows[wid] {
                    tileEntry(entry)
                    return .object(["ok": .bool(true), "wid": .int(Int(wid)), "position": .string(posStr)])
                }

                if let app = req.slots["app"]?.stringValue {
                    // Skip windows already tiled in this batch (e.g. two iTerm windows side by side)
                    let alreadyTiled = IntentEngine.recentlyTiledWids
                    if let entry = DesktopModel.shared.windows.values.first(where: {
                        $0.app.localizedCaseInsensitiveContains(app) && !alreadyTiled.contains($0.wid)
                    }) {
                        tileEntry(entry)
                        return .object(["ok": .bool(true), "app": .string(entry.app), "wid": .int(Int(entry.wid)), "position": .string(posStr)])
                    }
                    throw IntentError.targetNotFound("No window found for app '\(app)'")
                }

                // Default: tile frontmost window
                if let pos = position {
                    DispatchQueue.main.async {
                        WindowTiler.tileFrontmost(to: pos)
                    }
                }
                return .object(["ok": .bool(true), "target": .string("frontmost"), "position": .string(posStr)])
            }
        ))

        // ── Focus Window / App ──────────────────────────────────

        register(IntentDef(
            name: "focus",
            description: "Focus a window, app, or session",
            examples: [
                "switch to Chrome",
                "focus the terminal",
                "go to my frontend project",
                "show Slack"
            ],
            slots: [
                IntentSlot(name: "app", type: "string", required: false,
                           description: "App name to focus", enumValues: nil),
                IntentSlot(name: "session", type: "string", required: false,
                           description: "Session name to focus", enumValues: nil),
                IntentSlot(name: "wid", type: "int", required: false,
                           description: "Window ID to focus", enumValues: nil),
            ],
            handler: { req in
                if let session = req.slots["session"]?.stringValue {
                    return try LatticesApi.shared.dispatch(
                        method: "window.focus",
                        params: .object(["session": .string(session)])
                    )
                }
                if let wid = req.slots["wid"]?.intValue {
                    return try LatticesApi.shared.dispatch(
                        method: "window.focus",
                        params: .object(["wid": .int(wid)])
                    )
                }
                if let app = req.slots["app"]?.stringValue {
                    if let entry = DesktopModel.shared.windows.values.first(where: {
                        $0.app.localizedCaseInsensitiveContains(app)
                    }) {
                        return try LatticesApi.shared.dispatch(
                            method: "window.focus",
                            params: .object(["wid": .int(Int(entry.wid))])
                        )
                    }
                    // Try launching the app
                    NSWorkspace.shared.launchApplication(app)
                    return .object(["ok": .bool(true), "launched": .string(app)])
                }
                throw IntentError.missingSlot("app, session, or wid")
            }
        ))

        // ── Launch Session ──────────────────────────────────────

        register(IntentDef(
            name: "launch",
            description: "Launch a project session",
            examples: [
                "open my frontend project",
                "launch the API",
                "start working on lattices",
                "open the backend"
            ],
            slots: [
                IntentSlot(name: "project", type: "string", required: true,
                           description: "Project name or path", enumValues: nil),
            ],
            handler: { req in
                guard let project = req.slots["project"]?.stringValue else {
                    throw IntentError.missingSlot("project")
                }

                // Try matching by name against discovered projects
                let projects = try LatticesApi.shared.dispatch(method: "projects.list", params: nil)
                if case .array(let list) = projects {
                    for p in list {
                        let name = p["name"]?.stringValue ?? ""
                        let path = p["path"]?.stringValue ?? ""
                        if name.localizedCaseInsensitiveContains(project) ||
                           path.localizedCaseInsensitiveContains(project) {
                            return try LatticesApi.shared.dispatch(
                                method: "session.launch",
                                params: .object(["path": .string(path)])
                            )
                        }
                    }
                }
                throw IntentError.targetNotFound("No project matching '\(project)'")
            }
        ))

        // ── Switch Layer ────────────────────────────────────────

        register(IntentDef(
            name: "switch_layer",
            description: "Switch to a workspace layer",
            examples: [
                "switch to the web layer",
                "go to mobile",
                "layer 2",
                "switch to review"
            ],
            slots: [
                IntentSlot(name: "layer", type: "string", required: true,
                           description: "Layer name or index", enumValues: nil),
            ],
            handler: { req in
                guard let layer = req.slots["layer"]?.stringValue else {
                    throw IntentError.missingSlot("layer")
                }

                // Try as index first
                if let index = Int(layer) {
                    // Try session layers first, then config layers
                    let session = SessionLayerStore.shared
                    if !session.layers.isEmpty && index < session.layers.count {
                        DispatchQueue.main.async { session.switchTo(index: index) }
                        return .object(["ok": .bool(true), "type": .string("session"), "index": .int(index)])
                    }
                    return try LatticesApi.shared.dispatch(
                        method: "layer.switch",
                        params: .object(["index": .int(index)])
                    )
                }

                // Try as name — session layers first
                let session = SessionLayerStore.shared
                if let idx = session.layers.firstIndex(where: {
                    $0.name.localizedCaseInsensitiveContains(layer)
                }) {
                    DispatchQueue.main.async { session.switchTo(index: idx) }
                    return .object(["ok": .bool(true), "type": .string("session"), "name": .string(session.layers[idx].name)])
                }

                // Then config layers
                return try LatticesApi.shared.dispatch(
                    method: "layer.switch",
                    params: .object(["name": .string(layer)])
                )
            }
        ))

        // ── Search Windows ─────────────────────────────────────

        register(IntentDef(
            name: "search",
            description: "Search for windows by app name, title, session, or screen text",
            examples: [
                "find the error message",
                "search for TODO",
                "find all terminal windows",
                "find chrome",
                "where does it say build failed",
                "look for port 3000"
            ],
            slots: [
                IntentSlot(name: "query", type: "query", required: true,
                           description: "Text to search for", enumValues: nil),
            ],
            handler: { req in
                return try SearchIntent().perform(slots: req.slots)
            }
        ))

        // ── List Windows ────────────────────────────────────────

        register(IntentDef(
            name: "list_windows",
            description: "List all visible windows",
            examples: [
                "what windows are open",
                "show me all windows",
                "what's on screen"
            ],
            slots: [],
            handler: { _ in
                try LatticesApi.shared.dispatch(method: "windows.list", params: nil)
            }
        ))

        // ── List Sessions ───────────────────────────────────────

        register(IntentDef(
            name: "list_sessions",
            description: "List active terminal sessions",
            examples: [
                "what sessions are running",
                "show my projects",
                "list sessions"
            ],
            slots: [],
            handler: { _ in
                try LatticesApi.shared.dispatch(method: "tmux.sessions", params: nil)
            }
        ))

        // ── Distribute Windows ──────────────────────────────────

        register(IntentDef(
            name: "distribute",
            description: "Distribute all windows evenly across the screen",
            examples: [
                "spread out the windows",
                "distribute everything",
                "organize the windows",
                "clean up the layout"
            ],
            slots: [],
            handler: { _ in
                try LatticesApi.shared.dispatch(method: "layout.distribute", params: nil)
            }
        ))

        // ── Create Layer ────────────────────────────────────────

        register(IntentDef(
            name: "create_layer",
            description: "Create a new session layer from current windows",
            examples: [
                "save this layout as review",
                "create a layer called deploy",
                "make a new layer"
            ],
            slots: [
                IntentSlot(name: "name", type: "string", required: true,
                           description: "Name for the new layer", enumValues: nil),
                IntentSlot(name: "capture_visible", type: "bool", required: false,
                           description: "Auto-capture visible windows into the layer", enumValues: nil),
            ],
            handler: { req in
                guard let name = req.slots["name"]?.stringValue else {
                    throw IntentError.missingSlot("name")
                }

                var windowIds: [JSON] = []
                if req.slots["capture_visible"]?.boolValue == true {
                    for entry in DesktopModel.shared.windows.values where entry.isOnScreen {
                        windowIds.append(.int(Int(entry.wid)))
                    }
                }

                return try LatticesApi.shared.dispatch(
                    method: "session.layers.create",
                    params: .object([
                        "name": .string(name),
                        "windowIds": .array(windowIds)
                    ])
                )
            }
        ))

        // ── Kill Session ────────────────────────────────────────

        register(IntentDef(
            name: "kill",
            description: "Kill a terminal session",
            examples: [
                "stop the frontend session",
                "kill the API",
                "shut down that project"
            ],
            slots: [
                IntentSlot(name: "session", type: "string", required: true,
                           description: "Session name or project name", enumValues: nil),
            ],
            handler: { req in
                guard let session = req.slots["session"]?.stringValue else {
                    throw IntentError.missingSlot("session")
                }

                // Try direct name first
                let sessions = try LatticesApi.shared.dispatch(method: "tmux.sessions", params: nil)
                if case .array(let list) = sessions {
                    for s in list {
                        let name = s["name"]?.stringValue ?? ""
                        if name.localizedCaseInsensitiveContains(session) {
                            return try LatticesApi.shared.dispatch(
                                method: "session.kill",
                                params: .object(["name": .string(name)])
                            )
                        }
                    }
                }
                throw IntentError.targetNotFound("No session matching '\(session)'")
            }
        ))

        // ── Scan (trigger OCR) ──────────────────────────────────

        register(IntentDef(
            name: "scan",
            description: "Trigger an immediate screen text scan",
            examples: [
                "scan the screen",
                "read what's on screen",
                "update OCR"
            ],
            slots: [],
            handler: { _ in
                try LatticesApi.shared.dispatch(method: "ocr.scan", params: nil)
            }
        ))
    }
}

// MARK: - Errors

enum IntentError: LocalizedError {
    case unknownIntent(String, available: [String])
    case missingSlot(String)
    case invalidSlot(String)
    case targetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unknownIntent(let name, let available):
            return "Unknown intent '\(name)'. Available: \(available.joined(separator: ", "))"
        case .missingSlot(let name):
            return "Missing required slot: \(name)"
        case .invalidSlot(let detail):
            return detail
        case .targetNotFound(let detail):
            return detail
        }
    }
}

// MARK: - Claude CLI Fallback

struct ClaudeResolvedIntent {
    let intent: String
    let slots: [String: JSON]
}

struct ClaudeAgentPlan {
    let steps: [ClaudeResolvedIntent]
    let reasoning: String
}

enum ClaudeFallback {

    private static var claudePath: String? { Preferences.resolveClaudePath() }

    /// Shell out to Claude CLI to resolve a voice command transcript into an intent + slots.
    /// Runs synchronously — call from a background thread.
    static func resolve(
        transcript: String,
        windows: [WindowEntry],
        intentCatalog: JSON
    ) -> ClaudeResolvedIntent? {

        let timer = DiagnosticLog.shared.startTimed("Claude fallback")

        // Build window context (compact)
        // Compact window list — just app and title, max 20
        let windowList = windows.prefix(20).map { "\($0.app): \($0.title)" }.joined(separator: "\n")

        // Compact intent list — just name and slot names
        var intentList = ""
        if case .array(let intents) = intentCatalog {
            for intent in intents {
                let name = intent["intent"]?.stringValue ?? ""
                var slotNames: [String] = []
                if case .array(let slots) = intent["slots"] {
                    slotNames = slots.compactMap { $0["name"]?.stringValue }
                }
                let s = slotNames.isEmpty ? "" : "(\(slotNames.joined(separator: ",")))"
                intentList += "\(name)\(s), "
            }
        }

        let prompt = """
        Voice command resolver. Whisper transcript (may have typos): "\(transcript)"
        Intents: \(intentList.trimmingCharacters(in: .init(charactersIn: ", ")))
        Windows: \(windowList)
        Return ONLY a JSON object like {"intent":"search","slots":{"query":"dewey"},"reasoning":"user wants to find dewey windows"}. For search, extract the key term. Use window names from the list. If unclear, use intent "unknown".
        """

        guard let path = claudePath else {
            DiagnosticLog.shared.warn("ClaudeFallback: claude CLI not found")
            DiagnosticLog.shared.finish(timer)
            return nil
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)

        proc.arguments = [
            "-p", prompt,
            "--model", "haiku",
            "--output-format", "text",
            "--no-session-persistence",
            "--max-budget-usd", "0.50",
        ]

        // Clear CLAUDECODE env var to allow nested invocation
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        let pipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            DiagnosticLog.shared.warn("ClaudeFallback: failed to launch claude CLI — \(error)")
            return nil
        }

        proc.waitUntilExit()
        let exitCode = proc.terminationStatus
        DiagnosticLog.shared.finish(timer)
        DiagnosticLog.shared.info("ClaudeFallback: exit code \(exitCode)")

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !errOutput.isEmpty {
            DiagnosticLog.shared.warn("ClaudeFallback: stderr → \(errOutput.prefix(200))")
        }
        DiagnosticLog.shared.info("ClaudeFallback: raw output → \(output.prefix(300))")

        // Parse JSON from text output
        guard let jsonStr = extractJSON(from: output),
              let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let intent = json["intent"] as? String,
              intent != "unknown" else {
            DiagnosticLog.shared.info("ClaudeFallback: couldn't parse response")
            return nil
        }

        if let reasoning = json["reasoning"] as? String {
            DiagnosticLog.shared.info("ClaudeFallback: reasoning → \(reasoning)")
        }

        // Convert slots
        var slots: [String: JSON] = [:]
        if let rawSlots = json["slots"] as? [String: Any] {
            for (key, value) in rawSlots {
                if let s = value as? String {
                    slots[key] = .string(s)
                } else if let n = value as? Int {
                    slots[key] = .int(n)
                } else if let b = value as? Bool {
                    slots[key] = .bool(b)
                }
            }
        }

        return ClaudeResolvedIntent(intent: intent, slots: slots)
    }

    private static func extractJSON(from text: String) -> String? {
        // Try to find JSON object in the response
        // Claude might return it directly, or wrapped in ```json ... ```
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find first { and last }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }

        return String(cleaned[start...end])
    }
}
