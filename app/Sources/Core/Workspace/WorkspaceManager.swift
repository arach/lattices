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
    let app: String?       // match by owner app name (e.g. "Google Chrome", "Xcode")
    let title: String?     // substring match on window title (case-insensitive)
    let url: String?       // URL to open if no matching window found
    let launch: String?    // app name to launch if not running (via `open -a`)
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
    let snapZones: SnapZonesConfig?
}

enum SnapModifierKey: String, Codable, Equatable, CaseIterable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .command:
            return "Command"
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .shift:
            return "Shift"
        }
    }

    var shortLabel: String {
        switch self {
        case .command:
            return "Cmd"
        case .option:
            return "Opt"
        case .control:
            return "Ctrl"
        case .shift:
            return "Shift"
        }
    }

    var eventFlags: NSEvent.ModifierFlags {
        switch self {
        case .command:
            return .command
        case .option:
            return .option
        case .control:
            return .control
        case .shift:
            return .shift
        }
    }

    var cgEventFlags: CGEventFlags {
        switch self {
        case .command:
            return .maskCommand
        case .option:
            return .maskAlternate
        case .control:
            return .maskControl
        case .shift:
            return .maskShift
        }
    }

}

enum SnapZoneTriggerSpec: Codable, Equatable {
    case named(String)
    case fractions(FractionalPlacement)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let named = try? container.decode(String.self) {
            self = .named(named)
            return
        }

        let preset = try container.decode(GridPreset.self)
        guard let placement = FractionalPlacement(x: preset.x, y: preset.y, w: preset.w, h: preset.h) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "snap zone trigger fractions must stay within 0...1"
            )
        }
        self = .fractions(placement)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .named(let name):
            try container.encode(name)
        case .fractions(let placement):
            try container.encode(GridPreset(x: placement.x, y: placement.y, w: placement.w, h: placement.h))
        }
    }
}

enum SnapZonePlacementSpec: Codable, Equatable {
    case named(String)
    case fractions(FractionalPlacement)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let named = try? container.decode(String.self) {
            self = .named(named)
            return
        }

        let preset = try container.decode(GridPreset.self)
        guard let placement = FractionalPlacement(x: preset.x, y: preset.y, w: preset.w, h: preset.h) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "snap zone placement fractions must stay within 0...1"
            )
        }
        self = .fractions(placement)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .named(let name):
            try container.encode(name)
        case .fractions(let placement):
            try container.encode(GridPreset(x: placement.x, y: placement.y, w: placement.w, h: placement.h))
        }
    }
}

struct SnapZoneDefinition: Codable, Equatable, Identifiable {
    let rawID: String?
    let label: String?
    let placement: SnapZonePlacementSpec
    let trigger: SnapZoneTriggerSpec
    let priority: Int?

    enum CodingKeys: String, CodingKey {
        case rawID = "id"
        case label
        case placement
        case trigger
        case priority
    }

    var id: String {
        let trimmed = rawID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallbackID : trimmed
    }

    private var fallbackID: String {
        switch placement {
        case .named(let name):
            return name
        case .fractions(let fractions):
            return "fractions-\(fractions.x)-\(fractions.y)-\(fractions.w)-\(fractions.h)"
        }
    }
}

struct SnapZonesConfig: Codable, Equatable {
    let enabled: Bool?
    let modifier: SnapModifierKey?
    let zoneOpacity: Double?
    let highlightOpacity: Double?
    let previewOpacity: Double?
    let cornerRadius: CGFloat?
    let rules: [SnapZoneDefinition]?

    enum CodingKeys: String, CodingKey {
        case enabled
        case modifier
        case zoneOpacity
        case highlightOpacity
        case previewOpacity
        case cornerRadius
        case rules
        case zones
    }

    init(
        enabled: Bool?,
        modifier: SnapModifierKey?,
        zoneOpacity: Double?,
        highlightOpacity: Double?,
        previewOpacity: Double?,
        cornerRadius: CGFloat?,
        rules: [SnapZoneDefinition]?
    ) {
        self.enabled = enabled
        self.modifier = modifier
        self.zoneOpacity = zoneOpacity
        self.highlightOpacity = highlightOpacity
        self.previewOpacity = previewOpacity
        self.cornerRadius = cornerRadius
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        modifier = try container.decodeIfPresent(SnapModifierKey.self, forKey: .modifier)
        zoneOpacity = try container.decodeIfPresent(Double.self, forKey: .zoneOpacity)
        highlightOpacity = try container.decodeIfPresent(Double.self, forKey: .highlightOpacity)
        previewOpacity = try container.decodeIfPresent(Double.self, forKey: .previewOpacity)
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
        let decodedRules = try container.decodeIfPresent([SnapZoneDefinition].self, forKey: .rules)
        let decodedZones = try container.decodeIfPresent([SnapZoneDefinition].self, forKey: .zones)
        rules = decodedRules ?? decodedZones
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(modifier, forKey: .modifier)
        try container.encodeIfPresent(zoneOpacity, forKey: .zoneOpacity)
        try container.encodeIfPresent(highlightOpacity, forKey: .highlightOpacity)
        try container.encodeIfPresent(previewOpacity, forKey: .previewOpacity)
        try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(rules, forKey: .rules)
    }

    static let defaults = SnapZonesConfig(
        enabled: true,
        modifier: .command,
        zoneOpacity: 0.10,
        highlightOpacity: 0.22,
        previewOpacity: 0.18,
        cornerRadius: 18,
        rules: [
            SnapZoneDefinition(
                rawID: "top-left",
                label: "Top Left",
                placement: .named("top-left"),
                trigger: .fractions(FractionalPlacement(x: 0.00, y: 0.00, w: 0.24, h: 0.18)!),
                priority: 40
            ),
            SnapZoneDefinition(
                rawID: "maximize",
                label: "Maximize",
                placement: .named("maximize"),
                trigger: .fractions(FractionalPlacement(x: 0.24, y: 0.00, w: 0.52, h: 0.12)!),
                priority: 20
            ),
            SnapZoneDefinition(
                rawID: "top-right",
                label: "Top Right",
                placement: .named("top-right"),
                trigger: .fractions(FractionalPlacement(x: 0.76, y: 0.00, w: 0.24, h: 0.18)!),
                priority: 40
            ),
            SnapZoneDefinition(
                rawID: "left",
                label: "Left",
                placement: .named("left"),
                trigger: .fractions(FractionalPlacement(x: 0.00, y: 0.18, w: 0.12, h: 0.64)!),
                priority: 10
            ),
            SnapZoneDefinition(
                rawID: "right",
                label: "Right",
                placement: .named("right"),
                trigger: .fractions(FractionalPlacement(x: 0.88, y: 0.18, w: 0.12, h: 0.64)!),
                priority: 10
            ),
            SnapZoneDefinition(
                rawID: "bottom-left",
                label: "Bottom Left",
                placement: .named("bottom-left"),
                trigger: .fractions(FractionalPlacement(x: 0.00, y: 0.82, w: 0.24, h: 0.18)!),
                priority: 40
            ),
            SnapZoneDefinition(
                rawID: "bottom-right",
                label: "Bottom Right",
                placement: .named("bottom-right"),
                trigger: .fractions(FractionalPlacement(x: 0.76, y: 0.82, w: 0.24, h: 0.18)!),
                priority: 40
            ),
        ]
    )

    func merged(over defaults: SnapZonesConfig = .defaults) -> SnapZonesConfig {
        SnapZonesConfig(
            enabled: enabled ?? defaults.enabled,
            modifier: modifier ?? defaults.modifier,
            zoneOpacity: zoneOpacity ?? defaults.zoneOpacity,
            highlightOpacity: highlightOpacity ?? defaults.highlightOpacity,
            previewOpacity: previewOpacity ?? defaults.previewOpacity,
            cornerRadius: cornerRadius ?? defaults.cornerRadius,
            rules: rules ?? defaults.rules
        )
    }
}

// MARK: - Manager

class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var config: WorkspaceConfig?
    @Published var activeLayerIndex: Int = 0
    @Published var isSwitching: Bool = false
    @Published var gridPresets: [String: GridPreset] = [:]
    @Published var gridLayouts: [String: LayoutConfig] = [:]
    @Published var snapZonesConfig: SnapZonesConfig = .defaults

    private let configPath: String
    private let gridConfigPath: String
    private let snapZonesConfigPath: String
    private var tmuxPath: String { TmuxQuery.resolvedPath ?? "/opt/homebrew/bin/tmux" }
    private let activeLayerKey = "lattices.activeLayerIndex"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = (home as NSString).appendingPathComponent(".lattices/workspace.json")
        self.gridConfigPath = (home as NSString).appendingPathComponent(".lattices/grid.json")
        self.snapZonesConfigPath = (home as NSString).appendingPathComponent(".lattices/snap-zones.json")
        self.activeLayerIndex = UserDefaults.standard.integer(forKey: activeLayerKey)
        loadConfig()
        loadGridConfig()
    }

    var activeLayer: Layer? {
        guard let config, let layers = config.layers, activeLayerIndex < layers.count else { return nil }
        return layers[activeLayerIndex]
    }

    /// Look up a layer index by id or label (case-insensitive)
    func layerIndex(named name: String) -> Int? {
        guard let layers = config?.layers else { return nil }
        // Try exact id match first
        if let i = layers.firstIndex(where: { $0.id == name }) { return i }
        // Then case-insensitive id
        if let i = layers.firstIndex(where: { $0.id.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return i }
        // Then case-insensitive label
        if let i = layers.firstIndex(where: { $0.label.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return i }
        return nil
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
        var snapZones = SnapZonesConfig.defaults

        // Load global ~/.lattices/grid.json
        if FileManager.default.fileExists(atPath: gridConfigPath),
           let data = FileManager.default.contents(atPath: gridConfigPath) {
            do {
                let gridFile = try JSONDecoder().decode(GridFile.self, from: data)
                if let p = gridFile.presets { presets.merge(p) { _, new in new } }
                if let l = gridFile.layouts { layouts.merge(l) { _, new in new } }
                if let snap = gridFile.snapZones {
                    snapZones = snap.merged(over: snapZones)
                }
            } catch {
                DiagnosticLog.shared.error("WorkspaceManager: failed to decode grid.json — \(error.localizedDescription)")
            }
        }

        if FileManager.default.fileExists(atPath: snapZonesConfigPath),
           let data = FileManager.default.contents(atPath: snapZonesConfigPath) {
            do {
                let config = try JSONDecoder().decode(SnapZonesConfig.self, from: data)
                snapZones = config.merged(over: snapZones)
            } catch {
                DiagnosticLog.shared.error("WorkspaceManager: failed to decode snap-zones.json — \(error.localizedDescription)")
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
                    if let snap = gridFile.snapZones {
                        snapZones = snap.merged(over: snapZones)
                    }
                }
            } catch {
                DiagnosticLog.shared.error("WorkspaceManager: failed to decode .lattices.json grid — \(error.localizedDescription)")
            }
        }

        self.gridPresets = presets
        self.gridLayouts = layouts
        self.snapZonesConfig = snapZones
    }

    func updateSnapModifier(_ modifier: SnapModifierKey) {
        let updated = SnapZonesConfig(
            enabled: snapZonesConfig.enabled,
            modifier: modifier,
            zoneOpacity: snapZonesConfig.zoneOpacity,
            highlightOpacity: snapZonesConfig.highlightOpacity,
            previewOpacity: snapZonesConfig.previewOpacity,
            cornerRadius: snapZonesConfig.cornerRadius,
            rules: snapZonesConfig.rules
        )

        do {
            let url = URL(fileURLWithPath: snapZonesConfigPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updated)
            try data.write(to: url, options: .atomic)

            loadGridConfig()
            DiagnosticLog.shared.info("WorkspaceManager: updated snap modifier to \(modifier.rawValue)")
        } catch {
            DiagnosticLog.shared.error("WorkspaceManager: failed to write snap-zones.json — \(error.localizedDescription)")
        }
    }

    /// Resolve a tile string to fractions: check user presets first, then built-in TilePosition
    func resolveTileFractions(_ tile: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        resolvePlacement(tile)?.fractions
    }

    func resolvePlacement(_ tile: String) -> PlacementSpec? {
        if let preset = gridPresets[tile],
           let placement = FractionalPlacement(x: preset.x, y: preset.y, w: preset.w, h: preset.h) {
            return .fractions(placement)
        }
        return PlacementSpec(string: tile)
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
    private func batchTarget(session: String, position: PlacementSpec, screen: NSScreen) -> (wid: UInt32, pid: Int32, frame: CGRect)? {
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
            } else if let appName = lp.app {
                if DesktopModel.shared.windowForApp(app: appName, title: lp.title) != nil { running += 1 }
            } else if let path = lp.path {
                let project = scanner.projects.first(where: { $0.path == path })
                if project?.isRunning == true { running += 1 }
            }
        }
        return (running, total)
    }

    // MARK: - Layer Focus (raise only)

    /// Switch to a layer by raising all its windows in place — no launching, no tiling, no moving.
    /// This is the default hotkey action: just bring the layer's windows to the front.
    func focusLayer(index: Int) {
        guard let config, let layers = config.layers, index < layers.count else { return }
        if index == activeLayerIndex { return }

        let diag = DiagnosticLog.shared
        let t = diag.startTimed("focusLayer \(activeLayerIndex)→\(index)")

        DesktopModel.shared.poll()

        let targetLayer = layers[index]
        var windowsToRaise: [(wid: UInt32, pid: Int32)] = []

        for lp in targetLayer.projects {
            if let groupId = lp.group, let grp = group(byId: groupId) {
                // Raise all tab windows in the group
                for tab in grp.tabs {
                    let sessionName = Self.sessionName(for: tab.path)
                    if let entry = windowForSession(sessionName) {
                        windowsToRaise.append((entry.wid, entry.pid))
                    }
                }
                continue
            }

            if let appName = lp.app {
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: lp.title) {
                    windowsToRaise.append((entry.wid, entry.pid))
                }
                continue
            }

            guard let path = lp.path else { continue }
            let sessionName = Self.sessionName(for: path)
            if let entry = windowForSession(sessionName) {
                windowsToRaise.append((entry.wid, entry.pid))
            }

            // Also raise companion windows
            let companions = projectWindows(at: path)
            for cw in companions {
                guard let appName = cw.app else { continue }
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: cw.title) {
                    windowsToRaise.append((entry.wid, entry.pid))
                }
            }
        }

        if !windowsToRaise.isEmpty {
            WindowTiler.raiseWindowsAndReactivate(windows: windowsToRaise)
        }

        activeLayerIndex = index
        UserDefaults.standard.set(index, forKey: activeLayerKey)

        let allLabels = layers.map(\.label)
        LayerBezel.shared.show(label: targetLayer.label, index: index, total: layers.count, allLabels: allLabels)
        HandsOffSession.shared.playCachedCue("Switched.")

        diag.finish(t)
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

        // Fresh poll so we see windows on all Spaces before matching
        DesktopModel.shared.poll()

        // Tile debug log (written to ~/.lattices/tile-debug.log)
        let debugPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".lattices/tile-debug.log")
        var debugLines: [String] = ["tileLayer index=\(index) launch=\(launch) force=\(force) layer=\(targetLayer.id)"]

        // Phase 1: classify each project
        var batchMoves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        var fallbacks: [(session: String, position: PlacementSpec, screen: NSScreen)] = []
        var launchQueue: [(session: String, position: PlacementSpec?, screen: NSScreen, launchAction: () -> Void)] = []

        // Log screen info
        for (i, s) in NSScreen.screens.enumerated() {
            debugLines.append("screen[\(i)]: frame=\(s.frame) visible=\(s.visibleFrame)")
        }

        for lp in targetLayer.projects {
            guard let lpScreen = screen(for: lp.display) else { continue }

            if let groupId = lp.group, let grp = group(byId: groupId) {
                let firstTabSession = grp.tabs.first.map { Self.sessionName(for: $0.path) } ?? ""
                let position = lp.tile.flatMap { resolvePlacement($0) }
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

            // App-based window matching
            if let appName = lp.app {
                let position = lp.tile.flatMap { resolvePlacement($0) }
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: lp.title) {
                    if let pos = position {
                        let frame = WindowTiler.tileFrame(for: pos, on: lpScreen)
                        batchMoves.append((entry.wid, entry.pid, frame))
                    }
                } else if let found = Self.findAppWindow(app: appName, title: lp.title) {
                    // Window exists but wasn't in DesktopModel (e.g. different Space) — tile it
                    diag.info("  found app via CGWindowList fallback: \(appName) wid=\(found.wid)")
                    if let pos = position {
                        let frame = WindowTiler.tileFrame(for: pos, on: lpScreen)
                        batchMoves.append((found.wid, found.pid, frame))
                    }
                } else if launch {
                    diag.info("  launch app: \(appName)")
                    let capturedLp = lp
                    let capturedScreen = lpScreen
                    launchQueue.append(("app:\(appName)", nil, capturedScreen, { [weak self] in
                        self?.launchAppEntry(capturedLp)
                    }))
                    // Queue a delayed tile after launch
                    if let pos = position {
                        let capturedTitle = lp.title
                        let delay = Double(launchQueue.count) * 0.5 + 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            DesktopModel.shared.poll()
                            if let entry = DesktopModel.shared.windowForApp(app: appName, title: capturedTitle) {
                                let frame = WindowTiler.tileFrame(for: pos, on: capturedScreen)
                                WindowTiler.batchMoveAndRaiseWindows([(entry.wid, entry.pid, frame)])
                            }
                        }
                    }
                } else {
                    diag.info("  skip (not found): \(appName)")
                }
                continue
            }

            guard let path = lp.path else { continue }
            let sessionName = Self.sessionName(for: path)
            let project = scanner.projects.first(where: { $0.path == path })
            let position = lp.tile.flatMap { resolvePlacement($0) }
            // Check scanner first, fall back to direct tmux check for projects without .lattices.json
            let isRunning = project?.isRunning == true || shell([tmuxPath, "has-session", "-t", sessionName]) == 0

            if isRunning {
                let foundWindow = windowForSession(sessionName)
                let msg = "  \(sessionName): running=\(isRunning) window=\(foundWindow?.wid ?? 0) tile=\(position?.wireValue ?? "nil") desktopCount=\(DesktopModel.shared.windows.count)"
                diag.info(msg)
                debugLines.append(msg)
                if let pos = position,
                   let target = batchTarget(session: sessionName, position: pos, screen: lpScreen) {
                    batchMoves.append(target)
                    debugLines.append("    → batch move wid=\(target.wid) frame=\(target.frame)")
                } else if let pos = position {
                    fallbacks.append((sessionName, pos, lpScreen))
                    debugLines.append("    → fallback \(pos.wireValue)")
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

            // Compose companion windows from project's .lattices.json "windows" array
            let companions = projectWindows(at: path)
            for cw in companions {
                guard let appName = cw.app else { continue }
                let cwScreen = screen(for: cw.display ?? lp.display) ?? lpScreen
                let cwPosition = cw.tile.flatMap { resolvePlacement($0) }
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: cw.title) {
                    if let pos = cwPosition {
                        let frame = WindowTiler.tileFrame(for: pos, on: cwScreen)
                        batchMoves.append((entry.wid, entry.pid, frame))
                    }
                } else if launch {
                    diag.info("  launch companion: \(appName)")
                    let capturedCw = cw
                    launchQueue.append(("app:\(appName)", nil, cwScreen, { [weak self] in
                        self?.launchAppEntry(capturedCw)
                    }))
                    if let pos = cwPosition {
                        let capturedTitle = cw.title
                        let capturedScreen = cwScreen
                        let delay = Double(launchQueue.count) * 0.5 + 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            DesktopModel.shared.poll()
                            if let entry = DesktopModel.shared.windowForApp(app: appName, title: capturedTitle) {
                                let frame = WindowTiler.tileFrame(for: pos, on: capturedScreen)
                                WindowTiler.batchMoveAndRaiseWindows([(entry.wid, entry.pid, frame)])
                            }
                        }
                    }
                }
            }
        }

        // Write debug log
        debugLines.append("batchMoves=\(batchMoves.count) fallbacks=\(fallbacks.count) launchQueue=\(launchQueue.count)")
        try? debugLines.joined(separator: "\n").write(toFile: debugPath, atomically: true, encoding: .utf8)

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
                diag.info("  tile fallback: \(fb.session) → \(fb.position.wireValue)")
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
                    let t = diag.startTimed("tile launched: \(item.session) → \(pos.wireValue)")
                    WindowTiler.tile(session: item.session, terminal: terminal, to: pos, on: item.screen)
                    diag.finish(t)
                }
            }
        }

        activeLayerIndex = index
        UserDefaults.standard.set(index, forKey: activeLayerKey)

        // Show layer bezel
        let totalLayers = layers.count
        let allLabels = layers.map(\.label)
        LayerBezel.shared.show(label: targetLayer.label, index: index, total: totalLayers, allLabels: allLabels)

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

    // MARK: - Per-Project Window Config

    /// Read companion window entries from a project's .lattices.json "windows" array
    func projectWindows(at projectPath: String) -> [LayerProject] {
        let configPath = (projectPath as NSString).appendingPathComponent(".lattices.json")
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let windowsArray = json["windows"] else { return [] }
        do {
            let windowsData = try JSONSerialization.data(withJSONObject: windowsArray)
            return try JSONDecoder().decode([LayerProject].self, from: windowsData)
        } catch {
            DiagnosticLog.shared.error("WorkspaceManager: failed to decode windows in \(configPath) — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - App Launch Helper

    /// Launch an app-based layer project (open URL or launch app by name)
    private func launchAppEntry(_ lp: LayerProject) {
        if let urlStr = lp.url, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        } else if let appName = lp.launch ?? lp.app {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", appName]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
        }
    }

    // MARK: - App Window Fallback (CGWindowList .optionAll)

    /// Find an app window across ALL Spaces via CGWindowList (bypasses DesktopModel cache)
    static func findAppWindow(app: String, title: String?) -> (wid: UInt32, pid: Int32)? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in list {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerName.localizedCaseInsensitiveContains(app),
                  let wid = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width >= 50, rect.height >= 50 else { continue }

            if let title {
                let windowTitle = info[kCGWindowName as String] as? String ?? ""
                guard windowTitle.localizedCaseInsensitiveContains(title) else { continue }
            }

            return (wid, pid)
        }
        return nil
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
