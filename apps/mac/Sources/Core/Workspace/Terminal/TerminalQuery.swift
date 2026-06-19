import AppKit
import Darwin

// MARK: - Data Model

struct TerminalTab {
    let app: Terminal
    let windowId: UInt32?     // CGWindowID when exposed by the terminal app
    let windowIndex: Int
    let tabIndex: Int
    let tty: String           // normalized: "ttys003"
    let isActiveTab: Bool
    let title: String
    let sessionId: String?    // iTerm2 unique ID only
}

// MARK: - Query

enum TerminalQuery {

    /// Normalize TTY strings: strip "/dev/" prefix if present.
    /// iTerm2 returns "/dev/ttys003", Terminal.app and `ps` return "ttys003".
    static func normalizeTTY(_ raw: String) -> String {
        if raw.hasPrefix("/dev/") {
            return String(raw.dropFirst(5))
        }
        return raw
    }

    /// Query all running terminal emulators for tab info.
    /// Only queries apps that are currently running (won't auto-launch).
    static func queryAll() -> [TerminalTab] {
        var results: [TerminalTab] = []
        if isAppRunning("iTerm2") || isAppRunning("iTerm 2") {
            results.append(contentsOf: queryITerm2())
        }
        if isAppRunning("Terminal") {
            results.append(contentsOf: queryTerminalApp())
        }
        // Future: queryWarp(), queryGhostty(), etc.
        return results
    }

    // MARK: - iTerm2

    static func queryITerm2() -> [TerminalTab] {
        let script = """
        tell application "iTerm2"
            set output to ""
            set winIdx to 0
            repeat with w in windows
                set tabIdx to 0
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set output to output & (id of w) & "\t" & winIdx & "\t" & tabIdx & "\t" & (tty of s) & "\t" & (name of s) & "\t" & (unique ID of s) & linefeed
                    end repeat
                    set tabIdx to tabIdx + 1
                end repeat
                set winIdx to winIdx + 1
            end repeat
            return output
        end tell
        """

        let raw = osascript(script)
        guard !raw.isEmpty else { return [] }

        var tabs: [TerminalTab] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false)
            guard cols.count >= 6 else { continue }

            let windowId = UInt32(cols[0])
            guard let winIdx = Int(cols[1]),
                  let tabIdx = Int(cols[2]) else { continue }

            let tty = normalizeTTY(String(cols[3]))
            guard tty.hasPrefix("ttys") else { continue }

            let title = String(cols[4])
            let sessionId = String(cols[5])

            tabs.append(TerminalTab(
                app: .iterm2,
                windowId: windowId,
                windowIndex: winIdx,
                tabIndex: tabIdx,
                tty: tty,
                isActiveTab: false, // iTerm2 doesn't expose this easily in a single call
                title: title,
                sessionId: sessionId
            ))
        }
        return tabs
    }

    // MARK: - Terminal.app

    static func queryTerminalApp() -> [TerminalTab] {
        let script = """
        tell application "Terminal"
            set output to ""
            set winIdx to 0
            repeat with w in windows
                set selTab to selected tab of w
                set tabIdx to 0
                repeat with t in tabs of w
                    set isSel to (t = selTab)
                    set output to output & (id of w) & "\t" & winIdx & "\t" & tabIdx & "\t" & (tty of t) & "\t" & (custom title of t) & "\t" & isSel & linefeed
                    set tabIdx to tabIdx + 1
                end repeat
                set winIdx to winIdx + 1
            end repeat
            return output
        end tell
        """

        let raw = osascript(script)
        guard !raw.isEmpty else { return [] }

        var tabs: [TerminalTab] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false)
            guard cols.count >= 6 else { continue }

            let windowId = UInt32(cols[0])
            guard let winIdx = Int(cols[1]),
                  let tabIdx = Int(cols[2]) else { continue }

            let tty = normalizeTTY(String(cols[3]))
            guard tty.hasPrefix("ttys") else { continue }

            let title = String(cols[4])
            let isActive = String(cols[5]).lowercased() == "true"

            tabs.append(TerminalTab(
                app: .terminal,
                windowId: windowId,
                windowIndex: winIdx,
                tabIndex: tabIdx,
                tty: tty,
                isActiveTab: isActive,
                title: title,
                sessionId: nil
            ))
        }
        return tabs
    }

    // MARK: - Helpers

    /// Check if a named app is already running (prevents AppleScript from auto-launching it).
    private static func isAppRunning(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == name }
    }

    /// Run an AppleScript and capture stdout with a short bound. These queries
    /// are explicit deep refreshes only; the normal terminal model uses
    /// Lattices' window/process/tmux state and does not script terminal apps.
    private static func osascript(_ source: String) -> String {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return ""
        }

        let deadline = Date().addingTimeInterval(5.0)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if task.isRunning {
            task.terminate()
            Darwin.kill(task.processIdentifier, SIGKILL)
            return ""
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
