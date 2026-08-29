import ActionCore
import Foundation

final class ActionAgentCommandBridge {
    private let client = ActionAgentClient()
    private var process: Process?

    func send(method: ActionAgentMethod, params: [String: String] = [:]) async throws -> ActionAgentResponse {
        try await ensureAgentAvailable()
        return try await client.send(method: method, params: params)
    }

    func dispatch(method: ActionAgentMethod, params: [String: String] = [:]) async throws {
        try await ensureAgentAvailable()
        try await client.dispatch(method: method, params: params)
    }

    private func ensureAgentAvailable() async throws {
        do {
            _ = try await client.send(method: .ping)
            return
        } catch {
            if process?.isRunning != true {
                try startEphemeralAgent()
            }
        }

        for _ in 0..<20 {
            do {
                _ = try await client.send(method: .ping)
                return
            } catch {
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        _ = try await client.send(method: .ping)
    }

    private func startEphemeralAgent() throws {
        let executableURL = try resolveAgentExecutableURL()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "agent",
            "--port", String(ActionAgentDefaults.port),
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        self.process = process
    }

    private func resolveAgentExecutableURL() throws -> URL {
        if let mainExecutableURL = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: mainExecutableURL.path(percentEncoded: false)) {
            return mainExecutableURL
        }

        let helperExecutable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ActionAgent.app", isDirectory: true)
            .appendingPathComponent("Contents/MacOS/ActionAgent", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: helperExecutable.path(percentEncoded: false)) {
            return helperExecutable
        }

        let sibling = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ActionAgent", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: sibling.path(percentEncoded: false)) {
            return sibling
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("ActionAgent", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: bundled.path(percentEncoded: false)) {
                return bundled
            }
        }

        throw NSError(
            domain: "ActionAgentCommandBridge",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate ActionAgent executable for command bridge"]
        )
    }
}
