import Foundation

class ProjectScanner: ObservableObject {
    static let shared = ProjectScanner()

    @Published var projects: [Project] = []

    private var scanRoot: String

    init(root: String? = nil) {
        self.scanRoot = root ?? Preferences.shared.scanRoot
    }

    func updateRoot(_ root: String) {
        self.scanRoot = root
    }

    func scan() {
        // Use find to locate all .lattice.json files — no manual directory walking
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        task.arguments = [scanRoot, "-name", ".lattice.json", "-maxdepth", "3", "-not", "-path", "*/.git/*", "-not", "-path", "*/node_modules/*"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let configPaths = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        var found: [Project] = []

        for configPath in configPaths.sorted() {
            let projectPath = (configPath as NSString).deletingLastPathComponent
            let name = (projectPath as NSString).lastPathComponent
            let (devCmd, pm) = detectDevCommand(at: projectPath)
            let paneInfo = readPaneInfo(at: configPath)

            var project = Project(
                id: projectPath,
                path: projectPath,
                name: name,
                devCommand: devCmd,
                packageManager: pm,
                hasConfig: true,
                paneCount: paneInfo.count,
                paneNames: paneInfo.names,
                paneSummary: paneInfo.summary,
                isRunning: false
            )
            project.isRunning = isSessionRunning(project.sessionName)
            found.append(project)
        }

        DispatchQueue.main.async { self.projects = found }
    }

    func refreshStatus() {
        for i in projects.indices {
            projects[i].isRunning = isSessionRunning(projects[i].sessionName)
        }
    }

    // MARK: - Detection

    private func detectDevCommand(at path: String) -> (String?, String?) {
        let pkgPath = (path as NSString).appendingPathComponent("package.json")
        guard let data = FileManager.default.contents(atPath: pkgPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String]
        else { return (nil, nil) }

        let has = { (f: String) in
            FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(f))
        }

        var pm = "npm"
        if has("pnpm-lock.yaml") { pm = "pnpm" }
        else if has("bun.lockb") || has("bun.lock") { pm = "bun" }
        else if has("yarn.lock") { pm = "yarn" }

        let run = pm == "npm" ? "npm run" : pm
        if scripts["dev"] != nil { return ("\(run) dev", pm) }
        if scripts["start"] != nil { return ("\(run) start", pm) }
        if scripts["serve"] != nil { return ("\(run) serve", pm) }
        if scripts["watch"] != nil { return ("\(run) watch", pm) }
        return (nil, pm)
    }

    private func readPaneInfo(at configPath: String) -> (count: Int, names: [String], summary: String) {
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let panes = json["panes"] as? [[String: Any]]
        else { return (2, ["claude", "server"], "") }

        let labels = panes.compactMap { pane -> String? in
            if let name = pane["name"] as? String { return name }
            if let cmd = pane["cmd"] as? String {
                let parts = cmd.split(separator: " ")
                return parts.first.map(String.init)
            }
            return nil
        }
        return (panes.count, labels, labels.joined(separator: " · "))
    }

    private static let tmuxPath = "/opt/homebrew/bin/tmux"

    private func isSessionRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: Self.tmuxPath)
        task.arguments = ["has-session", "-t", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
