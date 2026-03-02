import AppKit
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
    let display: Int?
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

// MARK: - Grid Presets & Named Layouts

struct GridPreset: Codable {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat

    var fractions: (CGFloat, CGFloat, CGFloat, CGFloat) { (x, y, w, h) }
}

struct LayoutWindowSpec: Codable {
    let app: String
    let tile: String        // TilePosition name or preset name
    let display: Int?       // spatial display number (1-based), nil = current
    let title: String?      // optional title match for disambiguation
}

struct LayoutConfig: Codable {
    let windows: [LayoutWindowSpec]
}

struct GridFile: Codable {
    let presets: [String: GridPreset]?
    let layouts: [String: LayoutConfig]?
}

// MARK: - Manager

class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var config: WorkspaceConfig?
    @Published var activeLayerIndex: Int = 0
    @Published var isSwitching: Bool = false
    @Published var gridPresets: [String: GridPreset] = [:]
    @Published var gridLayouts: [String: LayoutConfig] = [:]

    private let configPath: String
    private let gridConfigPath: String
    private let tmuxPath = "/opt/homebrew/bin/tmux"
    private let activeLayerKey = "lattices.activeLayerIndex"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = (home as NSString).appendingPathComponent(".lattices/workspace.json")
        self.gridConfigPath = (home as NSString).appendingPathComponent(".lattices/grid.json")
        self.activeLayerIndex = UserDefaults.standard.integer(forKey: activeLayerKey)
        loadConfig()
        loadGridConfig()
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
        loadGridConfig()
    }

    // MARK: - Grid Config I/O

    func loadGridConfig() {
        var presets: [String: GridPreset] = [:]
        var layouts: [String: LayoutConfig] = [:]

        // Load global ~/.lattices/grid.json
        if FileManager.default.fileExists(atPath: gridConfigPath),
           let data = FileManager.default.contents(atPath: gridConfigPath) {
            do {
                let gridFile = try JSONDecoder().decode(GridFile.self, from: data)
                if let p = gridFile.presets { presets.merge(p) { _, new in new } }
                if let l = gridFile.layouts { layouts.merge(l) { _, new in new } }
            } catch {
                DiagnosticLog.shared.error("WorkspaceManager: failed to decode grid.json — \(error.localizedDescription)")
            }
        }

        // Merge per-project .lattices.json "grid" section on top
        let projectGridPath = ".lattices.json"
        if FileManager.default.fileExists(atPath: projectGridPath),
           let data = FileManager.default.contents(atPath: projectGridPath) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let gridDict = json["grid"] {
                    let gridData = try JSONSerialization.data(withJSONObject: gridDict)
                    let gridFile = try JSONDecoder().decode(GridFile.self, from: gridData)
                    if let p = gridFile.presets { presets.merge(p) { _, new in new } }
                    if let l = gridFile.layouts { layouts.merge(l) { _, new in new } }
                }
            } catch {
                DiagnosticLog.shared.error("WorkspaceManager: failed to decode .lattices.json grid — \(error.localizedDescription)")
            }
        }

        self.gridPresets = presets
        self.gridLayouts = layouts
    }

    /// Resolve a tile string to fractions: check user presets first, then built-in TilePosition
    func resolveTileFractions(_ tile: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        if let preset = gridPresets[tile] {
            return preset.fractions
        }
        if let position = TilePosition(rawValue: tile) {
            return position.rect
        }
        return nil
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
                    terminal.launch(command: "/opt/homebrew/bin/lattices", in: tab.path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        terminal.nameTab(label)
                    }
                } else {
                    terminal.launchTab(command: "/opt/homebrew/bin/lattices", in: tab.path, tabName: label)
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

    // MARK: - Display Helper

    /// Resolve a display index to an NSScreen (falls back to first screen)
    private func screen(for displayIndex: Int?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let idx = displayIndex ?? 0
        return idx < screens.count ? screens[idx] : screens[0]
    }

    // MARK: - Window Lookup

    /// Find a tracked window for a session name (instant — uses DesktopModel cache)
    private func windowForSession(_ sessionName: String) -> WindowEntry? {
        DesktopModel.shared.windowForSession(sessionName)
    }

    /// Resolve a session name to a tile target: (wid, pid, frame).
    /// Returns nil if the window isn't tracked or has no tile position.
    private func batchTarget(session: String, position: TilePosition, screen: NSScreen) -> (wid: UInt32, pid: Int32, frame: CGRect)? {
        guard let entry = windowForSession(session) else { return nil }
        let frame = WindowTiler.tileFrame(for: position, on: screen)
        return (entry.wid, entry.pid, frame)
    }

    // MARK: - Tiling

    /// Re-tile the current layer without switching (for "tile all")
    func retileCurrentLayer() {
        tileLayer(index: activeLayerIndex, launch: false, force: true)
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

    // MARK: - Unified Layer Tiling

    /// Unified entry point for arranging a layer's windows.
    ///
    /// | launch | force | Behavior |
    /// |--------|-------|----------|
    /// | false  | false | Tile running projects only (focus) |
    /// | true   | false | Launch stopped + tile all, skip if same layer |
    /// | true   | true  | Re-launch current layer |
    /// | false  | true  | Re-tile current layer |
    func tileLayer(index: Int, launch: Bool = false, force: Bool = false) {
        guard let config, let layers = config.layers, index < layers.count else { return }
        if launch && !force && index == activeLayerIndex { return }

        let diag = DiagnosticLog.shared
        let label = launch ? "tileLayer(launch)" : "tileLayer(focus)"
        let overall = diag.startTimed("\(label) \(activeLayerIndex)→\(index)")

        isSwitching = true
        let terminal = Preferences.shared.terminal
        let scanner = ProjectScanner.shared
        let targetLayer = layers[index]

        // Phase 1: classify each project
        var batchMoves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        var fallbacks: [(session: String, position: TilePosition, screen: NSScreen)] = []
        var launchQueue: [(session: String, position: TilePosition?, screen: NSScreen, launchAction: () -> Void)] = []

        for lp in targetLayer.projects {
            guard let lpScreen = screen(for: lp.display) else { continue }

            if let groupId = lp.group, let grp = group(byId: groupId) {
                let firstTabSession = grp.tabs.first.map { Self.sessionName(for: $0.path) } ?? ""
                let position = lp.tile.flatMap { TilePosition(rawValue: $0) }
                let groupRunning = isGroupRunning(grp)

                if groupRunning, let pos = position,
                   let target = batchTarget(session: firstTabSession, position: pos, screen: lpScreen) {
                    batchMoves.append(target)
                } else if !groupRunning && launch {
                    diag.info("  launch group: \(grp.label)")
                    launchQueue.append((firstTabSession, position, lpScreen, { [weak self] in
                        self?.launchGroup(grp)
                    }))
                } else if groupRunning, let pos = position {
                    // Running but not in DesktopModel — fallback
                    fallbacks.append((firstTabSession, pos, lpScreen))
                } else if !groupRunning {
                    diag.info("  skip (not running): \(grp.label)")
                }
                continue
            }

            guard let path = lp.path else { continue }
            let sessionName = Self.sessionName(for: path)
            let project = scanner.projects.first(where: { $0.path == path })
            let position = lp.tile.flatMap { TilePosition(rawValue: $0) }
            let isRunning = project?.isRunning == true

            if isRunning {
                if let pos = position,
                   let target = batchTarget(session: sessionName, position: pos, screen: lpScreen) {
                    batchMoves.append(target)
                } else if let pos = position {
                    fallbacks.append((sessionName, pos, lpScreen))
                }
            } else if launch {
                if let project {
                    let t = diag.startTimed("launch: \(project.name)")
                    SessionManager.launch(project: project)
                    diag.finish(t)
                } else {
                    diag.info("  launch (direct): \(sessionName)")
                    terminal.launch(command: "/opt/homebrew/bin/lattices", in: path)
                }
                launchQueue.append((sessionName, position, lpScreen, {}))
            } else {
                diag.info("  skip (not running): \(sessionName)")
            }
        }

        // Phase 2: batch tile all tracked windows
        if !batchMoves.isEmpty {
            let t = diag.startTimed("batch tile \(batchMoves.count) windows")
            WindowTiler.batchMoveAndRaiseWindows(batchMoves)
            diag.finish(t)
        }

        // Phase 3: fallback for running-but-untracked windows
        for (i, fb) in fallbacks.enumerated() {
            let delay = Double(i) * 0.15 + 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                diag.info("  tile fallback: \(fb.session) → \(fb.position.rawValue)")
                WindowTiler.navigateToWindow(session: fb.session, terminal: terminal)
                WindowTiler.tile(session: fb.session, terminal: terminal, to: fb.position, on: fb.screen)
            }
        }

        // Phase 4: staggered tile for newly-launched windows
        for (i, item) in launchQueue.enumerated() {
            let delay = Double(i) * 0.15 + 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                item.launchAction()
                if let pos = item.position {
                    let t = diag.startTimed("tile launched: \(item.session) → \(pos.rawValue)")
                    WindowTiler.tile(session: item.session, terminal: terminal, to: pos, on: item.screen)
                    diag.finish(t)
                }
            }
        }

        activeLayerIndex = index
        UserDefaults.standard.set(index, forKey: activeLayerKey)

        let maxDelay = max(
            fallbacks.isEmpty ? 0.0 : Double(fallbacks.count) * 0.15 + 0.3,
            launchQueue.isEmpty ? 0.0 : Double(launchQueue.count) * 0.15 + 0.5
        )
        let cleanupDelay = max(0.2, maxDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) {
            scanner.refreshStatus()
            self.isSwitching = false
            diag.finish(overall)
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
