import AppKit

// MARK: - StudioLayerClause

/// One match clause. A window satisfies a clause when it meets every present
/// criterion (app AND titleContains) — the same semantics as a `ClusterRule`.
/// A `StudioLayer` ORs its clauses together, so a heterogeneous plucked set
/// (a Chrome window + a terminal) becomes "app Chrome OR app iTerm".
struct StudioLayerClause: Codable, Equatable {
    var app: String?            // app name contains (case-insensitive)
    var titleContains: String?  // window title contains (case-insensitive)

    func matches(_ e: WindowEntry) -> Bool {
        var matched = false
        if let app {
            if !e.app.localizedCaseInsensitiveContains(app) { return false }
            matched = true
        }
        if let titleContains {
            if !e.title.localizedCaseInsensitiveContains(titleContains) { return false }
            matched = true
        }
        return matched
    }

    var summary: String {
        switch (app, titleContains) {
        case let (a?, t?):  return "\(a)·~\(t)"
        case let (a?, nil): return a
        case let (nil, t?): return "~\(t)"
        default:            return "any"
        }
    }
}

// MARK: - StudioLayer

/// A named, rule-backed layer. Membership is *computed* by evaluating the rule
/// against live windows — it is not a frozen list of window IDs — so a layer
/// survives restarts and auto-includes any new window that matches. Authored by
/// plucking in Hyperspace (or edited by hand), recalled from the Studio panel
/// or ⌘L. This is the unified successor to clusters and session layers.
struct StudioLayer: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var match: [StudioLayerClause]

    init(id: String = UUID().uuidString, name: String, match: [StudioLayerClause]) {
        self.id = id
        self.name = name
        self.match = match
    }

    /// A window belongs to the layer if it satisfies ANY clause (OR).
    func contains(_ e: WindowEntry) -> Bool {
        match.contains { $0.matches(e) }
    }

    /// Human-readable rule, e.g. "Chrome · iTerm2 · ~localhost".
    var summary: String {
        guard !match.isEmpty else { return "no rule" }
        return match.map(\.summary).joined(separator: " · ")
    }
}
