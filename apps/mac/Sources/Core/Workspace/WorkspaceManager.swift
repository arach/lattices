import AppKit
import CryptoKit
import Foundation

// MARK: - Data Model

struct TabGroupTab: Codable {
    let path: String?
    let label: String?
    let app: String?
    let title: String?
    let url: String?
    let launch: String?

    var displayLabel: String {
        if let label, !label.isEmpty { return label }
        if let path { return (path as NSString).lastPathComponent }
        return app ?? title ?? "Tab"
    }

    var isTerminal: Bool { path != nil }
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
    /// How to lay the layer's windows out when it's shown: "auto",
    /// "columns" or "master-stack" (`LayerLayout`). Nil leaves them where
    /// they are.
    var layout: String? = nil
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
    let id: String?
    let app: String
    let tile: String?       // TilePosition name, preset name, or omitted for engine layouts
    let display: Int?       // spatial display number (1-based), nil = current
    let title: String?      // optional title match for disambiguation
}

struct LayoutManagement: Codable, Equatable {
    let reconcile: String?
    let ambiguity: String?
    let fullscreen: String?
    let debounceMilliseconds: Int?
}

struct LayoutConfig: Codable {
    let engine: String?
    let gap: CGFloat?
    let masterRatio: CGFloat?
    let masterCount: Int?
    let management: LayoutManagement?
    let windows: [LayoutWindowSpec]

    var usesMasterStack: Bool {
        switch engine?.lowercased() {
        case "master-stack", "master":
            return true
        default:
            return false
        }
    }

    enum Placement {
        case named(String)
        case fractions(FractionalPlacement)
    }

    func placement(at index: Int) -> Placement? {
        guard windows.indices.contains(index) else { return nil }
        if let tile = windows[index].tile, !tile.isEmpty {
            return .named(tile)
        }
        guard usesMasterStack, let box = masterStackFractions(at: index) else { return nil }
        return .fractions(box)
    }

    func masterStackFractions(at index: Int) -> FractionalPlacement? {
        guard windows.indices.contains(index) else { return nil }
        let masters = max(masterCount ?? 1, 1)
        let ratio = min(max(masterRatio ?? 0.62, 0.05), 0.95)
        let stackWidth = 1 - ratio
        if index < masters {
            let height = 1 / CGFloat(masters)
            return FractionalPlacement(x: 0, y: CGFloat(index) * height, w: ratio, h: height)
        }
        let stackIndex = index - masters
        let stackCount = windows.count - masters
        guard stackCount > 0, stackWidth > 0 else { return nil }
        let height = 1 / CGFloat(stackCount)
        return FractionalPlacement(x: ratio, y: CGFloat(stackIndex) * height, w: stackWidth, h: height)
    }
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
    @Published private(set) var selectedGroupTabIndices: [String: Int] = [:]
    @Published private(set) var expandedGroupIDs: Set<String> = []

    private let configPath: String
    private let gridConfigPath: String
    private let snapZonesConfigPath: String
    private var gridConfigSourceToken = ""
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
        let token = gridConfigSourceFingerprint()
        if token == gridConfigSourceToken { return }
        gridConfigSourceToken = token

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
                DiagnosticLog.shared.error("WorkspaceManager: failed to decode grid.json — \(Self.describeDecodingError(error))")
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
                DiagnosticLog.shared.error("WorkspaceManager: failed to decode .lattices.json grid — \(Self.describeDecodingError(error))")
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

    func resolveLayoutFractions(_ layout: LayoutConfig, windowIndex: Int) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        switch layout.placement(at: windowIndex) {
        case .named(let tile):
            return resolveTileFractions(tile)
        case .fractions(let box):
            return box.fractions
        case nil:
            return nil
        }
    }

    private func gridConfigSourceFingerprint() -> String {
        func stamp(_ path: String) -> String {
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? -1
            return "\(path):\(mtime):\(size)"
        }
        let projectGrid = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent(".lattices.json")
        return [gridConfigPath, snapZonesConfigPath, projectGrid].map(stamp).joined(separator: "|")
    }

    static func describeDecodingError(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return error.localizedDescription
        }
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
            return keys.isEmpty ? "(root)" : keys.joined(separator: ".")
        }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .valueNotFound(let type, let context):
            return "missing \(type) at \(path(context))"
        case .typeMismatch(let type, let context):
            return "type mismatch (\(type)) at \(path(context)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "corrupted at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return decoding.localizedDescription
        }
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

    var activeLayerGroups: [TabGroup] {
        guard let layer = activeLayer else { return [] }
        return layer.projects.compactMap { project in
            project.group.flatMap(group(byId:))
        }
    }

    func selectedTabIndex(in group: TabGroup) -> Int {
        min(selectedGroupTabIndices[group.id] ?? 0, max(0, group.tabs.count - 1))
    }

    func isGroupExpanded(_ group: TabGroup) -> Bool {
        expandedGroupIDs.contains(group.id)
    }

    func isTabRunning(_ tab: TabGroupTab) -> Bool {
        if let path = tab.path {
            let name = Self.sessionName(for: path)
            return shell([tmuxPath, "has-session", "-t", name]) == 0
        }
        guard let app = tab.app else { return false }
        return DesktopModel.shared.windowForApp(app: app, title: tab.title) != nil
            || Self.findAppWindow(app: app, title: tab.title) != nil
    }

    func isGroupRunning(_ group: TabGroup) -> Bool {
        group.tabs.contains(where: isTabRunning)
    }

    /// Count how many tabs in the group have running sessions
    func runningTabCount(_ group: TabGroup) -> Int {
        group.tabs.filter(isTabRunning).count
    }

    /// Launch a mixed group. Project tabs open in the terminal; app/URL tabs
    /// open as native application windows.
    func launchGroup(_ group: TabGroup) {
        let terminal = Preferences.shared.terminal
        let latticesCommand = LatticesRuntime.cliShellCommand
        for (i, tab) in group.tabs.enumerated() {
            guard !isTabRunning(tab) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                if let path = tab.path {
                    let earlierTerminalTabs = group.tabs[..<i].contains(where: \.isTerminal)
                    if !earlierTerminalTabs {
                        terminal.launch(command: "\(latticesCommand) start", in: path)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            terminal.nameTab(tab.displayLabel)
                        }
                    } else {
                        terminal.launchTab(
                            command: "\(latticesCommand) start",
                            in: path,
                            tabName: tab.displayLabel
                        )
                    }
                } else {
                    self.launch(tab)
                }
            }
        }
    }

    /// Kill all individual tab sessions for a group
    func killGroup(_ group: TabGroup) {
        for tab in group.tabs {
            guard let path = tab.path else { continue }
            let name = Self.sessionName(for: path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: tmuxPath)
            task.arguments = ["kill-session", "-t", name]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    /// Focus a specific terminal or application window in a mixed tab group.
    /// When the group is collapsed, switching tabs keeps every member in the
    /// group's configured layer slot.
    func focusTab(group: TabGroup, tabIndex: Int) {
        guard tabIndex >= 0, tabIndex < group.tabs.count else { return }
        selectedGroupTabIndices[group.id] = tabIndex
        let tab = group.tabs[tabIndex]
        if !isGroupExpanded(group) {
            collapseGroup(group)
        }

        if let entry = window(for: tab) {
            _ = WindowTiler.focusWindow(wid: entry.wid, pid: entry.pid)
            WindowTiler.highlightWindowById(wid: entry.wid)
        } else if let path = tab.path {
            Preferences.shared.terminal.focusOrAttach(session: Self.sessionName(for: path))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.collapseGroup(group)
            }
        } else {
            launch(tab)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.collapseGroup(group)
            }
        }
    }

    /// Toggle between a single-slot cross-app tab stack and a full smart grid.
    func toggleGroupLayout(_ group: TabGroup) {
        if isGroupExpanded(group) {
            collapseGroup(group)
        } else {
            expandGroupToGrid(group)
        }
    }

    func expandGroupToGrid(_ group: TabGroup) {
        DesktopModel.shared.poll()
        let windows = orderedWindows(for: group)
        guard !windows.isEmpty else { return }
        expandedGroupIDs.insert(group.id)
        WindowTiler.batchRaiseAndDistribute(
            windows: windows.map { (wid: $0.wid, pid: $0.pid) },
            reactivateLattices: false
        )
        DiagnosticLog.shared.info("WorkspaceManager: expanded mixed group '\(group.label)' to grid")
    }

    func collapseGroup(_ group: TabGroup) {
        DesktopModel.shared.poll()
        let windows = orderedWindows(for: group)
        guard !windows.isEmpty,
              let (placement, targetScreen) = groupPlacement(group) else { return }

        let frame = WindowTiler.tileFrame(for: placement, on: targetScreen)
        WindowTiler.batchMoveAndRaiseWindows(
            windows.map { (wid: $0.wid, pid: $0.pid, frame: frame) }
        )
        expandedGroupIDs.remove(group.id)

        let selected = selectedTabIndex(in: group)
        if selected < group.tabs.count, let entry = window(for: group.tabs[selected]) {
            _ = WindowTiler.focusWindow(wid: entry.wid, pid: entry.pid)
        }
        DiagnosticLog.shared.info("WorkspaceManager: collapsed mixed group '\(group.label)' to \(placement.wireValue)")
    }

    private func window(for tab: TabGroupTab, currentSpaceOnly: Bool = false) -> WindowEntry? {
        if let path = tab.path {
            return windowForSession(Self.sessionName(for: path), currentSpaceOnly: currentSpaceOnly)
        }
        guard let app = tab.app else { return nil }
        return DesktopModel.shared.windowForApp(app: app, title: tab.title, currentSpaceOnly: currentSpaceOnly)
    }

    private func orderedWindows(for group: TabGroup, currentSpaceOnly: Bool = false) -> [WindowEntry] {
        let selected = selectedTabIndex(in: group)
        var result: [WindowEntry] = []
        for (index, tab) in group.tabs.enumerated() where index != selected {
            if let entry = window(for: tab, currentSpaceOnly: currentSpaceOnly), !result.contains(where: { $0.wid == entry.wid }) {
                result.append(entry)
            }
        }
        if selected < group.tabs.count,
           let entry = window(for: group.tabs[selected], currentSpaceOnly: currentSpaceOnly),
           !result.contains(where: { $0.wid == entry.wid }) {
            result.append(entry)
        }
        return result
    }

    private func groupPlacement(_ group: TabGroup) -> (PlacementSpec, NSScreen)? {
        let project = activeLayer?.projects.first(where: { $0.group == group.id })
            ?? config?.layers?.lazy.compactMap { layer in
                layer.projects.first(where: { $0.group == group.id })
            }.first
        let placement = project?.tile.flatMap(resolvePlacement) ?? .tile(.topLeft)
        guard let targetScreen = screen(for: project?.display) else { return nil }
        return (placement, targetScreen)
    }

    private func launch(_ tab: TabGroupTab) {
        if let urlString = tab.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else if let appName = tab.launch ?? tab.app {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", appName]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
        }
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
    private func windowForSession(_ sessionName: String, currentSpaceOnly: Bool = false) -> WindowEntry? {
        DesktopModel.shared.windowForSession(sessionName, currentSpaceOnly: currentSpaceOnly)
    }

    /// Resolve a session name to a tile target: (wid, pid, frame).
    /// Returns nil if the window isn't tracked on a desktop that's showing.
    private func batchTarget(session: String, position: PlacementSpec, screen: NSScreen) -> (wid: UInt32, pid: Int32, frame: CGRect)? {
        guard let entry = windowForSession(session, currentSpaceOnly: true) else { return nil }
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

    // MARK: - Layer Stage

    /// Every window a layer's entries match, on any desktop: the layer's own
    /// windows, as opposed to whatever else was showing when it was left.
    func memberWindowIDs(of layer: Layer, in windows: [WindowEntry]) -> Set<UInt32> {
        Set(memberWindows(of: layer, in: windows).map(\.entry.wid))
    }

    /// The layer's windows in entry order, front to back within an entry,
    /// each under the first entry that matches it. `placed` marks the ones
    /// whose entry sets its own `tile` or `display`, which a layout leaves be.
    func memberWindows(of layer: Layer, in windows: [WindowEntry]) -> [(entry: WindowEntry, placed: Bool)] {
        let windows = windows.sorted { $0.zIndex < $1.zIndex }
        var members: [(entry: WindowEntry, placed: Bool)] = []
        var seen = Set<UInt32>()
        func add(_ entry: WindowEntry, placed: Bool) {
            if seen.insert(entry.wid).inserted { members.append((entry, placed)) }
        }
        func matchApp(_ app: String, title: String?, placed: Bool) {
            for entry in windows where entry.app.localizedCaseInsensitiveContains(app)
                && (title.map { entry.title.localizedCaseInsensitiveContains($0) } ?? true) {
                add(entry, placed: placed)
            }
        }
        func matchSession(_ session: String, placed: Bool) {
            for entry in windows where SessionWindowLocator.matches(
                session: session, title: entry.title, extractedSessionName: entry.latticesSession
            ) {
                add(entry, placed: placed)
            }
        }
        for lp in layer.projects {
            let placed = lp.tile != nil || lp.display != nil
            if let groupId = lp.group, let grp = group(byId: groupId) {
                for tab in grp.tabs {
                    if let path = tab.path {
                        matchSession(Self.sessionName(for: path), placed: placed)
                    } else if let app = tab.app {
                        matchApp(app, title: tab.title, placed: placed)
                    }
                }
            } else if let app = lp.app {
                matchApp(app, title: lp.title, placed: placed)
            } else if let path = lp.path {
                matchSession(Self.sessionName(for: path), placed: placed)
                for cw in projectWindows(at: path) {
                    if let app = cw.app {
                        matchApp(app, title: cw.title, placed: cw.tile != nil || (cw.display ?? lp.display) != nil)
                    }
                }
            }
        }
        return members
    }

    /// Put away what the incoming layer doesn't use and bring back what it
    /// had showing (see `LayerStage`). Leaves `DesktopModel` freshly polled.
    private func stageSwitch(to index: Int, in layers: [Layer]) {
        let windows = DesktopModel.shared.refreshNow()
        var members: [String: Set<UInt32>] = [:]
        for layer in layers {
            members[layer.id, default: []].formUnion(memberWindowIDs(of: layer, in: windows))
        }
        let outgoing = layers.indices.contains(activeLayerIndex) ? layers[activeLayerIndex] : nil
        LayerStage.shared.stage(outgoing: outgoing, incoming: layers[index], members: members, windows: windows)
    }

    // MARK: - Layer Focus (no launching)

    /// Switch to a layer: put away what it doesn't use, then bring its
    /// windows forward — no launching. This is the default hotkey action. A
    /// layer with a `layout` lays its windows out (`arrangeLayer`); one
    /// without raises them in place. Choosing the active layer again does
    /// the same without staging, which gathers its windows back up. Windows
    /// on a desktop that isn't showing are left there; raising one would
    /// switch Spaces.
    func focusLayer(index: Int) {
        guard let config, let layers = config.layers, index < layers.count else { return }
        let switching = index != activeLayerIndex

        let diag = DiagnosticLog.shared
        let t = diag.startTimed("focusLayer \(activeLayerIndex)→\(index)")

        if switching {
            stageSwitch(to: index, in: layers)
        } else {
            DesktopModel.shared.refreshNow()
        }

        let targetLayer = layers[index]
        if !arrangeLayer(targetLayer, windows: DesktopModel.shared.allWindows()) {
            raiseWindows(of: targetLayer)
        }

        activeLayerIndex = index
        UserDefaults.standard.set(index, forKey: activeLayerKey)

        LayerBezel.shared.show(label: targetLayer.label, index: index, total: layers.count)
        if switching {
            HandsOffSession.shared.playCachedCue("Switched.")
        }

        diag.finish(t)
    }

    /// Raises the window each of a layer's entries matches on the showing
    /// desktop, where it is.
    private func raiseWindows(of targetLayer: Layer) {
        var windowsToRaise: [(wid: UInt32, pid: Int32)] = []

        for lp in targetLayer.projects {
            if let groupId = lp.group, let grp = group(byId: groupId) {
                // Raise all tab windows in the group
                for tab in grp.tabs {
                    if let entry = window(for: tab, currentSpaceOnly: true) {
                        windowsToRaise.append((entry.wid, entry.pid))
                    }
                }
                continue
            }

            if let appName = lp.app {
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: lp.title, currentSpaceOnly: true) {
                    windowsToRaise.append((entry.wid, entry.pid))
                }
                continue
            }

            guard let path = lp.path else { continue }
            let sessionName = Self.sessionName(for: path)
            if let entry = windowForSession(sessionName, currentSpaceOnly: true) {
                windowsToRaise.append((entry.wid, entry.pid))
            }

            // Also raise companion windows
            let companions = projectWindows(at: path)
            for cw in companions {
                guard let appName = cw.app else { continue }
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: cw.title, currentSpaceOnly: true) {
                    windowsToRaise.append((entry.wid, entry.pid))
                }
            }
        }

        if !windowsToRaise.isEmpty {
            WindowTiler.raiseWindowsAndReactivate(windows: windowsToRaise)
        }
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

        // Put away what the layer doesn't use, from a fresh inventory. A
        // re-tile of the active layer leaves the rest of the screen alone.
        if index != activeLayerIndex {
            stageSwitch(to: index, in: layers)
        } else {
            DesktopModel.shared.refreshNow()
        }

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
                let position = lp.tile.flatMap { resolvePlacement($0) }
                let groupWindows = orderedWindows(for: grp, currentSpaceOnly: true)
                let groupRunning = isGroupRunning(grp)

                if !groupWindows.isEmpty, let pos = position {
                    let frame = WindowTiler.tileFrame(for: pos, on: lpScreen)
                    batchMoves.append(contentsOf: groupWindows.map {
                        (wid: $0.wid, pid: $0.pid, frame: frame)
                    })
                    expandedGroupIDs.remove(grp.id)
                    if launch, runningTabCount(grp) < grp.tabs.count {
                        launchGroup(grp)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.collapseGroup(grp)
                        }
                    }
                } else if !groupRunning && launch {
                    diag.info("  launch group: \(grp.label)")
                    launchQueue.append(("group:\(grp.id)", nil, lpScreen, { [weak self] in
                        guard let self else { return }
                        self.launchGroup(grp)
                        if position != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.collapseGroup(grp)
                            }
                        }
                    }))
                } else if groupWindows.isEmpty {
                    diag.info("  skip (not running): \(grp.label)")
                }
                continue
            }

            // App-based window matching
            if let appName = lp.app {
                let position = lp.tile.flatMap { resolvePlacement($0) }
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: lp.title, currentSpaceOnly: true) {
                    if let pos = position {
                        let frame = WindowTiler.tileFrame(for: pos, on: lpScreen)
                        batchMoves.append((entry.wid, entry.pid, frame))
                    }
                } else if let found = Self.findAppWindow(app: appName, title: lp.title) {
                    // Open on a desktop that isn't showing: leave it there rather
                    // than switch Spaces, and don't launch a second one.
                    diag.info("  skip (on another desktop): \(appName) wid=\(found.wid)")
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
                    if foundWindow != nil {
                        // On a desktop that isn't showing: leave it there.
                        debugLines.append("    → skip (on another desktop)")
                    } else {
                        fallbacks.append((sessionName, pos, lpScreen))
                        debugLines.append("    → fallback \(pos.wireValue)")
                    }
                }
            } else if launch {
                if let project {
                    let t = diag.startTimed("launch: \(project.name)")
                    SessionManager.launch(project: project)
                    diag.finish(t)
                } else {
                    diag.info("  launch (direct): \(sessionName)")
                    terminal.launch(command: "\(LatticesRuntime.cliShellCommand) start", in: path)
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
                if let entry = DesktopModel.shared.windowForApp(app: appName, title: cw.title, currentSpaceOnly: true) {
                    if let pos = cwPosition {
                        let frame = WindowTiler.tileFrame(for: pos, on: cwScreen)
                        batchMoves.append((entry.wid, entry.pid, frame))
                    }
                } else if DesktopModel.shared.windowForApp(app: appName, title: cw.title) != nil {
                    diag.info("  skip companion (on another desktop): \(appName)")
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

        // Lay out the windows whose entries don't place them.
        arrangeLayer(targetLayer, windows: DesktopModel.shared.allWindows())

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
        LayerBezel.shared.show(label: targetLayer.label, index: index, total: layers.count)

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
