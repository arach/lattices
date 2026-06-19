import AppKit

// MARK: - StudioLayerStore

/// The persistent home of rule-backed layers. Reads/writes
/// `~/.lattices/layers.json`. On first run (no layers.json) it seeds from the
/// existing `clusters.json` so the Studio view is populated immediately —
/// clusters and layers are the same idea, just authored differently.
final class StudioLayerStore: ObservableObject {
    static let shared = StudioLayerStore()

    @Published private(set) var layers: [StudioLayer] = []

    private let fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".lattices/layers.json")

    var configFilePath: String { fileURL.path }

    private init() {
        load()
    }

    // MARK: - Resolution

    /// Live windows that currently match the layer's rule, frontmost first.
    func resolve(_ layer: StudioLayer, in desktop: DesktopModel = .shared) -> [WindowEntry] {
        desktop.allWindows().filter { layer.contains($0) }
    }

    /// How many live windows the rule matches right now.
    func matchCount(_ layer: StudioLayer, in desktop: DesktopModel = .shared) -> Int {
        desktop.windows.values.reduce(0) { $0 + (layer.contains($1) ? 1 : 0) }
    }

    // MARK: - Assistant Context

    func assistantContextPayload(in desktop: DesktopModel = .shared) -> [String: Any] {
        [
            "kind": "lattices.studio-layers.v1",
            "configFile": configFilePath,
            "semantics": Self.ruleSemantics,
            "count": layers.count,
            "layers": layers.map { layer in
                layerContextPayload(layer, matches: resolve(layer, in: desktop), includeSemantics: false)
            },
        ]
    }

    func layerContextPayload(_ layer: StudioLayer, matches providedMatches: [WindowEntry]? = nil, includeSemantics: Bool = true) -> [String: Any] {
        let matches = providedMatches ?? resolve(layer)
        var payload: [String: Any] = [
            "kind": "lattices.studio-layer.v1",
            "configFile": configFilePath,
            "layer": layerPayload(layer),
            "liveMatchCount": matches.count,
            "liveMatches": matches.map(windowPayload),
        ]
        if includeSemantics {
            payload["semantics"] = Self.ruleSemantics
        }
        return payload
    }

    func layerContextJSON(_ layer: StudioLayer, matches: [WindowEntry]? = nil) -> String {
        Self.prettyJSONString(layerContextPayload(layer, matches: matches))
    }

    private static let ruleSemantics: [String: String] = [
        "membership": "Layer membership is computed from live desktop windows; window ids are not persisted as members.",
        "layerMatch": "A window belongs to a layer when it matches any clause in layer.match.",
        "clauseMatch": "Within one clause, every present positive field must match and no clause in not may match.",
        "authoringDefault": "The Hyperspace rule editor writes simple clauses: appEquals plus optional titleContains (Text) or titleRegex (Regex).",
        "app": "Legacy case-insensitive substring match against the owning app name.",
        "appEquals": "Case-insensitive exact match against the owning app name. This is the App field in Hyperspace.",
        "appRegex": "Case-insensitive regular expression match against the owning app name.",
        "titleContains": "Case-insensitive plain-text substring match against the window name/title. This is the Name Text mode in Hyperspace.",
        "titleEquals": "Case-insensitive exact match against the window name/title.",
        "titleRegex": "Case-insensitive regular expression match against the window name/title. This is the Name Regex mode in Hyperspace.",
        "session": "Case-insensitive exact match against the parsed lattices tmux session tag.",
        "sessionContains": "Case-insensitive substring match against the parsed lattices tmux session tag.",
        "isOnScreen": "Boolean match against whether the window is visible on the current Space.",
        "spaceId": "Matches when the window belongs to the given macOS Space id.",
        "not": "Array of exclusion clauses; if any exclusion clause matches, this clause fails.",
        "emptyClause": "A clause with no positive fields matches no windows, even when not is present.",
    ]

    private func layerPayload(_ layer: StudioLayer) -> [String: Any] {
        [
            "id": layer.id,
            "name": layer.name,
            "match": layer.match.map(clausePayload),
            "summary": layer.summary,
        ]
    }

    private func clausePayload(_ clause: StudioLayerClause) -> [String: Any] {
        var payload: [String: Any] = [
            "app": jsonNullable(clause.app),
            "titleContains": jsonNullable(clause.titleContains),
            "summary": clause.summary,
        ]
        addOptional(clause.appEquals, key: "appEquals", to: &payload)
        addOptional(clause.appRegex, key: "appRegex", to: &payload)
        addOptional(clause.titleEquals, key: "titleEquals", to: &payload)
        addOptional(clause.titleRegex, key: "titleRegex", to: &payload)
        addOptional(clause.session, key: "session", to: &payload)
        addOptional(clause.sessionContains, key: "sessionContains", to: &payload)
        if let isOnScreen = clause.isOnScreen {
            payload["isOnScreen"] = isOnScreen
        }
        if let spaceId = clause.spaceId {
            payload["spaceId"] = spaceId
        }
        if let not = clause.not, !not.isEmpty {
            payload["not"] = not.map(clausePayload)
        }
        return payload
    }

    private func windowPayload(_ window: WindowEntry) -> [String: Any] {
        [
            "wid": Int(window.wid),
            "pid": Int(window.pid),
            "app": window.app,
            "title": window.title,
            "isOnScreen": window.isOnScreen,
            "spaceIds": window.spaceIds,
            "latticesSession": jsonNullable(window.latticesSession),
            "zIndex": window.zIndex,
            "frame": [
                "x": window.frame.x,
                "y": window.frame.y,
                "w": window.frame.w,
                "h": window.frame.h,
            ],
        ]
    }

    private func jsonNullable(_ value: String?) -> Any {
        if let value { return value }
        return NSNull()
    }

    private func addOptional(_ value: String?, key: String, to payload: inout [String: Any]) {
        guard let value else { return }
        payload[key] = value
    }

    private static func prettyJSONString(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"error":"layer context unavailable"}"#
        }
        return text
    }

    // MARK: - Recall

    /// Resolve the rule against live windows and raise them, with bezel feedback.
    /// This is the recall path the Studio panel and ⌘L share.
    func recall(_ layer: StudioLayer) {
        DesktopModel.shared.poll()
        let wins = resolve(layer)
        guard !wins.isEmpty else {
            DiagnosticLog.shared.info("StudioLayerStore: recall '\(layer.name)' matched 0 windows")
            return
        }
        WindowTiler.raiseWindowsAndReactivate(windows: wins.map { (wid: $0.wid, pid: $0.pid) })
        let idx = layers.firstIndex(where: { $0.id == layer.id }) ?? 0
        LayerBezel.shared.show(label: layer.name, index: idx, total: layers.count, allLabels: layers.map(\.name))
        DiagnosticLog.shared.info("StudioLayerStore: recalled '\(layer.name)' → raised \(wins.count) windows")
    }

    // MARK: - CRUD

    @discardableResult
    func add(name: String, match: [StudioLayerClause]) -> StudioLayer {
        let layer = StudioLayer(name: name, match: match)
        layers.append(layer)
        save()
        return layer
    }

    func rename(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[i].name = trimmed
        save()
    }

    func update(_ layer: StudioLayer) {
        guard let i = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[i] = layer
        save()
    }

    func delete(id: String) {
        layers.removeAll { $0.id == id }
        save()
    }

    // MARK: - Authoring from a pluck

    /// Infer a rule from a plucked set of live windows: group by exact app name
    /// and OR the apps together. This still auto-includes future windows from
    /// those apps, but avoids accidental substring matches.
    @discardableResult
    func saveFromPluck(_ entries: [WindowEntry], name: String? = nil) -> StudioLayer {
        let apps = orderedUniqueApps(entries)
        let clauses = apps.map { StudioLayerClause(appEquals: $0) }
        let layerName = name ?? defaultName(forApps: apps)
        return add(name: layerName, match: clauses.isEmpty ? [StudioLayerClause()] : clauses)
    }

    private func orderedUniqueApps(_ entries: [WindowEntry]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for e in entries where !seen.contains(e.app) {
            seen.insert(e.app)
            result.append(e.app)
        }
        return result
    }

    private func defaultName(forApps apps: [String]) -> String {
        switch apps.count {
        case 0:  return uniqueName("Layer")
        case 1:  return uniqueName(apps[0])
        case 2:  return uniqueName("\(apps[0]) + \(apps[1])")
        default: return uniqueName("\(apps[0]) +\(apps.count - 1)")
        }
    }

    private func uniqueName(_ base: String) -> String {
        guard layers.contains(where: { $0.name == base }) else { return base }
        var n = 2
        while layers.contains(where: { $0.name == "\(base) \(n)" }) { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([StudioLayer].self, from: data) {
            layers = saved
            return
        }
        // First run: seed (in memory) from clusters.json. We don't write
        // layers.json until the user actually changes something, so we never
        // surprise them with a file on launch.
        layers = Self.seedFromClusters()
    }

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(layers)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DiagnosticLog.shared.error("StudioLayerStore: save failed — \(error)")
        }
    }

    /// One-time seed: convert each clusters.json rule into a single-clause layer
    /// so the Studio view is non-empty on first run.
    private static func seedFromClusters() -> [StudioLayer] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices/clusters.json")
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([ClusterRule].self, from: data) else { return [] }
        return rules.map { rule in
            StudioLayer(name: rule.name, match: [StudioLayerClause(app: rule.app, titleContains: rule.titleContains)])
        }
    }
}
