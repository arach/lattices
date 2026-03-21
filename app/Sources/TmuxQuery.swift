import Foundation

// MARK: - Data Models

struct TmuxSession: Identifiable {
    let id: String          // session name
    let name: String
    let windowCount: Int
    let attached: Bool
    let panes: [TmuxPane]
}

struct TmuxPane: Identifiable {
    let id: String              // "%0", "%1", etc.
    let windowIndex: Int
    let windowName: String
    let title: String           // pane_title
    let currentCommand: String  // e.g. "node", "vim", "zsh"
    let pid: Int
    let isActive: Bool
}

// MARK: - Query

enum TmuxQuery {
    /// Resolved path to the tmux binary, or nil if not found
    static let resolvedPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/tmux",   // Apple Silicon Homebrew
            "/usr/local/bin/tmux",      // Intel Homebrew
            "/usr/bin/tmux",            // unlikely on macOS, but check
            "/opt/local/bin/tmux",      // MacPorts
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fall back to PATH lookup via /usr/bin/which
        let result = ProcessQuery.shell(["/usr/bin/which", "tmux"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty && FileManager.default.isExecutableFile(atPath: result) {
            return result
        }
        return nil
    }()

    /// Whether tmux is available on this system
    static var isAvailable: Bool { resolvedPath != nil }

    /// List all tmux sessions with their panes in exactly 2 shell calls
    static func listSessions() -> [TmuxSession] {
        guard let tmux = resolvedPath else { return [] }

        // Query 1: all sessions
        let sessionsRaw = shell([
            tmux, "list-sessions", "-F",
            "#{session_name}\t#{session_windows}\t#{session_created}\t#{session_attached}"
        ])
        guard !sessionsRaw.isEmpty else { return [] }

        // Query 2: all panes across all sessions
        let panesRaw = shell([
            tmux, "list-panes", "-a", "-F",
            "#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_title}\t#{pane_current_command}\t#{pane_pid}\t#{pane_active}"
        ])

        // Parse panes, grouped by session name
        var panesBySession: [String: [TmuxPane]] = [:]
        for line in panesRaw.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 8 else { continue }
            let pane = TmuxPane(
                id: cols[3],
                windowIndex: Int(cols[1]) ?? 0,
                windowName: cols[2],
                title: cols[4],
                currentCommand: cols[5],
                pid: Int(cols[6]) ?? 0,
                isActive: cols[7] == "1"
            )
            panesBySession[cols[0], default: []].append(pane)
        }

        // Parse sessions
        var sessions: [TmuxSession] = []
        for line in sessionsRaw.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 4 else { continue }
            let name = cols[0]
            sessions.append(TmuxSession(
                id: name,
                name: name,
                windowCount: Int(cols[1]) ?? 1,
                attached: cols[3] != "0",
                panes: panesBySession[name] ?? []
            ))
        }

        return sessions
    }

    private static func shell(_ args: [String]) -> String {
        ProcessQuery.shell(args)
    }
}
