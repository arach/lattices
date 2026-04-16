import AppKit

enum CliActionLauncher {
    private static var defaultDirectory: String {
        let root = Preferences.shared.scanRoot
        return root.isEmpty ? NSHomeDirectory() : root
    }

    private static func chooseProjectDirectory(message: String, prompt: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: defaultDirectory)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func initializeProjectInTerminal() {
        guard let directory = chooseProjectDirectory(
            message: "Choose a project folder to initialize with Lattices.",
            prompt: "Initialize"
        ) else { return }

        Preferences.shared.terminal.launch(
            command: "lattices init && lattices",
            in: directory
        )
    }

    static func launchProjectInTerminal() {
        guard let directory = chooseProjectDirectory(
            message: "Choose a project folder to launch with Lattices.",
            prompt: "Launch"
        ) else { return }

        Preferences.shared.terminal.launch(
            command: "lattices",
            in: directory
        )
    }

    static func installTmuxInTerminal() {
        Preferences.shared.terminal.launch(
            command: "brew install tmux",
            in: defaultDirectory
        )
    }
}
