import AppKit
import Foundation

public enum TerminalQuery {
    public static func normalizeTTY(_ raw: String) -> String {
        if raw.hasPrefix("/dev/") {
            return String(raw.dropFirst(5))
        }
        return raw
    }

    public static func queryAll(apps: [TerminalApp] = TerminalApp.allCases) -> [TerminalTab] {
        var results: [TerminalTab] = []
        for app in apps where isAppRunning(app.rawValue) {
            switch app {
            case .iterm2:
                results.append(contentsOf: queryITerm2())
            case .terminal:
                results.append(contentsOf: queryTerminalApp())
            case .ghostty:
                break
            }
        }
        return results
    }

    public static func queryITerm2() -> [TerminalTab] {
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
            guard cols.count >= 5,
                  let windowIndex = Int(cols[0]),
                  let tabIndex = Int(cols[1])
            else { continue }

            let tty = normalizeTTY(String(cols[2]))
            guard tty.hasPrefix("ttys") else { continue }

            tabs.append(TerminalTab(
                app: .iterm2,
                windowIndex: windowIndex,
                tabIndex: tabIndex,
                tty: tty,
                isActiveTab: false,
                title: String(cols[3]),
                sessionId: String(cols[4])
            ))
        }
        return tabs
    }

    public static func queryTerminalApp() -> [TerminalTab] {
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
            guard cols.count >= 5,
                  let windowIndex = Int(cols[0]),
                  let tabIndex = Int(cols[1])
            else { continue }

            let tty = normalizeTTY(String(cols[2]))
            guard tty.hasPrefix("ttys") else { continue }

            tabs.append(TerminalTab(
                app: .terminal,
                windowIndex: windowIndex,
                tabIndex: tabIndex,
                tty: tty,
                isActiveTab: String(cols[4]).lowercased() == "true",
                title: String(cols[3]),
                sessionId: nil
            ))
        }
        return tabs
    }

    static func isAppRunning(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == name }
    }

    private static func osascript(_ source: String) -> String {
        ProcessQuery.shell(["/usr/bin/osascript", "-e", source])
    }
}
