import Foundation

/// One completed agent-runtime turn.
struct AgentRuntimeReply {
    let text: String
    let harness: String
    /// Model the harness reported on its session (`session.model`), if any.
    let model: String?
    let sessionId: String
}

enum AgentRuntimeTransportError: LocalizedError {
    case bunMissing
    case runnerMissing
    case notAvailable(String)
    case startFailed(String)
    case turnFailed(String)
    case emptyReply
    case timeout
    case requestTimeout

    var errorDescription: String? {
        switch self {
        case .bunMissing:
            return "Bun is required for the local agent runtime."
        case .runnerMissing:
            return "Agent runner script not found. Rebuild Lattices from the repo."
        case .notAvailable(let detail):
            return detail
        case .startFailed(let detail):
            return "Could not start agent runtime: \(detail)"
        case .turnFailed(let detail):
            return detail
        case .emptyReply:
            return "The agent finished without a text reply."
        case .timeout:
            return "The agent turn timed out."
        case .requestTimeout:
            return "The agent runtime did not respond in time."
        }
    }
}

/// The picked model / effort for one harness. Applied only when that harness
/// answers the turn; a fallback harness starts on its own defaults.
struct AgentRuntimeLaunch: Equatable {
    let harness: String
    let model: String?
    let effort: String?

    /// What changes the session: a new pick restarts it.
    var key: String { [harness, model ?? "", effort ?? ""].joined(separator: "|") }

    /// Start-request fields in the shape each agent-sessions adapter reads:
    /// claude-code and pi take `model`, pi takes `options.thinking`, codex
    /// takes its app-server launch args.
    var startFields: [String: Any] {
        switch harness {
        case "codex":
            var args: [String] = []
            if let model { args += ["--model", model] }
            if let effort { args += ["--reasoning-effort", effort] }
            return args.isEmpty ? [:] : ["options": ["launchArgs": args]]
        case "pi":
            var fields: [String: Any] = [:]
            if let model { fields["model"] = model }
            if let effort { fields["options"] = ["thinking": effort] }
            return fields
        default:
            return model.map { ["model": $0] } ?? [:]
        }
    }
}

/// Catalog entry from `{"op":"catalog"}`.
struct AgentRuntimeHarness: Equatable {
    let id: String
    let name: String
    let available: Bool
    let binary: String?
}

/// Long-lived Bun stdio host for `packages/npm/agent-runner`.
///
/// Speaks agent-sessions under the covers (including ACP adapters when the
/// chosen harness uses them). Native chat drives: start → prompt → events → interrupt.
final class AgentRuntimeTransport {
    static let shared = AgentRuntimeTransport()

    /// Preferred harness order when the user has not picked one.
    /// Pi first: it has been the most reliable local one-shot for assistant chat
    /// on this stack; claude-code often exits 1 with an empty turn when not fully
    /// wired for non-interactive use.
    static let defaultHarnessPreference = ["pi", "claude-code", "codex", "opencode"]

    /// Harnesses whose agent-sessions adapter actually installs `systemPrompt`.
    /// Every other adapter (pi, claude-code, opencode) drops it on the floor,
    /// so for those the instructions ride in the first prompt of the session.
    static let harnessesHonoringSystemPrompt: Set<String> = ["codex"]

    /// Wall-clock for catalog/start/prompt-ack RPC (not the model turn itself).
    private static let requestTimeoutSeconds: TimeInterval = 12
    /// Default model-turn budget per harness for chat (cascade stays responsive).
    static let defaultTurnTimeoutSeconds: TimeInterval = 60

    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutSource: DispatchSourceRead?
    private var lineBuffer = Data()
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var pendingRequestTimeouts: [Int: DispatchWorkItem] = [:]
    private var nextRequestID = 1

    private var activeSessionID: String?
    private var activeHarness: String?
    /// Latest `session.model` from the adapter's `session:update` events.
    private var activeModel: String?
    /// `AgentRuntimeLaunch.key` the live session was started with.
    private var activeLaunchKey: String?
    /// Session that has already received the instructions (natively or inline).
    private var primedSessionID: String?
    /// Last turn context delivered, keyed by session, so unchanged state is not resent.
    private var deliveredContext: (sessionID: String, context: String)?
    /// Block id → block type ("text", "reasoning", "action", …) for the current turn.
    /// Only text blocks reach the transcript; reasoning must never leak into it.
    private var blockTypes: [String: String] = [:]
    private var accumulatedText = ""
    /// Last adapter/process error seen on stderr or session:update status=error.
    private var lastAdapterError: String?
    private var turnContinuation: CheckedContinuation<AgentRuntimeReply, Error>?
    private var turnTimeoutWork: DispatchWorkItem?
    private var onTextDelta: ((String) -> Void)?
    private var onTool: ((String) -> Void)?

    private init() {}

    // MARK: - Public

    /// Whether Bun + runner script exist and at least one non-echo harness (or echo) is available.
    func isAvailable() async -> Bool {
        guard bunURL != nil, runnerScriptURL != nil else { return false }
        do {
            let harnesses = try await catalog()
            return harnesses.contains(where: \.available)
        } catch {
            return false
        }
    }

    func catalog() async throws -> [AgentRuntimeHarness] {
        try await ensureProcess()
        let response = try await request(["op": "catalog"])
        guard let list = response["harnesses"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return AgentRuntimeHarness(
                id: id,
                name: (row["name"] as? String) ?? id,
                available: row["available"] as? Bool ?? false,
                binary: row["binary"] as? String
            )
        }
    }

    /// Pick the best available harness (user preference, then defaults, then any).
    func resolveHarness(preferred: String? = nil) async throws -> AgentRuntimeHarness {
        let harnesses = try await catalog()
        let available = harnesses.filter(\.available)
        guard !available.isEmpty else {
            throw AgentRuntimeTransportError.notAvailable(
                "No local agent runtime is installed (claude, codex, pi, or opencode)."
            )
        }
        if let preferred,
           let match = available.first(where: { $0.id == preferred }) {
            return match
        }
        for id in Self.defaultHarnessPreference {
            if let match = available.first(where: { $0.id == id }) {
                return match
            }
        }
        // Last resort: echo (dev) if somehow only that is available.
        if let echo = available.first(where: { $0.id == "echo" }) {
            return echo
        }
        return available[0]
    }

    /// Run one chat turn. Streams text deltas via `onDelta`.
    /// Tries preferred harness, then the rest of the preference list on empty/crash.
    /// `turnContext` is the live state for this turn (settings, attachments). It is
    /// sent inline with the prompt whenever it differs from what the session last saw,
    /// because the system prompt is fixed at session start.
    func ask(
        text: String,
        systemPrompt: String,
        turnContext: String? = nil,
        cwd: String,
        preferredHarness: String? = nil,
        launch: AgentRuntimeLaunch? = nil,
        onDelta: @escaping (String) -> Void,
        onTool: ((String) -> Void)? = nil,
        timeoutSeconds: TimeInterval = AgentRuntimeTransport.defaultTurnTimeoutSeconds
    ) async throws -> AgentRuntimeReply {
        let candidates = try await orderedAvailableHarnesses(preferred: preferredHarness)
        guard !candidates.isEmpty else {
            throw AgentRuntimeTransportError.notAvailable(
                "No local agent runtime is installed (pi, claude, codex, or opencode)."
            )
        }

        var lastError: Error = AgentRuntimeTransportError.emptyReply
        for (index, harness) in candidates.enumerated() {
            do {
                DiagnosticLog.shared.info(
                    "AgentRuntime · trying harness \(harness.id)\(index == 0 ? "" : " (fallback)")"
                )
                return try await askOnce(
                    text: text,
                    systemPrompt: systemPrompt,
                    turnContext: turnContext,
                    cwd: cwd,
                    harness: harness.id,
                    launch: launch?.harness == harness.id
                        ? launch!
                        : AgentRuntimeLaunch(harness: harness.id, model: nil, effort: nil),
                    onDelta: onDelta,
                    onTool: onTool,
                    timeoutSeconds: timeoutSeconds
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                DiagnosticLog.shared.warn(
                    "AgentRuntime · harness \(harness.id) failed: \(error.localizedDescription)"
                )
                // Force a fresh session for the next harness; restart process if
                // the stdio host itself hung or died.
                lock.lock()
                activeSessionID = nil
                activeHarness = nil
                lock.unlock()
                if error is AgentRuntimeTransportError {
                    let kind = error as? AgentRuntimeTransportError
                    switch kind {
                    case .timeout?, .requestTimeout?, .startFailed?:
                        restartProcess()
                    default:
                        break
                    }
                }
                continue
            }
        }
        throw lastError
    }

    private func orderedAvailableHarnesses(preferred: String?) async throws -> [AgentRuntimeHarness] {
        let available = try await catalog().filter(\.available)
        var ordered: [AgentRuntimeHarness] = []
        var seen = Set<String>()
        func append(_ id: String) {
            guard !seen.contains(id),
                  let match = available.first(where: { $0.id == id }) else { return }
            seen.insert(id)
            ordered.append(match)
        }
        if let preferred { append(preferred) }
        for id in Self.defaultHarnessPreference { append(id) }
        for h in available where h.id != "echo" { append(h.id) }
        return ordered
    }

    private func askOnce(
        text: String,
        systemPrompt: String,
        turnContext: String?,
        cwd: String,
        harness: String,
        launch: AgentRuntimeLaunch,
        onDelta: @escaping (String) -> Void,
        onTool: ((String) -> Void)?,
        timeoutSeconds: TimeInterval
    ) async throws -> AgentRuntimeReply {
        try await ensureSession(launch: launch, systemPrompt: systemPrompt, cwd: cwd)
        let outgoing = composeTurnText(
            text: text,
            systemPrompt: systemPrompt,
            turnContext: turnContext,
            harness: harness
        )

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AgentRuntimeReply, Error>) in
            lock.lock()
            if turnContinuation != nil {
                lock.unlock()
                cont.resume(throwing: AgentRuntimeTransportError.turnFailed("A turn is already in flight."))
                return
            }
            turnContinuation = cont
            accumulatedText = ""
            blockTypes.removeAll()
            lastAdapterError = nil
            self.onTextDelta = onDelta
            self.onTool = onTool
            lock.unlock()

            let timeout = DispatchWorkItem { [weak self] in
                self?.failTurn(AgentRuntimeTransportError.timeout)
            }
            lock.lock()
            turnTimeoutWork = timeout
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)

            Task {
                do {
                    _ = try await self.request([
                        "op": "prompt",
                        "sessionId": self.activeSessionID ?? "lattices-assistant",
                        "text": outgoing,
                    ])
                } catch {
                    self.failTurn(error)
                }
            }
        }
    }

    func interrupt() {
        guard let sessionID = activeSessionID else { return }
        Task {
            _ = try? await request(["op": "interrupt", "sessionId": sessionID])
        }
        failTurn(CancellationError())
    }

    func shutdown() {
        lock.lock()
        let cont = turnContinuation
        turnContinuation = nil
        turnTimeoutWork?.cancel()
        turnTimeoutWork = nil
        lock.unlock()
        cont?.resume(throwing: CancellationError())

        if let handle = stdinHandle {
            let line = (try? JSONSerialization.data(withJSONObject: ["op": "shutdown", "id": 0]))
                .flatMap { String(data: $0, encoding: .utf8) }
            if let line {
                try? handle.write(contentsOf: Data((line + "\n").utf8))
            }
        }
        process?.terminate()
        teardownProcess()
    }

    /// Wraps the user's text with whatever the session has not seen yet: the
    /// instructions (first turn, adapters that ignore `systemPrompt`) and the
    /// current state block (whenever it changed).
    private func composeTurnText(
        text: String,
        systemPrompt: String,
        turnContext: String?,
        harness: String
    ) -> String {
        lock.lock()
        let sessionID = activeSessionID ?? "lattices-assistant"
        let needsInstructions = primedSessionID != sessionID
            && !Self.harnessesHonoringSystemPrompt.contains(harness)
        primedSessionID = sessionID
        let context = turnContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let needsContext = !context.isEmpty
            && (deliveredContext?.sessionID != sessionID || deliveredContext?.context != context)
        if needsContext { deliveredContext = (sessionID, context) }
        lock.unlock()

        guard needsInstructions || needsContext else { return text }
        var parts: [String] = []
        if needsInstructions {
            parts.append("<lattices_instructions>\n\(systemPrompt)\n</lattices_instructions>")
        }
        if needsContext {
            parts.append(context)
        }
        parts.append("User request:\n\(text)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Session lifecycle

    private func ensureSession(launch: AgentRuntimeLaunch, systemPrompt: String, cwd: String) async throws {
        let harness = launch.harness
        try await ensureProcess()
        lock.lock()
        let same = activeSessionID != nil && activeHarness == harness && activeLaunchKey == launch.key
        lock.unlock()
        if same { return }

        // Drop prior session id; start fresh for harness / prompt changes.
        lock.lock()
        if activeLaunchKey != launch.key { activeModel = nil }
        activeSessionID = nil
        activeHarness = nil
        lock.unlock()

        let sessionID = "lattices-assistant-\(UUID().uuidString.prefix(8).lowercased())"
        var start: [String: Any] = [
            "op": "start",
            "sessionId": sessionID,
            "harness": harness,
            "name": "Lattices Assistant",
            "cwd": cwd,
            "systemPrompt": systemPrompt,
        ]
        start.merge(launch.startFields) { _, picked in picked }
        let response = try await request(start)
        guard response["ok"] as? Bool == true else {
            let err = response["error"] as? String ?? "start failed"
            throw AgentRuntimeTransportError.startFailed(err)
        }
        let resolvedID = (response["sessionId"] as? String) ?? sessionID
        lock.lock()
        activeSessionID = resolvedID
        activeHarness = harness
        activeLaunchKey = launch.key
        lock.unlock()
    }

    // MARK: - Process

    private var bunURL: URL? {
        LatticesRuntime.bunPath.map { URL(fileURLWithPath: $0) }
    }

    private var runnerScriptURL: URL? {
        let candidates: [String] = {
            var list: [String] = []
            if let root = LatticesRuntime.cliRoot {
                list.append(root + "/packages/npm/agent-runner/bin/agent-runner.mjs")
            }
            list.append(NSHomeDirectory() + "/dev/lattices/packages/npm/agent-runner/bin/agent-runner.mjs")
            return list
        }()
        return candidates
            .first(where: { FileManager.default.isReadableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    private func ensureProcess() async throws {
        lock.lock()
        let running = process?.isRunning == true
        lock.unlock()
        if running { return }

        guard let bunURL else { throw AgentRuntimeTransportError.bunMissing }
        guard let runnerScriptURL else { throw AgentRuntimeTransportError.runnerMissing }

        let proc = Process()
        proc.executableURL = bunURL
        proc.arguments = [runnerScriptURL.path]
        proc.currentDirectoryURL = runnerScriptURL
            .deletingLastPathComponent() // bin/
            .deletingLastPathComponent() // agent-runner/

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.enrichedPath
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        proc.terminationHandler = { [weak self] _ in
            self?.teardownProcess()
        }

        try proc.run()

        lock.lock()
        process = proc
        stdinHandle = stdin.fileHandleForWriting
        lock.unlock()

        let readHandle = stdout.fileHandleForReading
        let source = DispatchSource.makeReadSource(fileDescriptor: readHandle.fileDescriptor, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            let data = readHandle.availableData
            if data.isEmpty {
                self?.teardownProcess()
                return
            }
            self?.consumeStdout(data)
        }
        source.setCancelHandler {
            try? readHandle.close()
        }
        source.resume()

        // Surface `[session-registry] adapter error (…): …` from agent-runner.
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.consumeStderr(text)
        }

        lock.lock()
        stdoutSource = source
        lock.unlock()

        // Warm ping
        _ = try await request(["op": "ping"])
    }

    private func consumeStderr(_ text: String) {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            // Example: [session-registry] adapter error (t1): claude exited with code 1
            if let range = line.range(of: "adapter error") {
                let message = line[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                lock.lock()
                lastAdapterError = message.isEmpty ? line : message
                let hasTurn = turnContinuation != nil
                lock.unlock()
                DiagnosticLog.shared.warn("AgentRuntime · \(line)")
                // If a turn is live and the harness is already dead, fail promptly
                // rather than waiting for an empty turn:end.
                if hasTurn, message.localizedCaseInsensitiveContains("exited")
                    || message.localizedCaseInsensitiveContains("not running")
                    || message.localizedCaseInsensitiveContains("ENOENT") {
                    failTurn(AgentRuntimeTransportError.turnFailed(
                        message.isEmpty ? "Agent runtime crashed." : message
                    ))
                }
            } else if line.contains("error") || line.contains("Error") {
                DiagnosticLog.shared.info("AgentRuntime · stderr: \(line)")
            }
        }
    }

    private func teardownProcess() {
        lock.lock()
        stdoutSource?.cancel()
        stdoutSource = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        process = nil
        activeSessionID = nil
        activeHarness = nil
        let pending = pendingRequests
        pendingRequests.removeAll()
        for work in pendingRequestTimeouts.values { work.cancel() }
        pendingRequestTimeouts.removeAll()
        let turn = turnContinuation
        turnContinuation = nil
        turnTimeoutWork?.cancel()
        turnTimeoutWork = nil
        lock.unlock()

        for (_, cont) in pending {
            cont.resume(throwing: AgentRuntimeTransportError.turnFailed("Agent runtime process exited."))
        }
        turn?.resume(throwing: AgentRuntimeTransportError.turnFailed("Agent runtime process exited."))
    }

    private static var enrichedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let prefixes = [
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.opencode/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let existing = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        var seen = Set<String>()
        var parts: [String] = []
        for part in prefixes + existing where !part.isEmpty && seen.insert(part).inserted {
            parts.append(part)
        }
        return parts.joined(separator: ":")
    }

    // MARK: - Request / response

    private func request(_ fields: [String: Any]) async throws -> [String: Any] {
        try await ensureProcessRunningOnly()
        lock.lock()
        let id = nextRequestID
        nextRequestID += 1
        lock.unlock()
        var payload = fields
        payload["id"] = id

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard var line = String(data: data, encoding: .utf8) else {
            throw AgentRuntimeTransportError.turnFailed("Could not encode request.")
        }
        line += "\n"

        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            pendingRequests[id] = cont
            let handle = stdinHandle
            let timeout = DispatchWorkItem { [weak self] in
                self?.failPendingRequest(
                    id: id,
                    error: AgentRuntimeTransportError.requestTimeout
                )
            }
            pendingRequestTimeouts[id] = timeout
            lock.unlock()
            DispatchQueue.global().asyncAfter(
                deadline: .now() + Self.requestTimeoutSeconds,
                execute: timeout
            )
            guard let handle else {
                failPendingRequest(
                    id: id,
                    error: AgentRuntimeTransportError.turnFailed("Agent runtime stdin is closed.")
                )
                return
            }
            do {
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                failPendingRequest(
                    id: id,
                    error: AgentRuntimeTransportError.turnFailed("Agent runtime stdin write failed: \(error.localizedDescription)")
                )
            }
        }
    }

    private func failPendingRequest(id: Int, error: Error) {
        lock.lock()
        let cont = pendingRequests.removeValue(forKey: id)
        pendingRequestTimeouts.removeValue(forKey: id)?.cancel()
        lock.unlock()
        cont?.resume(throwing: error)
    }

    /// Kill and clear the Bun host so the next ensureProcess starts fresh.
    private func restartProcess() {
        DiagnosticLog.shared.warn("AgentRuntime · restarting stdio host after hard failure")
        shutdown()
    }

    private func ensureProcessRunningOnly() async throws {
        lock.lock()
        let running = process?.isRunning == true
        lock.unlock()
        if !running {
            try await ensureProcess()
        }
    }

    private func consumeStdout(_ data: Data) {
        lock.lock()
        lineBuffer.append(data)
        var chunks: [Data] = []
        while let range = lineBuffer.range(of: Data([0x0A])) {
            chunks.append(lineBuffer.subdata(in: lineBuffer.startIndex..<range.lowerBound))
            lineBuffer.removeSubrange(lineBuffer.startIndex...range.lowerBound)
        }
        lock.unlock()

        for chunk in chunks {
            guard !chunk.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if type == "response" {
                handleResponse(obj)
            } else if type == "event", let event = obj["event"] as? [String: Any] {
                handleEvent(event)
            }
        }
    }

    private func handleResponse(_ obj: [String: Any]) {
        let id = obj["id"] as? Int
        lock.lock()
        let cont: CheckedContinuation<[String: Any], Error>? = {
            guard let id else { return nil }
            pendingRequestTimeouts.removeValue(forKey: id)?.cancel()
            return pendingRequests.removeValue(forKey: id)
        }()
        lock.unlock()
        guard let cont else { return }
        if obj["ok"] as? Bool == false {
            let err = obj["error"] as? String ?? "request failed"
            cont.resume(throwing: AgentRuntimeTransportError.turnFailed(err))
        } else {
            cont.resume(returning: obj)
        }
    }

    /// Whether a block's content belongs in the visible reply. Untyped blocks
    /// (adapters that never sent block:start) count as text; any typed block
    /// other than "text" — reasoning, actions — does not. Call with `lock` held.
    private func isTextBlock(_ blockId: String?) -> Bool {
        guard let blockId, let type = blockTypes[blockId] else { return true }
        return type == "text"
    }

    private func handleEvent(_ event: [String: Any]) {
        let name = event["event"] as? String ?? ""

        switch name {
        case "block:start":
            if let block = event["block"] as? [String: Any],
               let type = block["type"] as? String,
               let blockId = block["id"] as? String {
                lock.lock()
                blockTypes[blockId] = type
                lock.unlock()
            }
            if let block = event["block"] as? [String: Any],
               let type = block["type"] as? String,
               type == "action",
               let action = block["action"] as? [String: Any],
               let toolName = action["toolName"] as? String {
                lock.lock()
                let cb = onTool
                lock.unlock()
                cb?(toolName)
            }

        case "block:delta":
            guard let text = event["text"] as? String, !text.isEmpty else { return }
            let blockId = event["blockId"] as? String
            lock.lock()
            let accept = isTextBlock(blockId)
            if accept {
                accumulatedText += text
            }
            let snapshot = accumulatedText
            let cb = onTextDelta
            lock.unlock()
            if accept {
                cb?(snapshot)
            }

        case "block:end":
            // Some adapters only put full text on block:end.
            if let blockId = event["blockId"] as? String {
                lock.lock()
                let isText = isTextBlock(blockId)
                lock.unlock()
                if isText, let text = event["text"] as? String, !text.isEmpty {
                    lock.lock()
                    if accumulatedText.isEmpty {
                        accumulatedText = text
                    } else if !accumulatedText.contains(text) {
                        accumulatedText += text
                    }
                    let snapshot = accumulatedText
                    let cb = onTextDelta
                    lock.unlock()
                    cb?(snapshot)
                }
            }
            if let block = event["block"] as? [String: Any],
               (block["type"] as? String) == "text",
               let text = block["text"] as? String,
               !text.isEmpty {
                lock.lock()
                if accumulatedText.isEmpty || text.count > accumulatedText.count {
                    accumulatedText = text
                }
                let snapshot = accumulatedText
                let cb = onTextDelta
                lock.unlock()
                cb?(snapshot)
            }

        case "block:action:status":
            break

        case "turn:end":
            finishTurn(status: event["status"] as? String)

        case "turn:error":
            let message = event["message"] as? String ?? "Agent turn error"
            failTurn(AgentRuntimeTransportError.turnFailed(message))

        case "session:update":
            if let session = event["session"] as? [String: Any],
               let model = session["model"] as? String,
               !model.isEmpty {
                lock.lock()
                activeModel = model
                lock.unlock()
            }
            if let session = event["session"] as? [String: Any],
               let status = session["status"] as? String,
               status == "error" {
                lock.lock()
                if lastAdapterError == nil {
                    lastAdapterError = "Agent session entered error state."
                }
                let hasTurn = turnContinuation != nil
                let err = lastAdapterError
                lock.unlock()
                if hasTurn, let err {
                    // Don't fail immediately on every error update — claude often
                    // errors after an empty turn:end. Keep for finishTurn.
                    DiagnosticLog.shared.warn("AgentRuntime · session error: \(err)")
                }
            }

        case "session:closed":
            lock.lock()
            activeSessionID = nil
            activeHarness = nil
            let hasTurn = turnContinuation != nil
            let err = lastAdapterError
            lock.unlock()
            // Harness died mid-turn without a clean turn:end.
            if hasTurn {
                failTurn(AgentRuntimeTransportError.turnFailed(
                    err ?? "Agent session closed before a reply."
                ))
            }

        default:
            break
        }
    }

    private func finishTurn(status: String?) {
        lock.lock()
        let cont = turnContinuation
        turnContinuation = nil
        turnTimeoutWork?.cancel()
        turnTimeoutWork = nil
        let text = accumulatedText
        let harness = activeHarness ?? "unknown"
        let model = activeModel
        let sessionId = activeSessionID ?? ""
        let adapterError = lastAdapterError
        onTextDelta = nil
        onTool = nil
        lock.unlock()

        guard let cont else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let reason: String
            if let adapterError, !adapterError.isEmpty {
                reason = adapterError
            } else if let status, status != "completed" {
                reason = "Agent turn ended (\(status)) without a text reply."
            } else {
                reason = "The agent finished without a text reply (harness may have exited early — check \(harness) is logged in)."
            }
            cont.resume(throwing: AgentRuntimeTransportError.turnFailed(reason))
        } else {
            cont.resume(returning: AgentRuntimeReply(text: trimmed, harness: harness, model: model, sessionId: sessionId))
        }
    }

    private func failTurn(_ error: Error) {
        lock.lock()
        let cont = turnContinuation
        turnContinuation = nil
        turnTimeoutWork?.cancel()
        turnTimeoutWork = nil
        onTextDelta = nil
        onTool = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

