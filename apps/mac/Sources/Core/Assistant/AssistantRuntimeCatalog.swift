import Foundation
import HudsonUI

/// The harness / model / effort catalog behind the composer's runtime picker.
///
/// Scout owns the list (`scout runtimes --json`); this maps it onto the
/// agent-runner's harness ids and onto what each agent-sessions adapter can
/// actually be told at start. A model or effort an adapter would ignore is not
/// offered: picking it would change the chip and nothing else.
///
/// The last good Scout answer is cached on disk, so the picker is populated
/// at launch while a fresh `scout runtimes` (a few seconds) runs behind it.
@MainActor
final class AssistantRuntimeCatalog: ObservableObject {
    static let shared = AssistantRuntimeCatalog()

    @Published private(set) var harnesses: [HudRuntimeHarness] = []
    @Published private(set) var efforts: [HudRuntimeEffort] = []

    private var isLoading = false
    private var lastLoaded: Date?

    /// Runner harness id → Scout harness id, in picker order.
    private static let runnerHarnesses: [(runner: String, scout: String, label: String)] = [
        ("claude-code", "claude", "Claude Code"),
        ("codex", "codex", "Codex"),
        ("pi", "pi", "Pi"),
        ("opencode", "opencode", "OpenCode"),
    ]

    /// Adapters that honour a start-time model (`claude --model`, `pi --model`,
    /// codex launch args). OpenCode's adapter ignores it today.
    static let modelHarnesses: Set<String> = ["claude-code", "codex", "pi"]
    /// Adapters that honour a start-time reasoning effort (codex launch args).
    static let effortHarnesses: Set<String> = ["codex"]

    /// Stand-in row for a harness with nothing to pick: it runs its own default.
    static let harnessDefaultModel = HudRuntimeModel(id: "", label: "Default", isDefault: true)

    private static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices/cache/scout-runtimes.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.cacheURL) {
            apply(data)
        }
    }

    /// Refresh from Scout at most every ten minutes; `force` skips the wait.
    func refresh(force: Bool = false) {
        if isLoading { return }
        if !force, let lastLoaded, Date().timeIntervalSince(lastLoaded) < 600 { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let data = try await Self.fetch()
                guard apply(data) else { return }
                lastLoaded = Date()
                let url = Self.cacheURL
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: url, options: .atomic)
            } catch {
                DiagnosticLog.shared.warn("Assistant · scout runtimes failed: \(error.localizedDescription)")
            }
        }
    }

    /// Scout runs one core command at a time and refuses the rest, so a
    /// runtimes call that lands on another is retried rather than dropped.
    private static func fetch() async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await ScoutAssistantTransport().runtimesJSON()
            } catch {
                attempt += 1
                guard attempt < 4, error.localizedDescription.contains("already running") else { throw error }
                try await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// The selection's model, when its harness can be told one and the model
    /// is one of that harness's (a pick saved for another harness is dropped).
    func launchModel(for selection: HudRuntimeSelection) -> String? {
        guard Self.modelHarnesses.contains(selection.harnessId), !selection.modelId.isEmpty,
              harnesses.first(where: { $0.id == selection.harnessId })?
                .models.contains(where: { $0.id == selection.modelId }) == true else { return nil }
        return selection.modelId
    }

    /// The selection's effort, when its harness can be told one.
    func launchEffort(for selection: HudRuntimeSelection) -> String? {
        guard Self.effortHarnesses.contains(selection.harnessId),
              selection.effortId != HudRuntimeEffort.autoId,
              !selection.effortId.isEmpty else { return nil }
        return selection.effortId
    }

    @discardableResult
    private func apply(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let caps = root["runtimeCapabilities"] as? [String: Any] else { return false }
        let scoutHarnesses = caps["harnesses"] as? [[String: Any]] ?? []
        let scoutModels = caps["models"] as? [[String: Any]] ?? []
        let scoutEfforts = caps["efforts"] as? [[String: Any]] ?? []
        let defaults = caps["defaultsByHarness"] as? [String: [String: Any]] ?? [:]

        let runnerByScout = Dictionary(
            uniqueKeysWithValues: Self.runnerHarnesses.map { ($0.scout, $0.runner) }
        )

        harnesses = Self.runnerHarnesses.map { entry in
            let scout = scoutHarnesses.first { ($0["id"] as? String) == entry.scout }
            let defaultModel = defaults[entry.scout]?["model"] as? String
            var models: [HudRuntimeModel] = []
            if Self.modelHarnesses.contains(entry.runner) {
                models = scoutModels.compactMap { model in
                    guard let id = model["id"] as? String,
                          let label = model["label"] as? String,
                          (model["harnesses"] as? [String])?.contains(entry.scout) == true else { return nil }
                    return HudRuntimeModel(
                        id: id,
                        label: label,
                        isDefault: id == defaultModel || (defaultModel == nil && model["isDefault"] as? Bool == true)
                    )
                }
            }
            if models.isEmpty { models = [Self.harnessDefaultModel] }
            return HudRuntimeHarness(
                id: entry.runner,
                label: (scout?["label"] as? String) ?? entry.label,
                models: models,
                isAvailable: scout?["ready"] as? Bool ?? false
            )
        }

        efforts = [.auto] + scoutEfforts.compactMap { effort in
            guard let id = effort["id"] as? String, let label = effort["label"] as? String else { return nil }
            let supported = Set((effort["harnesses"] as? [String] ?? []).compactMap { runnerByScout[$0] })
                .intersection(Self.effortHarnesses)
            guard !supported.isEmpty else { return nil }
            let models = (effort["models"] as? [String]).map(Set.init)
            return HudRuntimeEffort(id: id, label: label, harnesses: supported, models: models)
        }
        return !harnesses.isEmpty
    }
}
