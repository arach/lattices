import ActionCore
import Foundation
import OSLog

@MainActor
final class ActionAgentProcessController {
    private let logger = Logger(subsystem: "dev.action.Action", category: "AgentProcess")
    private let port: UInt16
    private var process: Process?

    init(port: UInt16 = ActionAgentDefaults.port) {
        self.port = port
    }

    func startIfNeeded() throws {
        if let process, process.isRunning {
            return
        }

        let executableURL = try resolveAgentExecutableURL()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["agent", "--port", String(port), "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        self.process = process
        logger.notice("Started ActionAgent at \(executableURL.path(percentEncoded: false), privacy: .public) on port \(self.port, privacy: .public)")
    }

    func stopIfNeeded() {
        guard let process else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    /// The bundled helper comes first, and the app's own executable is the
    /// fallback — not the other way round.
    ///
    /// Re-running `Contents/MacOS/Action` with `agent` works, but it puts a
    /// second process named `Action`, inside the `Action.app` bundle, in the
    /// process table. macOS then counts it as a second instance of the app, so
    /// a quit Apple Event is addressed to it as well; it has no run loop to
    /// answer one, and every caller that waits for "all instances of
    /// dev.action.Action to go away" times out and reports that the app
    /// refused to quit — when in fact the window had closed immediately. That
    /// is what made `pkill` look like the only reliable way to stop Action.
    ///
    /// `ActionAgent.app` has its own bundle id and `LSUIElement`, so the same
    /// child is unambiguous both to LaunchServices and to `pgrep`. The main
    /// executable stays as the fallback for running out of a bare build
    /// directory, where the helper bundle does not exist.
    private func resolveAgentExecutableURL() throws -> URL {
        let helperExecutable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ActionAgent.app", isDirectory: true)
            .appendingPathComponent("Contents/MacOS/ActionAgent", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: helperExecutable.path(percentEncoded: false)) {
            return helperExecutable
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("ActionAgent", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: bundled.path(percentEncoded: false)) {
                return bundled
            }
        }

        let sibling = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ActionAgent", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: sibling.path(percentEncoded: false)) {
            return sibling
        }

        // Bare build directory: no helper bundle, so the host binary serves as
        // its own agent. Safe here because there is no .app for the second
        // process to be mistaken for an instance of.
        if let mainExecutableURL = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: mainExecutableURL.path(percentEncoded: false)) {
            return mainExecutableURL
        }

        throw NSError(
            domain: "ActionAgentProcessController",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate bundled ActionAgent executable"]
        )
    }
}
