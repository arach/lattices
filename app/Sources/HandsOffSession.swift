import AppKit

/// Hands-off voice mode: hotkey → listen → worker handles everything.
///
/// Architecture:
///   - Swift owns: hotkey, Vox dictation, action execution
///   - Worker owns: inference (Groq), TTS (streaming OpenAI), fast path matching, audio caching
///   - Worker is a long-running bun process, started once, communicates via JSON lines over stdio
///
/// The worker handles the full turn orchestration in parallel:
///   - Fast path: local match → cached ack + execute + cached confirm (~300ms)
///   - Slow path: cached ack ∥ Groq inference → streaming TTS ∥ execute (~2s)

// MARK: - Chat Log Entry

struct VoiceChatEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let role: Role
    let text: String
    /// Optional structured data — actions taken, search results, etc.
    /// Displayable in the chat log but not spoken.
    let detail: String?

    enum Role: String, Equatable {
        case user       // what the user said
        case assistant  // spoken response
        case system     // silent info (actions executed, search results, etc.)
    }

    static func == (lhs: VoiceChatEntry, rhs: VoiceChatEntry) -> Bool {
        lhs.id == rhs.id
    }
}

final class HandsOffSession: ObservableObject {
    static let shared = HandsOffSession()

    enum State: Equatable {
        case idle
        case connecting
        case listening
        case thinking
    }

    @Published var state: State = .idle
    @Published var lastTranscript: String?
    @Published var lastResponse: String?
    @Published var audibleFeedbackEnabled: Bool = false

    /// Recently executed actions — shown as playback in the HUD bottom bar
    @Published var recentActions: [[String: Any]] = []

    /// Frame history for undo — stores pre-move frames of windows touched by the last turn
    struct FrameSnapshot {
        let wid: UInt32
        let pid: Int32
        let frame: WindowFrame
    }
    private(set) var frameHistory: [FrameSnapshot] = []

    /// Snapshot current frames for all windows that are about to be moved.
    /// Stores frames in CG/AX coordinates (top-left origin) for direct use with batchRestoreWindows.
    func snapshotFrames(wids: [UInt32]) {
        frameHistory.removeAll()
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        for wid in wids {
            guard let entry = DesktopModel.shared.windows[wid] else { continue }
            for info in windowList {
                guard let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
                      let dict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
                var rect = CGRect.zero
                if CGRectMakeWithDictionaryRepresentation(dict, &rect) {
                    let frame = WindowFrame(x: rect.origin.x, y: rect.origin.y, w: rect.width, h: rect.height)
                    frameHistory.append(FrameSnapshot(wid: wid, pid: entry.pid, frame: frame))
                }
                break
            }
        }
    }

    func clearFrameHistory() {
        frameHistory.removeAll()
    }

    /// Running chat log — visible in the voice chat panel. Persists across turns.
    @Published private(set) var chatLog: [VoiceChatEntry] = []
    private let maxChatEntries = 50

    private var turnCount = 0
    @Published private(set) var conversationHistory: [[String: String]] = []
    private let maxHistoryTurns = 10

    // Long-running worker process
    private var workerProcess: Process?
    private var workerStdin: FileHandle?
    private var workerBuffer = ""
    private let workerQueue = DispatchQueue(label: "com.lattices.handsoff-worker", qos: .userInitiated)
    private var lastCueAt: Date = .distantPast

    /// JSONL log for full turn data — ~/.lattices/handsoff.jsonl
    private let turnLogPath = NSHomeDirectory() + "/.lattices/handsoff.jsonl"

    private init() {}

    // MARK: - Chat Log

    func appendChat(_ role: VoiceChatEntry.Role, text: String, detail: String? = nil) {
        let entry = VoiceChatEntry(timestamp: Date(), role: role, text: text, detail: detail)
        DispatchQueue.main.async {
            self.chatLog.append(entry)
            if self.chatLog.count > self.maxChatEntries {
                self.chatLog.removeFirst(self.chatLog.count - self.maxChatEntries)
            }
        }
    }

    func clearChatLog() {
        DispatchQueue.main.async { self.chatLog.removeAll() }
    }

    // MARK: - Lifecycle

    func start() {
        startWorker()
    }

    func setAudibleFeedbackEnabled(_ enabled: Bool) {
        audibleFeedbackEnabled = enabled
        if enabled {
            startWorker()
        }
    }

    func playCachedCue(_ phrase: String) {
        guard audibleFeedbackEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCueAt) >= 0.2 else { return }
        lastCueAt = now
        startWorker()
        sendToWorker(["cmd": "play_cached", "text": phrase])
    }

    /// Append a full turn record to the JSONL log
    private func logTurn(transcript: String, response: [String: Any], turnMs: Int) {
        let snapshot = buildSnapshot()
        var record: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "turn": turnCount,
            "transcript": transcript,
            "turnMs": turnMs,
            "snapshot": snapshot,
        ]
        if let data = response["data"] as? [String: Any] {
            record["actions"] = data["actions"]
            record["spoken"] = data["spoken"]
            record["meta"] = data["_meta"]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: record),
              var line = String(data: jsonData, encoding: .utf8) else { return }
        line += "\n"

        if let handle = FileHandle(forWritingAtPath: turnLogPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: turnLogPath, contents: line.data(using: .utf8))
        }
    }

    private func startWorker() {
        if workerProcess?.isRunning == true, workerStdin != nil {
            return
        }

        let bunPaths = [
            NSHomeDirectory() + "/.bun/bin/bun",
            "/usr/local/bin/bun",
            "/opt/homebrew/bin/bun",
        ]
        guard let bunPath = bunPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            DiagnosticLog.shared.warn("HandsOff: bun not found, worker disabled")
            return
        }

        let scriptPath = NSHomeDirectory() + "/dev/lattices/bin/handsoff-worker.ts"
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            DiagnosticLog.shared.warn("HandsOff: worker script not found at \(scriptPath)")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bunPath)
        proc.arguments = ["run", scriptPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/dev/lattices")

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            DiagnosticLog.shared.warn("HandsOff: failed to start worker — \(error)")
            return
        }

        workerProcess = proc
        workerStdin = inPipe.fileHandleForWriting

        // Read stdout for responses
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            self?.handleWorkerOutput(str)
        }

        // Log stderr
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            for line in str.components(separatedBy: "\n") where !line.isEmpty {
                DiagnosticLog.shared.info("HandsOff worker: \(line)")
            }
        }

        // Handle worker crash → restart
        proc.terminationHandler = { [weak self] proc in
            DiagnosticLog.shared.warn("HandsOff: worker exited (code \(proc.terminationStatus)), restarting in 2s")
            self?.workerProcess = nil
            self?.workerStdin = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.startWorker()
            }
        }

        // Ping to verify
        sendToWorker(["cmd": "ping"])
        DiagnosticLog.shared.info("HandsOff: worker started (pid \(proc.processIdentifier))")
    }

    // MARK: - Worker communication

    private var pendingCallback: (([String: Any]) -> Void)?
    private var turnTimeoutWork: DispatchWorkItem?
    private static let turnTimeoutSeconds: TimeInterval = 30

    private func sendToWorker(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              var str = String(data: data, encoding: .utf8) else { return }
        str += "\n"
        workerQueue.async { [weak self] in
            self?.workerStdin?.write(str.data(using: .utf8)!)
        }
    }

    private func sendToWorkerWithCallback(_ dict: [String: Any], callback: @escaping ([String: Any]) -> Void) {
        pendingCallback = callback
        sendToWorker(dict)
    }

    private func handleWorkerOutput(_ str: String) {
        workerBuffer += str
        let lines = workerBuffer.components(separatedBy: "\n")
        workerBuffer = lines.last ?? ""

        for line in lines.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            DiagnosticLog.shared.info("HandsOff: worker response → \(trimmed)")

            // Parse everything on the background thread, then do ONE main-queue dispatch
            // to update all @Published properties atomically. Scattered dispatches cause
            // Combine deadlocks (os_unfair_lock contention with SwiftUI rendering).
            let dataObj = json["data"] as? [String: Any]
            let spoken = dataObj?["spoken"] as? String
            let actions = dataObj?["actions"] as? [[String: Any]]
            let cb = pendingCallback
            pendingCallback = nil

            // Build chat entries off-main
            var chatEntries: [(VoiceChatEntry.Role, String)] = []
            if let spoken { chatEntries.append((.assistant, spoken)) }
            if let actions, !actions.isEmpty {
                let summaries = actions.compactMap { action -> String? in
                    guard let intent = action["intent"] as? String else { return nil }
                    let slots = action["slots"] as? [String: Any] ?? [:]
                    let target = slots["app"] as? String ?? slots["query"] as? String ?? ""
                    let pos = slots["position"] as? String ?? ""
                    return [intent, target, pos].filter { !$0.isEmpty }.joined(separator: " ")
                }
                if !summaries.isEmpty {
                    chatEntries.append((.system, summaries.joined(separator: ", ")))
                }
            }

            // Single dispatch — all @Published mutations in one block
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let spoken { self.lastResponse = spoken }
                for (role, text) in chatEntries {
                    self.chatLog.append(VoiceChatEntry(timestamp: Date(), role: role, text: text, detail: nil))
                }
                if self.chatLog.count > self.maxChatEntries {
                    self.chatLog.removeFirst(self.chatLog.count - self.maxChatEntries)
                }
                if let actions, !actions.isEmpty {
                    self.recentActions = actions
                    self.executeActions(actions)
                }
                self.state = .idle
            }

            cb?(json)
        }
    }

    // MARK: - Toggle

    func toggle() {
        switch state {
        case .idle:
            beginListening()
        case .listening:
            finishListening()
        case .thinking:
            cancelTurn()
        case .connecting:
            cancel()
        }
    }

    func cancel() {
        cancelVoxSession()
        state = .idle
        DiagnosticLog.shared.info("HandsOff: cancelled")
    }

    private func cancelTurn() {
        turnTimeoutWork?.cancel()
        turnTimeoutWork = nil
        pendingCallback = nil
        state = .idle
        DiagnosticLog.shared.warn("HandsOff: turn cancelled by user")
        playSound("Funk")
    }

    /// Cancel any active Vox recording session without transcribing.
    private func cancelVoxSession() {
        guard VoxClient.shared.activeSessionId != nil else { return }
        DiagnosticLog.shared.info("HandsOff: cancelling Vox session")
        VoxClient.shared.cancelSession()
    }

    // MARK: - Voice capture

    private func beginListening() {
        let client = VoxClient.shared

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
        if VoxClient.shared.connectionState == .connected {
            startDictation()
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.retryListenIfConnected(attempts: attempts - 1)
            }
        } else {
            state = .idle
            DiagnosticLog.shared.warn("HandsOff: Vox not available")
            playSound("Basso")
        }
    }

    /// Guard against double-processing the transcript (session.final + completion can both deliver it).
    private var turnProcessed = false

    private func startDictation() {
        state = .listening
        lastTranscript = nil
        turnProcessed = false
        playSound("Tink")

        DiagnosticLog.shared.info("HandsOff: listening...")

        // Vox live session: startSession opens the mic, events flow on the start call ID.
        // session.final arrives via onProgress, then the same data arrives via completion.
        // We process the transcript from whichever arrives first to be resilient against
        // connection drops between the two.
        VoxClient.shared.startSession(
            onProgress: { [weak self] event, data in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch event {
                    case "session.state":
                        let sessionState = data["state"] as? String ?? ""
                        DiagnosticLog.shared.info("HandsOff: session → \(sessionState)")
                        // Vox cancelled the session (e.g. recording timeout)
                        if sessionState == "cancelled" {
                            let reason = data["reason"] as? String ?? "unknown"
                            DiagnosticLog.shared.warn("HandsOff: Vox cancelled session — \(reason)")
                            if self.state == .listening {
                                self.state = .idle
                                self.playSound("Basso")
                            }
                        }
                    case "session.final":
                        // Primary transcript delivery — process immediately
                        if let text = data["text"] as? String, !text.isEmpty {
                            self.lastTranscript = text
                            self.deliverTranscript(text)
                        }
                    default:
                        break
                    }
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let data):
                        let text = data["text"] as? String ?? ""
                        if text.isEmpty {
                            if !self.turnProcessed {
                                self.state = .idle
                                DiagnosticLog.shared.info("HandsOff: no speech detected")
                            }
                        } else {
                            // Fallback — deliver if session.final didn't already
                            self.lastTranscript = text
                            self.deliverTranscript(text)
                        }
                    case .failure(let error):
                        if !self.turnProcessed {
                            self.state = .idle
                            DiagnosticLog.shared.warn("HandsOff: session error — \(error.localizedDescription)")
                            self.playSound("Basso")
                        }
                    }
                }
            }
        )
    }

    /// Deliver transcript exactly once — called from both session.final and completion.
    private func deliverTranscript(_ text: String) {
        guard !turnProcessed else { return }
        turnProcessed = true
        DiagnosticLog.shared.info("HandsOff: heard → '\(text)'")
        appendChat(.user, text: text)
        processTurn(text)
    }

    func finishListening() {
        guard state == .listening else { return }
        playSound("Tink")
        VoxClient.shared.stopSession()
    }

    // MARK: - Turn processing (delegates to worker)

    private func processTurn(_ transcript: String) {
        state = .thinking
        turnCount += 1

        let turnStart = Date()
        DiagnosticLog.shared.info("HandsOff: ⏱ turn \(turnCount) — '\(transcript)'")

        // Build snapshot
        let snapshot = buildSnapshot()

        // Send turn to worker — it handles ack, inference, TTS, everything in parallel
        let turnCmd: [String: Any] = [
            "cmd": "turn",
            "transcript": transcript,
            "snapshot": snapshot,
            "history": conversationHistory,
        ]

        // Start turn timeout — forcibly reset if worker never responds
        turnTimeoutWork?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .thinking else { return }
            DiagnosticLog.shared.warn("HandsOff: ⏱ turn \(self.turnCount) timed out after \(Int(Self.turnTimeoutSeconds))s")
            self.pendingCallback = nil
            self.state = .idle
            self.playSound("Basso")
        }
        turnTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.turnTimeoutSeconds, execute: timeout)

        sendToWorkerWithCallback(turnCmd) { [weak self] response in
            guard let self else { return }

            // Cancel the timeout — we got a response
            self.turnTimeoutWork?.cancel()
            self.turnTimeoutWork = nil

            let turnMs = Int(Date().timeIntervalSince(turnStart) * 1000)
            DiagnosticLog.shared.info("HandsOff: ⏱ turn \(self.turnCount) complete — \(turnMs)ms")

            // Log full turn to JSONL
            self.logTurn(transcript: transcript, response: response, turnMs: turnMs)

            // Record history
            if let data = response["data"] as? [String: Any] {
                let responseStr = (try? String(data: JSONSerialization.data(withJSONObject: data), encoding: .utf8)) ?? ""
                self.conversationHistory.append(["role": "user", "content": transcript])
                self.conversationHistory.append(["role": "assistant", "content": responseStr])
                if self.conversationHistory.count > self.maxHistoryTurns * 2 {
                    self.conversationHistory = Array(self.conversationHistory.suffix(self.maxHistoryTurns * 2))
                }
            }
        }
    }

    // MARK: - Desktop snapshot (full context — all windows, all screens)

    private func buildSnapshot() -> [String: Any] {
        let allWindows = DesktopModel.shared.allWindows()
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        let grouping = UserDefaults(suiteName: "com.apple.WindowManager")?.integer(forKey: "AppWindowGroupingBehavior") ?? 0

        // All windows — no filtering. Order is front-to-back (Z-order).
        let windowList: [[String: Any]] = allWindows.enumerated().map { (zIndex, w) in
            var entry: [String: Any] = [
                "wid": w.wid,
                "app": w.app,
                "title": w.title,
                "frame": "\(Int(w.frame.x)),\(Int(w.frame.y)) \(Int(w.frame.w))x\(Int(w.frame.h))",
                "onScreen": w.isOnScreen,
                "zIndex": zIndex, // 0 = frontmost
            ]
            if let session = w.latticesSession {
                entry["session"] = session
            }
            if !w.spaceIds.isEmpty {
                entry["spaces"] = w.spaceIds
            }
            return entry
        }

        // All screens
        let screens: [[String: Any]] = NSScreen.screens.enumerated().map { (i, s) in
            [
                "index": i + 1,
                "width": Int(s.frame.width),
                "height": Int(s.frame.height),
                "isMain": s == NSScreen.main,
                "visibleWidth": Int(s.visibleFrame.width),
                "visibleHeight": Int(s.visibleFrame.height),
            ]
        }

        // Layers
        var layerInfo: [String: Any]?
        let layerStore = SessionLayerStore.shared
        if layerStore.activeIndex >= 0 && layerStore.activeIndex < layerStore.layers.count {
            let current = layerStore.layers[layerStore.activeIndex]
            layerInfo = ["name": current.name, "index": layerStore.activeIndex]
        }

        // Terminal enrichment — cwd, running commands, claude, tmux sessions
        let terminals = ProcessModel.shared.synthesizeTerminals()
        let terminalList: [[String: Any]] = terminals.compactMap { inst in
            var entry: [String: Any] = [
                "tty": inst.tty,
                "hasClaude": inst.hasClaude,
                "displayName": inst.displayName,
                "isActiveTab": inst.isActiveTab,
            ]
            if let cwd = inst.cwd { entry["cwd"] = cwd }
            if let app = inst.app { entry["app"] = app.rawValue }
            if let session = inst.tmuxSession { entry["tmuxSession"] = session }
            if let wid = inst.windowId { entry["windowId"] = Int(wid) }
            if let title = inst.tabTitle { entry["tabTitle"] = title }
            // Top running command (most useful for context)
            let userProcesses = inst.processes.filter {
                !["zsh", "bash", "fish", "login", "-zsh", "-bash"].contains($0.comm)
            }
            if !userProcesses.isEmpty {
                entry["runningCommands"] = userProcesses.map { proc in
                    var cmd: [String: Any] = ["command": proc.comm]
                    if let cwd = proc.cwd { cmd["cwd"] = cwd }
                    return cmd
                }
            }
            return entry
        }

        // Tmux sessions
        let tmuxSessions = TmuxModel.shared.sessions
        let tmuxList: [[String: Any]] = tmuxSessions.map { s in
            [
                "name": s.name,
                "windowCount": s.windowCount,
                "attached": s.attached,
            ]
        }

        var snapshot: [String: Any] = [
            "stageManager": smEnabled,
            "smGrouping": grouping == 0 ? "all-at-once" : "one-at-a-time",
            "windows": windowList,
            "terminals": terminalList,
            "screens": screens,
            "windowCount": allWindows.count,
            "onScreenCount": allWindows.filter(\.isOnScreen).count,
        ]
        if !tmuxList.isEmpty { snapshot["tmuxSessions"] = tmuxList }
        if let layerInfo { snapshot["currentLayer"] = layerInfo }

        return snapshot
    }

    // MARK: - Action execution

    /// Hard cap on simultaneous actions. Rearranging 20+ windows is never right.
    /// distribute is exempt because it's a single intent that handles all windows safely.
    private static let maxActions = 6

    private func executeActions(_ actions: [[String: Any]]) {
        // Snapshot frames of all windows about to be moved (for undo)
        let movingWids: [UInt32] = actions.compactMap { action in
            let intent = action["intent"] as? String ?? ""
            guard ["tile_window", "swap", "distribute", "move_to_display"].contains(intent) else { return nil }
            let slots = action["slots"] as? [String: Any] ?? [:]
            return (slots["wid"] as? NSNumber)?.uint32Value
                ?? (slots["wid_a"] as? NSNumber)?.uint32Value
        }
        // Also grab wid_b from swap actions
        let swapBWids: [UInt32] = actions.compactMap { action in
            let slots = action["slots"] as? [String: Any] ?? [:]
            return (slots["wid_b"] as? NSNumber)?.uint32Value
        }
        snapshotFrames(wids: movingWids + swapBWids)

        // Guard: refuse to execute bulk operations that would be disorienting
        let nonDistributeActions = actions.filter { ($0["intent"] as? String) != "distribute" }
        if nonDistributeActions.count > Self.maxActions {
            DiagnosticLog.shared.warn(
                "HandsOff: BLOCKED — \(nonDistributeActions.count) actions exceeds limit of \(Self.maxActions). " +
                "Skipping execution to avoid disorienting window rearrangement."
            )
            return
        }

        // Smart distribution: when multiple tile_window actions target the same
        // position, subdivide that region instead of stacking windows on top of each other.
        let distributed = distributeTileActions(actions)

        for action in distributed {
            guard let intent = action["intent"] as? String else { continue }
            let slots = action["slots"] as? [String: Any] ?? [:]

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
                intentName: intent,
                slots: jsonSlots,
                confidence: 0.95,
                matchedPhrase: "hands-off"
            )

            do {
                _ = try PhraseMatcher.shared.execute(match)
                DiagnosticLog.shared.success("HandsOff: \(intent) executed")
            } catch {
                DiagnosticLog.shared.warn("HandsOff: \(intent) failed — \(error.localizedDescription)")
            }
        }
    }

    /// When multiple tile_window actions target the same position, distribute them
    /// within that region. E.g., 3 windows → "left" becomes top-left, left, bottom-left.
    private func distributeTileActions(_ actions: [[String: Any]]) -> [[String: Any]] {
        // Group tile_window actions by position
        var tileGroups: [String: [[String: Any]]] = [:]
        var otherActions: [[String: Any]] = []

        for action in actions {
            let intent = action["intent"] as? String ?? ""
            if intent == "tile_window",
               let slots = action["slots"] as? [String: Any],
               let position = slots["position"] as? String {
                tileGroups[position, default: []].append(action)
            } else {
                otherActions.append(action)
            }
        }

        var result = otherActions

        for (position, group) in tileGroups {
            if group.count == 1 {
                // Single window — keep as-is
                result.append(group[0])
            } else {
                // Multiple windows targeting the same position — subdivide
                let subPositions = subdividePosition(position, count: group.count)
                for (i, action) in group.enumerated() {
                    var modified = action
                    var slots = (action["slots"] as? [String: Any]) ?? [:]
                    slots["position"] = subPositions[i]
                    modified["slots"] = slots
                    result.append(modified)
                    DiagnosticLog.shared.info("HandsOff: distributed \(position) → \(subPositions[i]) for window \(slots["wid"] ?? "?")")
                }
            }
        }

        return result
    }

    /// Subdivide a tile position for N windows.
    private func subdividePosition(_ position: String, count: Int) -> [String] {
        // 2-3 windows in a half → vertical stack
        let verticalSubs: [String: [String]] = [
            "left":  ["top-left", "bottom-left"],
            "right": ["top-right", "bottom-right"],
        ]
        // 4+ windows in a half → 2×2 grid using the eighths
        let gridSubs: [String: [String]] = [
            "left":  ["top-first-fourth", "top-second-fourth", "bottom-first-fourth", "bottom-second-fourth"],
            "right": ["top-third-fourth", "top-last-fourth", "bottom-third-fourth", "bottom-last-fourth"],
        ]
        // Horizontal stacking within a half
        let horizontalSubs: [String: [String]] = [
            "top":    ["top-left", "top-right"],
            "bottom": ["bottom-left", "bottom-right"],
        ]
        // 4+ windows horizontal → use fourths
        let horizontalGridSubs: [String: [String]] = [
            "top":    ["top-first-fourth", "top-second-fourth", "top-third-fourth", "top-last-fourth"],
            "bottom": ["bottom-first-fourth", "bottom-second-fourth", "bottom-third-fourth", "bottom-last-fourth"],
        ]
        // Full screen → grid
        let fullSubs = ["top-left", "top-right", "bottom-left", "bottom-right", "left", "right"]

        let subs: [String]
        if count >= 4, let g = gridSubs[position] {
            subs = g
        } else if let v = verticalSubs[position] {
            subs = v
        } else if count >= 4, let hg = horizontalGridSubs[position] {
            subs = hg
        } else if let h = horizontalSubs[position] {
            subs = h
        } else if position == "maximize" || position == "center" {
            subs = fullSubs
        } else {
            // Can't subdivide further — just repeat the position
            return Array(repeating: position, count: count)
        }

        // Distribute windows across available sub-positions
        var result: [String] = []
        for i in 0..<count {
            result.append(subs[i % subs.count])
        }
        return result
    }

    // MARK: - Sound

    private func playSound(_ name: NSSound.Name) {
        NSSound(named: name)?.play()
    }
}
