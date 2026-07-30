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
        }
    }
}

/// Canonical bridge to the user's existing local Scout broker. Lattices never
/// owns model credentials for chat: Scout resolves the project worker and
/// returns a durable binding ref that keeps follow-up turns in the same session.
final class ScoutAssistantTransport {
    private let processLock = NSLock()
    private var activeProcess: Process?

    var isInstalled: Bool { executableURL != nil }

    /// A saved Scout ref is continuity metadata, not a permanent route. Broker
    /// restarts and retired sessions can invalidate it while project routing is
    /// still healthy, so callers may safely retry these errors without the ref.
    static func isUnroutableBindingError(_ error: Error) -> Bool {
        guard let transportError = error as? ScoutAssistantTransportError,
              case .commandFailed(let detail) = transportError else { return false }
        let normalized = detail.lowercased()
        return normalized.contains("not currently routable")
            || (normalized.contains("no agent matches") && normalized.contains("ref:"))
    }

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

        if let immediate = Self.replyText(fromFlight: receipt["flight"] as? [String: Any]) {
            return ScoutAssistantReply(text: immediate, bindingRef: nextRef, targetLabel: targetLabel)
        }

        guard let invocationID, !invocationID.isEmpty else {
            throw ScoutAssistantTransportError.invalidResponse("The ask receipt did not include an invocation id.")
        }

        let waitData = try await run(
            arguments: ["--json", "wait", invocationID, "--timeout", "600"],
            currentDirectory: projectPath
        )
        let wait = try Self.jsonObject(from: waitData)
        if let error = Self.string(in: wait, key: "error"), !error.isEmpty {
            throw ScoutAssistantTransportError.commandFailed(error)
        }
        guard let output = Self.string(in: wait, key: "output")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
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
        let environment = ProcessInfo.processInfo.environment
        let pathCandidates = (environment["PATH"] ?? "")
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
            process.waitUntilExit()
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
