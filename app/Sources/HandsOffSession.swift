import AppKit

/// Hands-off voice mode: hotkey → listen → worker handles everything.
///
/// Architecture:
///   - Swift owns: hotkey, Talkie dictation, action execution
///   - Worker owns: inference (Groq), TTS (streaming OpenAI), fast path matching, audio caching
///   - Worker is a long-running bun process, started once, communicates via JSON lines over stdio
///
/// The worker handles the full turn orchestration in parallel:
///   - Fast path: local match → cached ack + execute + cached confirm (~300ms)
///   - Slow path: cached ack ∥ Groq inference → streaming TTS ∥ execute (~2s)

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

    private var turnCount = 0
    private var conversationHistory: [[String: String]] = []
    private let maxHistoryTurns = 10

    // Long-running worker process
    private var workerProcess: Process?
    private var workerStdin: FileHandle?
    private var workerBuffer = ""
    private let workerQueue = DispatchQueue(label: "com.lattices.handsoff-worker", qos: .userInitiated)

    /// JSONL log for full turn data — ~/.lattices/handsoff.jsonl
    private let turnLogPath = NSHomeDirectory() + "/.lattices/handsoff.jsonl"

    private init() {}

    // MARK: - Lifecycle

    func start() {
        startWorker()
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

            // Execute actions immediately when they arrive
            if let dataObj = json["data"] as? [String: Any],
               let actions = dataObj["actions"] as? [[String: Any]], !actions.isEmpty {
                DispatchQueue.main.async {
                    self.executeActions(actions)
                }
            }

            if let cb = pendingCallback {
                pendingCallback = nil
                cb(json)
            }

            DispatchQueue.main.async {
                self.state = .idle
            }
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
            DiagnosticLog.shared.info("HandsOff: busy, ignoring toggle")
        case .connecting:
            cancel()
        }
    }

    func cancel() {
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
                            self.processTurn(text)
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
        playSound("Tink")
        TalkieClient.shared.call(method: "stopDictation") { _ in }
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

        sendToWorkerWithCallback(turnCmd) { [weak self] response in
            guard let self else { return }

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

    private func executeActions(_ actions: [[String: Any]]) {
        for action in actions {
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

    // MARK: - Sound

    private func playSound(_ name: NSSound.Name) {
        NSSound(named: name)?.play()
    }
}
