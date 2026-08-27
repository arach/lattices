import Foundation

// MARK: - Start → Edit → Review
// The cycle is inherent to the product — not a named "loop" object.
// Users work with a scenario (plan) and takes (runs).

enum ActionLauncherDestination: String, CaseIterable, Identifiable {
    case home
    case scenarios
    case runs
    case library
    case settings

    var id: String { rawValue }
}

/// What you're looking at for a scenario — plan vs last take.
/// Start is not a mode; it's creating a scenario.
enum ActionFlowPhase: String, CaseIterable, Identifiable {
    case edit
    case review

    var id: String { rawValue }

    /// User-facing labels (not wizard chrome).
    var title: String {
        switch self {
        case .edit: return "Plan"
        case .review: return "Take"
        }
    }

    var subtitle: String {
        switch self {
        case .edit: return "Steps the next run will follow"
        case .review: return "Last capture for this scenario"
        }
    }
}

extension ActionFlowPhase: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "review":
            self = .review
        default:
            // edit, start, plan, unknown → plan
            self = .edit
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ActionScenarioStepFeedback: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: String
    var instruction: String
}

struct ActionScenarioStep: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var index: Int
    var action: String
    var description: String
    var targetSummary: String?
    /// pending | approved | flagged | skipped
    var status: String
    var feedback: [ActionScenarioStepFeedback]

    var isSkipped: Bool { status == "skipped" }
    var isFlagged: Bool { status == "flagged" || !feedback.isEmpty }
}

/// A draft plan the agent (or a preset) proposed. Runs produce takes.
struct ActionScenarioDocument: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var goal: String
    var phase: ActionFlowPhase
    /// Built-in seed id (e.g. calculator-demo).
    var scenarioId: String
    var targetAppName: String
    var targetBundleId: String
    var steps: [ActionScenarioStep]
    /// Take session ids produced by runs of this scenario.
    var sessionIds: [String]
    var latestSessionId: String?
    var createdAt: String
    var updatedAt: String
    var lastRunStatus: String?

    var feedbackCount: Int {
        steps.reduce(0) { $0 + $1.feedback.count }
    }
}

enum ActionScenarioPresets {
    static func calculatorDemoSteps() -> [ActionScenarioStep] {
        [
            step(1, action: "type", description: "Enter 12", target: "keyboard"),
            step(2, action: "click", description: "Click plus", target: "calculator.operator.plus"),
            step(3, action: "type", description: "Enter 30", target: "keyboard"),
            step(4, action: "press-key", description: "Press equals", target: "calculator.operator.equals"),
        ]
    }

    static func makeCalculatorScenario(goal: String? = nil) -> ActionScenarioDocument {
        let now = ISO8601DateFormatter().string(from: Date())
        let id = "scenario-\(Int(Date().timeIntervalSince1970))-\(String(UUID().uuidString.prefix(6)).lowercased())"
        let resolvedGoal = (goal?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Calculator, keyboard and click"

        return ActionScenarioDocument(
            id: id,
            title: "Calculator demo",
            goal: resolvedGoal,
            phase: .edit, // plan
            scenarioId: "calculator-demo",
            targetAppName: "Calculator",
            targetBundleId: "com.apple.calculator",
            steps: calculatorDemoSteps(),
            sessionIds: [],
            latestSessionId: nil,
            createdAt: now,
            updatedAt: now,
            lastRunStatus: nil
        )
    }

    private static func step(
        _ index: Int,
        action: String,
        description: String,
        target: String?
    ) -> ActionScenarioStep {
        ActionScenarioStep(
            id: "step_\(index)",
            index: index,
            action: action,
            description: description,
            targetSummary: target,
            status: "pending",
            feedback: []
        )
    }
}

@MainActor
final class ActionScenarioStore {
    static let shared = ActionScenarioStore()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private var scenariosDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/scenarios", isDirectory: true)
    }

    /// Legacy path from the short-lived "loops" naming.
    private var legacyLoopsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/loops", isDirectory: true)
    }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: scenariosDirectoryURL, withIntermediateDirectories: true)
    }

    func loadAll() -> [ActionScenarioDocument] {
        migrateLegacyLoopsIfNeeded()

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: scenariosDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sorted = urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }

        return sorted.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ActionScenarioDocument.self, from: data)
        }
    }

    func save(_ document: ActionScenarioDocument) throws {
        try ensureDirectory()
        var copy = document
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = try encoder.encode(copy)
        let url = scenariosDirectoryURL.appendingPathComponent("\(copy.id).json")
        try data.write(to: url, options: .atomic)
    }

    func delete(id: String) throws {
        let url = scenariosDirectoryURL.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func migrateLegacyLoopsIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyLoopsDirectoryURL.path) else { return }
        try? ensureDirectory()

        guard let urls = try? fm.contentsOfDirectory(
            at: legacyLoopsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            // Old files used the same JSON shape with different Swift type names — field names match.
            let dest = scenariosDirectoryURL.appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: "loop-", with: "scenario-"))
            if fm.fileExists(atPath: dest.path) { continue }
            if let data = try? Data(contentsOf: url),
               var doc = try? decoder.decode(ActionScenarioDocument.self, from: data) {
                // Re-key ids that still say loop-
                if doc.id.hasPrefix("loop-") {
                    doc = ActionScenarioDocument(
                        id: doc.id.replacingOccurrences(of: "loop-", with: "scenario-"),
                        title: doc.title,
                        goal: doc.goal,
                        phase: doc.phase,
                        scenarioId: doc.scenarioId,
                        targetAppName: doc.targetAppName,
                        targetBundleId: doc.targetBundleId,
                        steps: doc.steps,
                        sessionIds: doc.sessionIds,
                        latestSessionId: doc.latestSessionId,
                        createdAt: doc.createdAt,
                        updatedAt: doc.updatedAt,
                        lastRunStatus: doc.lastRunStatus
                    )
                }
                try? save(doc)
            } else if let data = try? Data(contentsOf: url) {
                // If decode fails (old encoding), copy raw for inspection
                try? data.write(to: dest)
            }
        }
    }
}
