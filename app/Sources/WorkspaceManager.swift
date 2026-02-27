import CryptoKit
import Foundation

// MARK: - Data Model

struct TabGroupTab: Codable {
    let path: String
    let label: String?
}

struct TabGroup: Codable, Identifiable {
    let id: String
    let label: String
    let tabs: [TabGroupTab]
}

struct LayerProject: Codable {
    let path: String?
    let group: String?
    let tile: String?
}

struct Layer: Codable, Identifiable {
    let id: String
    let label: String
    let projects: [LayerProject]
}

struct WorkspaceConfig: Codable {
    let name: String
    let groups: [TabGroup]?
    let layers: [Layer]?
}

// MARK: - Manager

class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var config: WorkspaceConfig?
    @Published var activeLayerIndex: Int = 0
    @Published var isSwitching: Bool = false

    private let configPath: String
    private let tmuxPath = "/opt/homebrew/bin/tmux"
    private let activeLayerKey = "lattice.activeLayerIndex"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = (home as NSString).appendingPathComponent(".lattice/workspace.json")
        self.activeLayerIndex = UserDefaults.standard.integer(forKey: activeLayerKey)
        loadConfig()
    }

    var activeLayer: Layer? {
        guard let config, let layers = config.layers, activeLayerIndex < layers.count else { return nil }
        return layers[activeLayerIndex]
    }

    // MARK: - Config I/O

    func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath),
              let data = FileManager.default.contents(atPath: configPath) else {
            config = nil
            return
        }
        do {
            config = try JSONDecoder().decode(WorkspaceConfig.self, from: data)
            // Clamp saved index
            if let config, let layers = config.layers, activeLayerIndex >= layers.count {
                activeLayerIndex = 0
            }
        } catch {
            DiagnosticLog.shared.error("WorkspaceManager: failed to decode workspace.json — \(error.localizedDescription)")
            config = nil
        }
    }

    func reloadConfig() {
        loadConfig()
    }

    // MARK: - Tab Groups

    func group(byId id: String) -> TabGroup? {
        config?.groups?.first(where: { $0.id == id })
    }

    func isGroupRunning(_ group: TabGroup) -> Bool {
        group.tabs.contains { tab in
            let name = Self.sessionName(for: tab.path)
            return shell([tmuxPath, "has-session", "-t", name]) == 0
        }
    }

    /// Count how many tabs in the group have running sessions
    func runningTabCount(_ group: TabGroup) -> Int {
        group.tabs.filter { tab in
            let name = Self.sessionName(for: tab.path)
            return shell([tmuxPath, "has-session", "-t", name]) == 0
        }.count
    }

    /// Launch a group by opening each tab as a separate iTerm/Terminal tab
    func launchGroup(_ group: TabGroup) {
        let terminal = Preferences.shared.terminal
        for (i, tab) in group.tabs.enumerated() {
            let label = tab.label ?? (tab.path as NSString).lastPathComponent
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                if i == 0 {
                    terminal.launch(command: "/opt/homebrew/bin/lattice", in: tab.path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        terminal.nameTab(label)
                    }
                } else {
                    terminal.launchTab(command: "/opt/homebrew/bin/lattice", in: tab.path, tabName: label)
                }
            }
        }
    }

    /// Kill all individual tab sessions for a group
    func killGroup(_ group: TabGroup) {
        for tab in group.tabs {
            let name = Self.sessionName(for: tab.path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: tmuxPath)
            task.arguments = ["kill-session", "-t", name]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    /// Focus a specific tab's session in the terminal
    func focusTab(group: TabGroup, tabIndex: Int) {
        guard tabIndex >= 0, tabIndex < group.tabs.count else { return }
        let tab = group.tabs[tabIndex]
        let sessionName = Self.sessionName(for: tab.path)
        let terminal = Preferences.shared.terminal
        terminal.focusOrAttach(session: sessionName)
    }

    /// Run a command and return exit code
    private func shell(_ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: args[0])
        task.arguments = Array(args.dropFirst())
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    // MARK: - Tiling

    /// Re-tile the current layer without switching (for "tile all")
    func retileCurrentLayer() {
        guard let config, let layers = config.layers, activeLayerIndex < layers.count else { return }

        let diag = DiagnosticLog.shared
        diag.info("WorkspaceManager: re-tiling current layer \(activeLayerIndex)")

        isSwitching = true
        let terminal = Preferences.shared.terminal
        let targetLayer = layers[activeLayerIndex]

        for (i, lp) in targetLayer.projects.enumerated() {
            if let groupId = lp.group, let group = group(byId: groupId) {
                let firstTabSession = group.tabs.first.map { Self.sessionName(for: $0.path) } ?? ""
                if let tileStr = lp.tile, let position = TilePosition(rawValue: tileStr) {
                    let delay = Double(i) * 0.3 + 0.1
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        diag.info("  tile group: \(firstTabSession) -> \(position.rawValue)")
                        WindowTiler.tile(session: firstTabSession, terminal: terminal, to: position)
                    }
                }
                continue
            }

            guard let path = lp.path else { continue }
            let sessionName = Self.sessionName(for: path)

            if let tileStr = lp.tile, let position = TilePosition(rawValue: tileStr) {
                let delay = Double(i) * 0.3 + 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    diag.info("  tile: \(sessionName) -> \(position.rawValue)")
                    WindowTiler.tile(session: sessionName, terminal: terminal, to: position)
                }
            }
        }

        let projectCount = targetLayer.projects.count
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(projectCount) * 0.3 + 0.5) {
            self.isSwitching = false
        }
    }

    // MARK: - Layer Focus (no launch)

    /// Focus/tile running projects in a layer without launching stopped ones
    func focusLayer(index: Int) {
        guard let config, let layers = config.layers, index < layers.count else { return }

        let diag = DiagnosticLog.shared
        diag.info("WorkspaceManager: focusing layer \(index)")

        isSwitching = true
        let terminal = Preferences.shared.terminal
        let scanner = ProjectScanner.shared
        let targetLayer = layers[index]

        for (i, lp) in targetLayer.projects.enumerated() {
            if let groupId = lp.group, let group = group(byId: groupId) {
                let firstTabSession = group.tabs.first.map { Self.sessionName(for: $0.path) } ?? ""

                if isGroupRunning(group) {
                    diag.info("  focus group: \(group.label)")
                    WindowTiler.navigateToWindow(session: firstTabSession, terminal: terminal)
                    if let tileStr = lp.tile, let position = TilePosition(rawValue: tileStr) {
                        let delay = Double(i) * 0.3 + 0.2
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            diag.info("  tile group: \(firstTabSession) -> \(position.rawValue)")
                            WindowTiler.tile(session: firstTabSession, terminal: terminal, to: position)
                        }
                    }
                } else {
                    diag.info("  skip (not running): \(group.label)")
                }
                continue
            }

            guard let path = lp.path else { continue }
            let sessionName = Self.sessionName(for: path)
            let project = scanner.projects.first(where: { $0.path == path })

            if let project, project.isRunning {
                diag.info("  focus: \(project.name)")
                WindowTiler.navigateToWindow(session: sessionName, terminal: terminal)
                if let tileStr = lp.tile, let position = TilePosition(rawValue: tileStr) {
                    let delay = Double(i) * 0.3 + 0.2
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        diag.info("  tile: \(sessionName) -> \(position.rawValue)")
                        WindowTiler.tile(session: sessionName, terminal: terminal, to: position)
                    }
                }
            } else {
                diag.info("  skip (not running): \(sessionName)")
            }
        }

        activeLayerIndex = index
        UserDefaults.standard.set(index, forKey: activeLayerKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            scanner.refreshStatus()
            self.isSwitching = false
        }
    }

    /// Count running projects+groups in a layer
    func layerRunningCount(index: Int) -> (running: Int, total: Int) {
        guard let config, let layers = config.layers, index < layers.count else { return (0, 0) }
        let layer = layers[index]
        let scanner = ProjectScanner.shared
        var running = 0
        let total = layer.projects.count

        for lp in layer.projects {
            if let groupId = lp.group, let group = group(byId: groupId) {
                if isGroupRunning(group) { running += 1 }
            } else if let path = lp.path {
                let project = scanner.projects.first(where: { $0.path == path })
                if project?.isRunning == true { running += 1 }
            }
        }
        return (running, total)
    }

    // MARK: - Layer Switching (full launch)

    func switchToLayer(index: Int, force: Bool = false) {
        guard let config, let layers = config.layers, index < layers.count,
              force || index != activeLayerIndex else { return }

        let diag = DiagnosticLog.shared
        diag.info("WorkspaceManager: switching from layer \(activeLayerIndex) to \(index)")

        isSwitching = true
        let terminal = Preferences.shared.terminal
        let scanner = ProjectScanner.shared
        let targetLayer = layers[index]

        for (i, lp) in targetLayer.projects.enumerated() {
            // Handle group references
            if let groupId = lp.group, let group = group(byId: groupId) {
                // Use the first tab's session for focus/tiling (the iTerm window)
                let firstTabSession = group.tabs.first.map { Self.sessionName(for: $0.path) } ?? ""

                if isGroupRunning(group) {
                    diag.info("  focus group: \(group.label)")
                    WindowTiler.navigateToWindow(session: firstTabSession, terminal: terminal)
                } else {
                    diag.info("  launch group: \(group.label)")
                    launchGroup(group)
                }

                if let tileStr = lp.tile, let position = TilePosition(rawValue: tileStr) {
                    let delay = Double(i) * 0.3 + (isGroupRunning(group) ? 0.2 : 0.8)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        diag.info("  tile group: \(firstTabSession) -> \(position.rawValue)")
                        WindowTiler.tile(session: firstTabSession, terminal: terminal, to: position)
                    }
                }
                continue
            }

            // Handle regular project references
            guard let path = lp.path else { continue }
            let sessionName = Self.sessionName(for: path)
            let project = scanner.projects.first(where: { $0.path == path })

            if let project, project.isRunning {
                diag.info("  focus: \(project.name)")
                WindowTiler.navigateToWindow(session: sessionName, terminal: terminal)
            } else if let project {
                diag.info("  launch: \(project.name)")
                SessionManager.launch(project: project)
            } else {
                diag.info("  launch (direct): \(sessionName)")
                terminal.launch(command: "/opt/homebrew/bin/lattice", in: path)
            }

            if let tileStr = lp.tile, let position = TilePosition(rawValue: tileStr) {
                let delay = Double(i) * 0.3 + (project?.isRunning == true ? 0.2 : 0.8)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    diag.info("  tile: \(sessionName) -> \(position.rawValue)")
                    WindowTiler.tile(session: sessionName, terminal: terminal, to: position)
                }
            }
        }

        activeLayerIndex = index
        UserDefaults.standard.set(index, forKey: activeLayerKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            scanner.refreshStatus()
            self.isSwitching = false
        }
    }

    // MARK: - Session Name Helper

    /// Replicates Project.sessionName logic from a bare path
    static func sessionName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let base = name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let hash = SHA256.hash(data: Data(path.utf8))
        let short = hash.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(base)-\(short)"
    }
}
