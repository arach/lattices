import Foundation

public enum TmuxQuery {
    public static let resolvedPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
            "/opt/local/bin/tmux",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let result = ProcessQuery.shell(["/usr/bin/which", "tmux"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty && FileManager.default.isExecutableFile(atPath: result) {
            return result
        }
        return nil
    }()

    public static var isAvailable: Bool {
        resolvedPath != nil
    }

    public static func listSessions() -> [TmuxSession] {
        guard let tmux = resolvedPath else { return [] }

        let sessionsRaw = ProcessQuery.shell([
            tmux, "list-sessions", "-F",
            "#{session_name}\t#{session_windows}\t#{session_created}\t#{session_attached}"
        ])
        guard !sessionsRaw.isEmpty else { return [] }

        let panesRaw = ProcessQuery.shell([
            tmux, "list-panes", "-a", "-F",
            "#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_title}\t#{pane_current_command}\t#{pane_pid}\t#{pane_active}"
        ])

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

        var sessions: [TmuxSession] = []
        for line in sessionsRaw.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 4 else { continue }

            let name = cols[0]
            sessions.append(TmuxSession(
                name: name,
                windowCount: Int(cols[1]) ?? 1,
                attached: cols[3] != "0",
                panes: panesBySession[name] ?? []
            ))
        }

        return sessions.sorted { $0.name < $1.name }
    }

    public static func capturePane(paneId: String, lineLimit: Int = 120) -> String? {
        guard let tmux = resolvedPath else { return nil }
        let clamped = max(1, min(lineLimit, 2_000))
        let raw = ProcessQuery.shell([
            tmux, "capture-pane", "-p", "-S", "-\(clamped)", "-t", paneId
        ])
        return raw.isEmpty ? nil : raw
    }
}
