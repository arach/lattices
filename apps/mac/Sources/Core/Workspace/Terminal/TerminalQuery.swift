import AppKit

// MARK: - Data Model

struct TerminalTab {
    let app: Terminal
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
        if isAppRunning("iTerm2") {
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
                        set output to output & winIdx & "\t" & tabIdx & "\t" & (tty of s) & "\t" & (name of s) & "\t" & (unique ID of s) & linefeed
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
            let cols = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard cols.count >= 5 else { continue }

            guard let winIdx = Int(cols[0]),
                  let tabIdx = Int(cols[1]) else { continue }

            let tty = normalizeTTY(String(cols[2]))
            guard tty.hasPrefix("ttys") else { continue }

            let title = String(cols[3])
            let sessionId = String(cols[4])

            tabs.append(TerminalTab(
                app: .iterm2,
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
                    set output to output & winIdx & "\t" & tabIdx & "\t" & (tty of t) & "\t" & (custom title of t) & "\t" & isSel & linefeed
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
            let cols = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard cols.count >= 5 else { continue }

            guard let winIdx = Int(cols[0]),
                  let tabIdx = Int(cols[1]) else { continue }

            let tty = normalizeTTY(String(cols[2]))
            guard tty.hasPrefix("ttys") else { continue }

            let title = String(cols[3])
            let isActive = String(cols[4]).lowercased() == "true"

            tabs.append(TerminalTab(
                app: .terminal,
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

    /// Run an AppleScript and capture stdout.
    /// Uses ProcessQuery.shell to avoid Process.waitUntilExit() deadlocks on macOS 26.
    private static func osascript(_ source: String) -> String {
        ProcessQuery.shell(["/usr/bin/osascript", "-e", source])
    }
}
