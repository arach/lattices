import AppKit

/// Brings the pointer back after sharing it with lan-mouse: every client is
/// deactivated so nothing captures at a screen edge any more, then the cursor
/// lands in the middle of the main display. A daemon that doesn't answer is
/// stopped, since a hung capture is what keeps the cursor away. With no
/// lan-mouse at all it only warps.
enum PointerHome {
    struct Client: Equatable {
        let id: Int
        let host: String
        let active: Bool
    }

    struct Result {
        var deactivated: [String] = []
        var stoppedDaemon = false
        var lanMouse = true
    }

    static let timeout: TimeInterval = 2

    static let binaryCandidates = [
        "~/Applications/Lan Mouse.app/Contents/MacOS/lan-mouse",
        "/Applications/Lan Mouse.app/Contents/MacOS/lan-mouse",
        "/opt/homebrew/bin/lan-mouse",
        "/usr/local/bin/lan-mouse",
    ]

    static func binary() -> String? {
        binaryCandidates
            .map { ($0 as NSString).expandingTildeInPath }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Parses `lan-mouse cli list`, one line per client:
    /// `id 0: archie:4242 (left) active: true, ips: {…}`
    static func parseClients(_ output: String) -> [Client] {
        output.split(separator: "\n").compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("id "), let colon = line.firstIndex(of: ":") else { return nil }
            guard let id = Int(line[line.index(line.startIndex, offsetBy: 3)..<colon]) else { return nil }
            let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let host = rest.split(separator: " ").first.map { String($0.split(separator: ":").first ?? $0) } ?? "unknown"
            return Client(id: id, host: host, active: rest.contains("active: true"))
        }
    }

    /// Releases lan-mouse off the main thread, then warps on it.
    static func bringHome(completion: ((Result) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = release()
            DispatchQueue.main.async {
                let main = NSScreen.screens.first?.frame ?? .zero
                MouseFinder.shared.summon(to: NSPoint(x: main.midX, y: main.midY))
                var line = "Pointer home"
                if !result.deactivated.isEmpty { line += ", sharing off for \(result.deactivated.joined(separator: ", "))" }
                if result.stoppedDaemon { line += ", lan-mouse stopped (no answer)" }
                DiagnosticLog.shared.info(line)
                completion?(result)
            }
        }
    }

    private static func release() -> Result {
        guard let bin = binary() else { return Result(lanMouse: false) }
        var result = Result()
        guard let list = run(bin, ["cli", "list"]) else {
            // No answer: either nothing is running, or a hung daemon holds the cursor.
            result.stoppedDaemon = stopDaemon()
            return result
        }
        for client in parseClients(list) where client.active {
            if run(bin, ["cli", "deactivate", String(client.id)]) != nil {
                result.deactivated.append(client.host)
            }
        }
        return result
    }

    private static func stopDaemon() -> Bool {
        guard let found = ProcessQuery.shell(["/usr/bin/pgrep", "-x", "lan-mouse"]).nilIfEmpty else { return false }
        var stopped = false
        for pid in found.split(separator: "\n").compactMap({ pid_t($0) }) where kill(pid, SIGTERM) == 0 {
            stopped = true
        }
        return stopped
    }

    /// Runs a command, giving up after `timeout`. nil on failure or timeout.
    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        guard done.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
