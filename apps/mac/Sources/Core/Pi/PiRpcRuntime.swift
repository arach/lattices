import Foundation

/// Long-lived `pi --mode rpc` client. JSON lines on stdin/stdout (see `bin/project-twin.ts`).
final class PiRpcRuntime {
    enum RuntimeError: LocalizedError {
        case notStarted
        case processExited(String)
        case timedOut(String)
        case commandFailed(String)
        case invalidResponse(String)
        case emptyAssistantText(String)

        var errorDescription: String? {
            switch self {
            case .notStarted:
                return "Pi RPC runtime is not started."
            case .processExited(let detail):
                return "Pi RPC process exited. \(detail)"
            case .timedOut(let detail):
                return "Timed out waiting for Pi. \(detail)"
            case .commandFailed(let detail):
                return detail
            case .invalidResponse(let detail):
                return "Pi RPC returned an invalid response. \(detail)"
            case .emptyAssistantText(let detail):
                return "Pi returned no assistant text. \(detail)"
            }
        }
    }

    private struct PendingRequest {
        let commandDescription: String
        let completion: (Result<[String: Any], Error>) -> Void
        let timeoutWorkItem: DispatchWorkItem
    }

    private let piPath: String
    private let sessionDir: URL
    private let providerID: String
    private let modelID: String
    private let environment: [String: String]
    private let appendSystemPrompt: String
    private let disableBuiltInTools: Bool
    private let defaultTimeout: TimeInterval

    private let workQueue = DispatchQueue(label: "pi-rpc-runtime-work", qos: .userInitiated)
    private let lock = NSLock()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var recentStdoutLines: [String] = []
    private var recentInvalidStdoutLines: [String] = []
    private var requestCounter = 0
    private var pendingRequests: [String: PendingRequest] = [:]
    private var eventHandlers: [String: ([String: Any]) -> Void] = [:]

    private static let recentOutputLimit = 8
    private static let outputLineLimit = 1_000

    init(
        piPath: String,
        sessionDir: URL,
        providerID: String,
        modelID: String,
        environment: [String: String],
        appendSystemPrompt: String,
        disableBuiltInTools: Bool = false,
        defaultTimeout: TimeInterval = 120
    ) {
        self.piPath = piPath
        self.sessionDir = sessionDir
        self.providerID = providerID
        self.modelID = modelID
        self.environment = environment
        self.appendSystemPrompt = appendSystemPrompt
        self.disableBuiltInTools = disableBuiltInTools
        self.defaultTimeout = defaultTimeout
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    func stop() {
        workQueue.async {
            self.stopLocked()
        }
    }

    func newSession(parentSession: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        workQueue.async {
            do {
                try self.startIfNeededLocked()
                var command: [String: Any] = ["type": "new_session"]
                if let parentSession {
                    command["parentSession"] = parentSession
                }
                _ = try self.sendLocked(command, timeout: self.defaultTimeout)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func promptAndFetchAssistantText(
        _ message: String,
        onEvent: (([String: Any]) -> Void)? = nil,
        timeout: TimeInterval? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        workQueue.async {
            do {
                let text = try self.promptAndFetchAssistantTextLocked(
                    message,
                    onEvent: onEvent,
                    timeout: timeout
                )
                completion(.success(text))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func promptAndFetchAssistantTextLocked(
        _ message: String,
        onEvent: (([String: Any]) -> Void)?,
        timeout: TimeInterval?
    ) throws -> String {
        try startIfNeededLocked()
        let waitTimeout = timeout ?? defaultTimeout

        if let onEvent {
            let streamHandlerID = "stream-\(UUID().uuidString)"
            lock.lock()
            eventHandlers[streamHandlerID] = onEvent
            lock.unlock()
            defer {
                lock.lock()
                eventHandlers.removeValue(forKey: streamHandlerID)
                lock.unlock()
            }
            _ = try waitForAgentEndLocked(timeout: waitTimeout) {
                _ = try self.sendLocked(["type": "prompt", "message": message], timeout: waitTimeout)
            }
        } else {
            _ = try waitForAgentEndLocked(timeout: waitTimeout) {
                _ = try self.sendLocked(["type": "prompt", "message": message], timeout: waitTimeout)
            }
        }

        let response = try sendLocked(["type": "get_last_assistant_text"], timeout: waitTimeout)
        guard let data = response["data"] as? [String: Any] else {
            throw RuntimeError.invalidResponse(
                diagnosticSummary(reason: "Missing data payload for get_last_assistant_text.", command: "get_last_assistant_text")
            )
        }
        if let text = data["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw RuntimeError.emptyAssistantText(
            diagnosticSummary(reason: "get_last_assistant_text returned an empty text field.", command: "get_last_assistant_text")
        )
    }

    // MARK: - Process lifecycle

    private func startIfNeededLocked() throws {
        lock.lock()
        defer { lock.unlock() }

        if process?.isRunning == true { return }

        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: piPath)
        proc.arguments = buildPiArguments()
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        proc.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            throw RuntimeError.commandFailed("Failed to launch Pi RPC: \(error.localizedDescription)")
        }

        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        stderrBuffer = ""
        stdoutBuffer = ""
        recentStdoutLines = []
        recentInvalidStdoutLines = []

        let stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            self.consumeStdoutChunk(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            self.lock.lock()
            self.stderrBuffer += chunk
            self.lock.unlock()
        }

        proc.terminationHandler = { [weak self] _ in
            self?.workQueue.async {
                self?.handleProcessExitLocked(proc)
            }
        }
    }

    private func stopLocked() {
        lock.lock()
        let proc = process
        process = nil
        stdinHandle = nil
        lock.unlock()

        failPendingRequestsLocked(RuntimeError.processExited(
            diagnosticSummary(reason: "Pi RPC runtime was stopped before the pending request completed.")
        ))

        guard let proc else { return }
        if proc.isRunning {
            proc.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if proc.isRunning {
                    proc.interrupt()
                }
            }
        }
    }

    private func handleProcessExitLocked(_ proc: Process) {
        let exitStatus = proc.terminationStatus
        let terminationReason = Self.terminationReasonDescription(proc.terminationReason)
        lock.lock()
        process = nil
        stdinHandle = nil
        lock.unlock()
        failPendingRequestsLocked(RuntimeError.processExited(
            diagnosticSummary(
                reason: "Pi RPC subprocess exited before returning a response.",
                exitStatus: exitStatus,
                terminationReason: terminationReason
            )
        ))
    }

    private func buildPiArguments() -> [String] {
        var args = [
            "--mode", "rpc",
            "--session-dir", sessionDir.path,
            "--provider", providerID,
            "--model", modelID,
            "--no-extensions",
            "--no-skills",
            "--no-prompt-templates",
        ]
        let trimmedPrompt = appendSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            args.append(contentsOf: ["--append-system-prompt", trimmedPrompt])
        }
        if disableBuiltInTools {
            args.append("--no-builtin-tools")
        }
        return args
    }

    // MARK: - Streaming helpers

    static func streamingDelta(from event: [String: Any]) -> String? {
        guard event["type"] as? String == "message_update",
              let assistantEvent = event["assistantMessageEvent"] as? [String: Any],
              assistantEvent["type"] as? String == "text_delta",
              let delta = assistantEvent["delta"] as? String else {
            return nil
        }
        return delta
    }

    static func streamingSnapshot(from event: [String: Any]) -> String? {
        guard event["type"] as? String == "message_update",
              let message = event["message"] as? [String: Any],
              message["role"] as? String == "assistant" else {
            return nil
        }
        return extractAssistantText(from: message)
    }

    static func extractAssistantText(from message: [String: Any]) -> String? {
        guard let content = message["content"] else { return nil }
        if let text = content as? String {
            return text
        }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let parts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text", let text = block["text"] as? String else { return nil }
            return text
        }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - RPC

    private func waitForAgentEndLocked(timeout: TimeInterval, sendPrompt: () throws -> Void) throws -> [[String: Any]] {
        final class Collector {
            var events: [[String: Any]] = []
            var finished = false
            var error: Error?
        }

        let collector = Collector()
        let semaphore = DispatchSemaphore(value: 0)
        let handlerID = "event-\(UUID().uuidString)"

        lock.lock()
        eventHandlers[handlerID] = { payload in
            collector.events.append(payload)
            if payload["type"] as? String == "agent_end" {
                collector.finished = true
                semaphore.signal()
            }
        }
        lock.unlock()

        defer {
            lock.lock()
            eventHandlers.removeValue(forKey: handlerID)
            lock.unlock()
        }

        let timeoutWork = DispatchWorkItem {
            collector.error = RuntimeError.timedOut(self.diagnosticSummary(
                reason: "Timed out waiting for Pi to finish the assistant turn.",
                command: "prompt",
                extra: Self.eventSummaryLines(collector.events)
            ))
            semaphore.signal()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        do {
            try sendPrompt()
        } catch {
            timeoutWork.cancel()
            throw error
        }

        semaphore.wait()
        timeoutWork.cancel()

        if let error = collector.error {
            throw error
        }
        if !collector.finished {
            throw RuntimeError.timedOut(diagnosticSummary(
                reason: "Pi event stream ended without an agent_end event.",
                command: "prompt",
                extra: Self.eventSummaryLines(collector.events)
            ))
        }
        return collector.events
    }

    private func sendLocked(_ command: [String: Any], timeout: TimeInterval) throws -> [String: Any] {
        let commandType = command["type"] as? String ?? "unknown"
        lock.lock()
        guard process?.isRunning == true, let stdinHandle else {
            lock.unlock()
            throw RuntimeError.notStarted
        }

        let id = "req_\(requestCounter)"
        requestCounter += 1
        lock.unlock()

        var payload = command
        payload["id"] = id

        guard let lineData = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: lineData, encoding: .utf8) else {
            throw RuntimeError.invalidResponse(
                diagnosticSummary(reason: "Failed to encode Pi RPC command.", command: commandType)
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        var resolved: Result<[String: Any], Error>?

        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resolveTimedOutRequest(id: id, semaphore: semaphore)
        }

        lock.lock()
        pendingRequests[id] = PendingRequest(
            commandDescription: commandType,
            completion: { result in
                resolved = result
                semaphore.signal()
            },
            timeoutWorkItem: timeoutWork
        )
        lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        stdinHandle.write(Data((line + "\n").utf8))
        semaphore.wait()
        timeoutWork.cancel()

        lock.lock()
        pendingRequests.removeValue(forKey: id)
        lock.unlock()

        guard let resolved else {
            throw RuntimeError.invalidResponse(
                diagnosticSummary(reason: "Pi RPC request completed without a result.", command: commandType)
            )
        }
        let response = try resolved.get()

        guard response["type"] as? String == "response" else {
            throw RuntimeError.invalidResponse(
                diagnosticSummary(
                    reason: "Unexpected response envelope for Pi RPC command.",
                    command: commandType,
                    extra: ["Response keys: \(response.keys.sorted().joined(separator: ", "))"]
                )
            )
        }
        let success = response["success"] as? Bool ?? false
        if !success {
            let message = response["error"] as? String ?? "Pi RPC command failed."
            throw RuntimeError.commandFailed(diagnosticSummary(
                reason: "Pi RPC command failed: \(message)",
                command: commandType
            ))
        }
        return response
    }

    private func resolveTimedOutRequest(id: String, semaphore: DispatchSemaphore) {
        lock.lock()
        guard let pending = pendingRequests.removeValue(forKey: id) else {
            lock.unlock()
            return
        }
        lock.unlock()
        pending.timeoutWorkItem.cancel()
        pending.completion(.failure(RuntimeError.timedOut(diagnosticSummary(
            reason: "Timed out waiting for Pi RPC response.",
            command: pending.commandDescription
        ))))
        semaphore.signal()
    }

    private func consumeStdoutChunk(_ chunk: String) {
        lock.lock()
        stdoutBuffer += chunk
        var lines: [String] = []
        while let newlineIndex = stdoutBuffer.firstIndex(of: "\n") {
            let line = String(stdoutBuffer[..<newlineIndex])
            stdoutBuffer = String(stdoutBuffer[stdoutBuffer.index(after: newlineIndex)...])
            let trimmed = line.trimmingCharacters(in: .newlines)
            if !trimmed.isEmpty {
                Self.appendRecentLineLocked(trimmed, to: &recentStdoutLines)
                lines.append(trimmed)
            }
        }
        lock.unlock()

        for line in lines {
            handleStdoutLine(line)
        }
    }

    private func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lock.lock()
            Self.appendRecentLineLocked(line, to: &recentInvalidStdoutLines)
            lock.unlock()
            return
        }

        if payload["type"] as? String == "response",
           let id = payload["id"] as? String {
            lock.lock()
            let pending = pendingRequests.removeValue(forKey: id)
            lock.unlock()

            if let pending {
                pending.timeoutWorkItem.cancel()
                pending.completion(.success(payload))
                return
            }
        }

        lock.lock()
        let handlers = Array(eventHandlers.values)
        lock.unlock()
        for handler in handlers {
            handler(payload)
        }
    }

    private func failPendingRequestsLocked(_ error: Error) {
        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        for entry in pending.values {
            entry.timeoutWorkItem.cancel()
            entry.completion(.failure(error))
        }
    }

    private func diagnosticSummary(
        reason: String,
        command: String? = nil,
        exitStatus: Int32? = nil,
        terminationReason: String? = nil,
        extra: [String] = []
    ) -> String {
        lock.lock()
        let proc = process
        let stderr = stderrBuffer
        let partialStdout = stdoutBuffer
        let stdoutLines = recentStdoutLines
        let invalidStdoutLines = recentInvalidStdoutLines
        lock.unlock()

        var lines: [String] = [reason]
        if let command {
            lines.append("RPC command: \(command)")
        }
        if let proc {
            lines.append("Process: pid \(proc.processIdentifier), running \(proc.isRunning)")
        }
        if let exitStatus {
            lines.append("Exit status: \(exitStatus)")
        }
        if let terminationReason {
            lines.append("Termination: \(terminationReason)")
        }
        lines.append("Provider/model: \(providerID)/\(modelID)")
        lines.append("Session dir: \(sessionDir.path)")
        lines.append(contentsOf: extra)

        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("stderr: \(trimmed.isEmpty ? "<empty>" : Self.clipped(trimmed, limit: 2_000))")

        if !invalidStdoutLines.isEmpty {
            lines.append("Malformed stdout:")
            lines.append(contentsOf: invalidStdoutLines.map { "  " + $0 })
        }
        if !stdoutLines.isEmpty {
            lines.append("Recent stdout:")
            lines.append(contentsOf: stdoutLines.map { "  " + $0 })
        }
        let partial = partialStdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            lines.append("Partial stdout: \(Self.clipped(partial, limit: 1_000))")
        }

        return lines.joined(separator: "\n")
    }

    private static func appendRecentLineLocked(_ line: String, to lines: inout [String]) {
        lines.append(clipped(line.trimmingCharacters(in: .whitespacesAndNewlines), limit: outputLineLimit))
        if lines.count > recentOutputLimit {
            lines.removeFirst(lines.count - recentOutputLimit)
        }
    }

    private static func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "… [truncated]"
    }

    private static func terminationReasonDescription(_ reason: Process.TerminationReason) -> String {
        switch reason {
        case .exit:
            return "exit"
        case .uncaughtSignal:
            return "uncaught signal"
        @unknown default:
            return "unknown"
        }
    }

    private static func eventSummaryLines(_ events: [[String: Any]]) -> [String] {
        var lines = ["Events received: \(events.count)"]
        let types = events.suffix(6).map { payload -> String in
            let type = payload["type"] as? String ?? "unknown"
            if let tool = payload["toolName"] as? String {
                return "\(type)(\(tool))"
            }
            return type
        }
        if !types.isEmpty {
            lines.append("Recent events: \(types.joined(separator: " -> "))")
        }
        return lines
    }
}
