import AppKit

enum SessionManager {
    private static let latticesPath = "/opt/homebrew/bin/lattices"
    private static var tmuxPath: String { TmuxQuery.resolvedPath ?? "/opt/homebrew/bin/tmux" }

    /// Launch or reattach — if session is running, find and focus the existing window
    static func launch(project: Project) {
        let terminal = Preferences.shared.terminal
        if project.isRunning {
            if let window = DesktopModel.shared.windowForSession(project.sessionName) {
                DesktopModel.shared.markInteraction(wid: window.wid)
            }
            terminal.focusOrAttach(session: project.sessionName)
        } else {
            terminal.launch(command: "\(latticesPath) start", in: project.path)
        }
    }

    /// Detach all clients from a tmux session (keeps it running)
    static func detach(project: Project) {
        detachByName(project.sessionName)
    }

    /// Detach all clients by session name string (for layer switching without a Project object)
    static func detachByName(_ sessionName: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tmuxPath)
        task.arguments = ["detach-client", "-s", sessionName]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// Kill a tmux session
    static func kill(project: Project) {
        killByName(project.sessionName)
    }

    /// Kill a tmux session by name string (for orphan sessions without a Project object)
    static func killByName(_ sessionName: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tmuxPath)
        task.arguments = ["kill-session", "-t", sessionName]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// Reconcile session state to match declared config (recreate missing panes)
    static func sync(project: Project) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: latticesPath)
        task.arguments = ["sync"]
        task.currentDirectoryURL = URL(fileURLWithPath: project.path)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// Restart a specific pane's process (kill + re-run declared command)
    static func restart(project: Project, paneName: String? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: latticesPath)
        task.arguments = paneName != nil ? ["restart", paneName!] : ["restart"]
        task.currentDirectoryURL = URL(fileURLWithPath: project.path)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
