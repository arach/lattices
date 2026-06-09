import AppKit
#if canImport(HudsonVoice)
import HudsonVoice
#endif

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

    @Published var state: State = .idle {
        didSet {
            if state != oldValue {
                stateChangedAt = Date()
            }
        }
    }
    @Published private(set) var stateChangedAt: Date = Date()
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
    private(set) var frameHistoryUpdatedAt: Date?

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
        frameHistoryUpdatedAt = frameHistory.isEmpty ? nil : Date()
    }

    func clearFrameHistory() {
        frameHistory.removeAll()
        frameHistoryUpdatedAt = nil
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
    private var workerRoot: String? {
        if let idx = CommandLine.arguments.firstIndex(of: "--lattices-cli-root"),
           CommandLine.arguments.indices.contains(idx + 1) {
            return CommandLine.arguments[idx + 1]
        }

        let devRoot = NSHomeDirectory() + "/dev/lattices"
        return FileManager.default.fileExists(atPath: devRoot) ? devRoot : nil
    }

    /// JSONL log for full turn data — ~/.lattices/handsoff.jsonl
    private let turnLogPath = NSHomeDirectory() + "/.lattices/handsoff.jsonl"

    /// Dev-only rich trace log written on every `runRpc` call.
    /// Captures snapshot source, request cmd, raw worker response, and timings
    /// so the studio's MethodInspector can unpack the whole loop.
    private let rpcDebugLogPath = NSHomeDirectory() + "/.lattices/handsoff-debug.jsonl"

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
        // Worker startup is lazy — only start it when a voice turn or cached cue needs it.
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

    @discardableResult
    private func startWorker() -> Bool {
        if workerProcess?.isRunning == true, workerStdin != nil {
            return true
        }

        let bunPaths = [
            NSHomeDirectory() + "/.bun/bin/bun",
            "/usr/local/bin/bun",
            "/opt/homebrew/bin/bun",
        ]
        guard let bunPath = bunPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            DiagnosticLog.shared.warn("HandsOff: bun not found, worker disabled")
            return false
        }

        guard let workerRoot else {
            DiagnosticLog.shared.warn("HandsOff: worker root not found, worker disabled")
            return false
        }

        let scriptPath = workerRoot + "/bin/handsoff-worker.ts"
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            DiagnosticLog.shared.warn("HandsOff: worker script not found at \(scriptPath)")
            return false
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bunPath)
        proc.arguments = ["run", scriptPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: workerRoot)

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
            return false
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
            guard let self else { return }
            let keepWarm = self.audibleFeedbackEnabled || self.state != .idle
            let suffix = keepWarm ? ", restarting in 2s" : ", staying idle"
            DiagnosticLog.shared.warn("HandsOff: worker exited (code \(proc.terminationStatus))\(suffix)")
            self.workerProcess = nil
            self.workerStdin = nil
            guard keepWarm else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.startWorker()
            }
        }

        // Ping to verify
        sendToWorker(["cmd": "ping"])
        DiagnosticLog.shared.info("HandsOff: worker started (pid \(proc.processIdentifier))")
        return true
    }

    // MARK: - Worker communication

    private var pendingCallback: (([String: Any]) -> Void)?
    /// When true, the worker response should be returned to the callback
    /// WITHOUT touching live state — no chatLog append, no executeActions,
    /// no @Published mutations, no state-machine reset. Set by RPC paths
    /// (e.g. `runRpc`); the audio-driven voice path leaves this false.
    private var pendingCallbackDryRun = false
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

    private func sendToWorkerWithCallback(
        _ dict: [String: Any],
        dryRun: Bool = false,
        callback: @escaping ([String: Any]) -> Void
    ) {
        pendingCallback = callback
        pendingCallbackDryRun = dryRun
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
            let isDryRun = pendingCallbackDryRun
            pendingCallback = nil
            pendingCallbackDryRun = false

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

            // Single dispatch — all @Published mutations in one block.
            // For dry-run RPC turns (studio etc.), skip every side effect
            // and just fire the callback. The voice path runs the full body.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !isDryRun {
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
        #if canImport(HudsonVoice)
        guard let session = voxSession else { return }
        DiagnosticLog.shared.info("HandsOff: cancelling Vox session")
        voxSession = nil
        voxPump?.cancel()
        voxPump = nil
        Task { try? await session.cancel() }
        #endif
    }

    // MARK: - Voice capture

    #if canImport(HudsonVoice)
    /// Live HudsonVoice session for the current dictation turn, plus its event pump.
    private var voxSession: HudVoxLiveSession?
    private var voxPump: Task<Void, Never>?
    #endif

    private func beginListening() {
        #if canImport(HudsonVoice)
        // HudsonVoice dials voxd on capture start — there's no socket to pre-connect,
        // so we just confirm the daemon is discoverable (retrying briefly if it's
        // still spinning up) and then open the live session.
        if VoxDaemon.isRunning {
            startDictation()
        } else {
            state = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.retryListenIfReady(attempts: 5)
            }
        }
        #else
        DiagnosticLog.shared.warn("HandsOff: built without HudsonVoice — voice unavailable")
        state = .idle
        playSound("Basso")
        #endif
    }

    private func retryListenIfReady(attempts: Int) {
        #if canImport(HudsonVoice)
        if VoxDaemon.isRunning {
            startDictation()
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.retryListenIfReady(attempts: attempts - 1)
            }
        } else {
            state = .idle
            DiagnosticLog.shared.warn("HandsOff: Vox not available")
            playSound("Basso")
        }
        #endif
    }

    /// Guard against double-processing the transcript (a final followed by a late stream end).
    private var turnProcessed = false

    private func startDictation() {
        #if canImport(HudsonVoice)
        state = .listening
        lastTranscript = nil
        turnProcessed = false
        playSound("Tink")

        DiagnosticLog.shared.info("HandsOff: listening...")

        // HudVoxLiveSession opens the mic in voxd; events stream back on start().
        // `.partial` updates the live transcript, `.final` delivers the turn.
        let endpoint = VoxEndpointResolver.resolve()
        let session = HudVoxLiveSession(
            endpoint: endpoint,
            options: HudVoxLiveSessionOptions(clientId: "lattices", mode: .pushToTalk)
        )
        voxSession = session
        voxPump = Task { [weak self] in
            do {
                let stream = try await session.start()
                for try await event in stream {
                    await MainActor.run { [weak self] in self?.handleVoxEvent(event) }
                }
                await MainActor.run { [weak self] in self?.voxStreamEnded(error: nil) }
            } catch {
                await MainActor.run { [weak self] in self?.voxStreamEnded(error: error) }
            }
        }
        #endif
    }

    // MARK: - RPC entry (silent, dry-run)

    enum RpcError: Error, LocalizedError {
        case busy
        case workerUnavailable
        var errorDescription: String? {
            switch self {
            case .busy:
                return "Hands-off session is busy — try again once the current turn finishes."
            case .workerUnavailable:
                return "Hands-off worker is unavailable (bun missing or script not found)."
            }
        }
    }

    /// Run a transcript through the same worker pipeline voice uses, but
    /// silently — no state-machine change, no TTS, no chat-log append, no
    /// row in `handsoff.jsonl`, no action execution. Optional snapshot
    /// override feeds the LLM a synthetic desktop (for studio mocks).
    ///
    /// In dev builds, every call writes a rich trace to
    /// `~/.lattices/handsoff-debug.jsonl` that the studio can unpack.
    func runRpc(
        transcript: String,
        snapshotOverride: [String: Any]? = nil,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(.failure(RpcError.workerUnavailable))
                return
            }

            // Refuse to step on a live voice turn.
            if self.state != .idle || self.pendingCallback != nil {
                completion(.failure(RpcError.busy))
                return
            }

            guard self.startWorker() else {
                completion(.failure(RpcError.workerUnavailable))
                return
            }

            let snapshot = snapshotOverride ?? self.buildSnapshot()
            let snapshotSource = snapshotOverride == nil ? "live" : "override"

            let turnCmd: [String: Any] = [
                "cmd": "turn",
                "transcript": transcript,
                "snapshot": snapshot,
                "history": [],
            ]

            let startedAt = Date()
            DiagnosticLog.shared.info(
                "HandsOff.RPC: ⏱ '\(transcript)' (snapshot: \(snapshotSource))"
            )

            self.sendToWorkerWithCallback(turnCmd, dryRun: true) { [weak self] response in
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                if LatticesRuntime.isDevBuild {
                    self?.writeRpcDebugArtifact(
                        transcript: transcript,
                        snapshotSource: snapshotSource,
                        snapshot: snapshot,
                        request: turnCmd,
                        response: response,
                        durationMs: durationMs
                    )
                }
                completion(.success(response))
            }
        }
    }

    private func writeRpcDebugArtifact(
        transcript: String,
        snapshotSource: String,
        snapshot: [String: Any],
        request: [String: Any],
        response: [String: Any],
        durationMs: Int
    ) {
        let record: [String: Any] = [
            "kind": "handsoff.run",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "transcript": transcript,
            "snapshotSource": snapshotSource,
            "snapshot": snapshot,
            "request": request,
            "response": response,
            "durationMs": durationMs,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = FileHandle(forWritingAtPath: rpcDebugLogPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(
                atPath: rpcDebugLogPath,
                contents: line.data(using: .utf8)
            )
        }
    }

    #if canImport(HudsonVoice)
    @MainActor
    private func handleVoxEvent(_ event: HudVoiceEvent) {
        switch event {
        case .state(let s):
            DiagnosticLog.shared.info("HandsOff: session → \(s.state)")
            // voxd cancelled the session (e.g. recording timeout)
            if case .cancelled = s.state, state == .listening {
                state = .idle
                playSound("Basso")
            }
        case .partial(let p):
            lastTranscript = p.text
        case .final(let f):
            if !f.text.isEmpty {
                lastTranscript = f.text
                deliverTranscript(f.text)
            }
        case .raw:
            break
        }
    }

    @MainActor
    private func voxStreamEnded(error: Error?) {
        if !turnProcessed, state == .listening {
            state = .idle
            if let error {
                DiagnosticLog.shared.warn("HandsOff: session error — \(error.localizedDescription)")
                playSound("Basso")
            } else {
                DiagnosticLog.shared.info("HandsOff: no speech detected")
            }
        }
        voxSession = nil
        voxPump = nil
    }
    #endif

    /// Deliver transcript exactly once — called from the final event.
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
        #if canImport(HudsonVoice)
        let session = voxSession
        Task { try? await session?.stop() }
        #endif
    }

    // MARK: - Turn processing (delegates to worker)

    private func processTurn(_ transcript: String) {
        state = .thinking
        guard startWorker() else {
            state = .idle
            DiagnosticLog.shared.warn("HandsOff: worker unavailable")
            playSound("Basso")
            return
        }
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
        AssistantSnapshotBuilder.build()
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
