import Foundation

struct ScoutAssistantReply {
    let text: String
    let bindingRef: String?
    let targetLabel: String?
}

enum ScoutAssistantTransportError: LocalizedError {
    case executableMissing
    case invalidResponse(String)
    case commandFailed(String)
    case emptyReply
    /// Flight parked for an offline/offline-queued target — not worth a 10‑minute wait.
    case targetOffline(summary: String, targetLabel: String?)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "Scout is not installed or could not be found. Install Scout, then try again."
        case .invalidResponse(let detail):
            return "Scout returned an unreadable response. \(detail)"
        case .commandFailed(let detail):
            return detail.isEmpty ? "Scout could not complete this turn." : detail
        case .emptyReply:
            return "Scout completed the turn without returning a reply."
        case .targetOffline(let summary, let targetLabel):
            let target = (targetLabel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            // Keep user-facing copy product-level; avoid "Waiting for …" style transport copy.
            if let target {
                return "The assistant session is offline (\(target)). \(summary) The binding was cleared — try again."
            }
            return "The assistant session is offline. \(summary) The binding was cleared — try again."
        }
    }

    /// True when the binding should be dropped so the next ask re-resolves a live target.
    var shouldClearBinding: Bool {
        if case .targetOffline = self { return true }
        // Stale / retired refs also need a clean project re-route.
        if case .commandFailed(let detail) = self {
            return ScoutAssistantTransport.isUnroutableBindingDetail(detail)
        }
        return false
    }
}

/// Canonical bridge to the user's existing local Scout broker. Lattices never
/// owns model credentials for chat: Scout resolves the project worker and
/// returns a durable binding ref that keeps follow-up turns in the same session.
final class ScoutAssistantTransport {
    private let processLock = NSLock()
    private var activeProcess: Process?

    /// A saved Scout ref is continuity metadata, not a permanent route. Broker
    /// restarts and retired sessions can invalidate it while project routing is
    /// still healthy, so callers may safely clear the ref and retry.
    static func isUnroutableBindingError(_ error: Error) -> Bool {
        if let transportError = error as? ScoutAssistantTransportError {
            if transportError.shouldClearBinding { return true }
            if case .commandFailed(let detail) = transportError {
                return isUnroutableBindingDetail(detail)
            }
            return false
        }
        return isUnroutableBindingDetail(error.localizedDescription)
    }

    static func isUnroutableBindingDetail(_ detail: String) -> Bool {
        let normalized = detail.lowercased()
        return normalized.contains("not currently routable")
            || (normalized.contains("no agent matches") && normalized.contains("ref:"))
    }

    var isInstalled: Bool { executableURL != nil }

    func checkAvailability(projectPath: String?) async -> Bool {
        do {
            _ = try await run(
                arguments: ["--json", "whoami"],
                currentDirectory: projectPath,
                trackForCancellation: false
            )
            return true
        } catch {
            return false
        }
    }

    func ask(prompt: String, projectPath: String, bindingRef: String?) async throws -> ScoutAssistantReply {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lattices-scout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let promptURL = tempRoot.appendingPathComponent("prompt.md")
        try prompt.write(to: promptURL, atomically: true, encoding: .utf8)

        var arguments = ["--json", "ask"]
        if let bindingRef, !bindingRef.isEmpty {
            arguments += ["--ref", Self.normalizedRef(bindingRef)]
        } else {
            arguments += ["--project", projectPath]
        }
        arguments += ["--reply-mode", "none", "--no-wait", "--prompt-file", promptURL.path]

        let receiptData = try await run(arguments: arguments, currentDirectory: projectPath)
        let receipt = try Self.jsonObject(from: receiptData)
        let receiptBody = receipt["receipt"] as? [String: Any]
        let ids = receiptBody?["ids"] as? [String: Any]
        let invocationID = Self.string(in: ids, key: "invocationId")
        let nextRef = Self.string(in: receipt, key: "bindingRef")
            ?? Self.string(in: ids, key: "bindingRef")
            ?? bindingRef
        let targetLabel = Self.string(in: ids, key: "targetAgentId")

        let receiptFlight = receipt["flight"] as? [String: Any]
        if let immediate = Self.replyText(fromFlight: receiptFlight) {
            return ScoutAssistantReply(text: immediate, bindingRef: nextRef, targetLabel: targetLabel)
        }

        // Offline targets return state=queued with "when online" and never complete
        // until the session wakes — do not hang the composer for the full wait window.
        if let offline = Self.offlineQueueError(fromFlight: receiptFlight, targetLabel: targetLabel) {
            throw offline
        }

        guard let invocationID, !invocationID.isEmpty else {
            throw ScoutAssistantTransportError.invalidResponse("The ask receipt did not include an invocation id.")
        }

        // Cap wait well under Scout's multi-minute parking window so a stuck
        // flight surfaces as an error instead of a permanent LIVE / Composing card.
        let waitData = try await run(
            arguments: ["--json", "wait", invocationID, "--timeout", "90"],
            currentDirectory: projectPath
        )
        let wait = try Self.jsonObject(from: waitData)
        if let error = Self.string(in: wait, key: "error"), !error.isEmpty {
            throw ScoutAssistantTransportError.commandFailed(error)
        }

        let waitFlight = wait["flight"] as? [String: Any] ?? receiptFlight
        if wait["timedOut"] as? Bool == true {
            if let offline = Self.offlineQueueError(fromFlight: waitFlight, targetLabel: targetLabel) {
                throw offline
            }
            let summary = Self.string(in: waitFlight, key: "summary")
                ?? Self.string(in: wait, key: "summary")
                ?? "No reply yet."
            throw ScoutAssistantTransportError.commandFailed(
                "Scout timed out waiting for a reply. \(summary)"
            )
        }

        guard let output = Self.string(in: wait, key: "output")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            if let offline = Self.offlineQueueError(fromFlight: waitFlight, targetLabel: targetLabel) {
                throw offline
            }
            if let summary = Self.string(in: wait, key: "summary")?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                return ScoutAssistantReply(text: summary, bindingRef: nextRef, targetLabel: targetLabel)
            }
            throw ScoutAssistantTransportError.emptyReply
        }
        return ScoutAssistantReply(text: output, bindingRef: nextRef, targetLabel: targetLabel)
    }

    func cancelCurrentTurn() {
        let process = currentProcess()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private var executableURL: URL? {
        let pathCandidates = Self.enrichedPath
            .split(separator: ":")
            .map { String($0) + "/scout" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = pathCandidates + [
            "\(home)/.bun/bin/scout",
            "\(home)/.local/bin/scout",
            "/opt/homebrew/bin/scout",
            "/usr/local/bin/scout",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    /// PATH with common user install prefixes prepended so GUI-spawned Scout
    /// can resolve `bun` / `node` (macOS LaunchServices PATH is often bare).
    private static var enrichedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let prefixes = [
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
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

    private static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = enrichedPath
        return env
    }

    private func run(
        arguments: [String],
        currentDirectory: String?,
        trackForCancellation: Bool = true
    ) async throws -> Data {
        guard let executableURL else { throw ScoutAssistantTransportError.executableMissing }

        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            try Task.checkCancellation()

            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("lattices-scout-process-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let stdoutURL = tempRoot.appendingPathComponent("stdout")
            let stderrURL = tempRoot.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdout.close()
                try? stderr.close()
            }

            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            // GUI apps inherit a minimal PATH from LaunchServices, so scout's
            // shell wrapper cannot find bun/node unless we restore user bins.
            process.environment = Self.processEnvironment()
            if let currentDirectory, FileManager.default.fileExists(atPath: currentDirectory) {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
            }
            process.standardOutput = stdout
            process.standardError = stderr

            if trackForCancellation { self.setActiveProcess(process) }
            defer {
                if trackForCancellation { self.clearActiveProcess(process) }
            }

            try process.run()
            // Wall-clock cap so a hung scout binary cannot leave the composer on
            // "Composing…" forever (wait --timeout alone is not enough if the
            // process never returns).
            let wallSeconds = Self.wallClockSeconds(for: arguments)
            let deadline = Date().addingTimeInterval(wallSeconds)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
                try Task.checkCancellation()
            }
            if process.isRunning {
                process.terminate()
                // Brief grace, then hard kill if still alive.
                let killDeadline = Date().addingTimeInterval(1.0)
                while process.isRunning, Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    process.interrupt()
                }
                throw ScoutAssistantTransportError.commandFailed(
                    "Scout timed out after \(Int(wallSeconds))s (\(arguments.dropFirst().prefix(3).joined(separator: " ")))."
                )
            }
            try stdout.synchronize()
            try stderr.synchronize()
            try Task.checkCancellation()

            let output = try Data(contentsOf: stdoutURL)
            let errorData = try Data(contentsOf: stderrURL)
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                throw ScoutAssistantTransportError.commandFailed(errorText)
            }
            guard !output.isEmpty else {
                throw ScoutAssistantTransportError.invalidResponse(errorText)
            }
            return output
        }.value
    }

    /// Max seconds a Scout subprocess may live before Lattices kills it.
    static func wallClockSeconds(for arguments: [String]) -> TimeInterval {
        if arguments.contains("wait") { return 105 }
        if arguments.contains("whoami") { return 8 }
        if arguments.contains("ask") { return 45 }
        return 30
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ScoutAssistantTransportError.invalidResponse(text)
        }
        return object
    }

    private static func string(in object: [String: Any]?, key: String) -> String? {
        object?[key] as? String
    }

    private static func replyText(fromFlight flight: [String: Any]?) -> String? {
        guard flight?["state"] as? String == "completed" else { return nil }
        return (flight?["output"] as? String) ?? (flight?["summary"] as? String)
    }

    /// Detect Scout parking a flight for a session that is not currently online.
    static func offlineQueueError(
        fromFlight flight: [String: Any]?,
        targetLabel: String?
    ) -> ScoutAssistantTransportError? {
        guard let flight else { return nil }
        let state = (flight["state"] as? String)?.lowercased() ?? ""
        let summary = string(in: flight, key: "summary")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let looksOffline =
            summary.localizedCaseInsensitiveContains("when online")
            || summary.localizedCaseInsensitiveContains("will deliver when")
            || summary.localizedCaseInsensitiveContains("offline")
        let parked = state == "queued" || state == "pending" || state == "deferred"
        // Definitive signal: parked + offline wording (e.g. "Will deliver when online").
        guard parked && looksOffline else { return nil }
        return .targetOffline(
            summary: summary.isEmpty ? "Will deliver when the target is online." : summary,
            targetLabel: targetLabel ?? string(in: flight, key: "targetAgentId")
        )
    }

    private static func normalizedRef(_ value: String) -> String {
        value.hasPrefix("ref:") ? String(value.dropFirst(4)) : value
    }

    private func setActiveProcess(_ process: Process) {
        processLock.lock()
        activeProcess = process
        processLock.unlock()
    }

    private func clearActiveProcess(_ process: Process) {
        processLock.lock()
        if activeProcess === process { activeProcess = nil }
        processLock.unlock()
    }

    private func currentProcess() -> Process? {
        processLock.lock()
        defer { processLock.unlock() }
        return activeProcess
    }
}
