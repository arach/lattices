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

    /// Infer a rule from a plucked set of live windows: group by app and OR the
    /// apps together. Coarse on purpose — a rule-backed layer is meant to
    /// auto-include future windows of the same apps. Refine it later in Studio.
    @discardableResult
    func saveFromPluck(_ entries: [WindowEntry], name: String? = nil) -> StudioLayer {
        let apps = orderedUniqueApps(entries)
        let clauses = apps.map { StudioLayerClause(app: $0, titleContains: nil) }
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
