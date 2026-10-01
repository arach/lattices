import AppKit

// MARK: - StudioLayerClause

/// One match clause. The Hyperspace editor intentionally keeps authoring simple:
/// pick an app name and, optionally, a direct or regex match against the window
/// name/title.
/// A ⌘⌥ layer entry's `match`; a layer holds a window when any of its
/// entries matches it.
struct StudioLayerClause: Codable, Equatable {
    var app: String? = nil              // app name contains (case-insensitive)
    var appEquals: String? = nil        // app name exactly equals (case-insensitive)
    var appRegex: String? = nil         // app name matches regex (case-insensitive)
    var titleContains: String? = nil    // window title contains (case-insensitive)
    var titleEquals: String? = nil      // window title exactly equals (case-insensitive)
    var titleRegex: String? = nil       // window title matches regex (case-insensitive)
    var session: String? = nil          // lattices session exactly equals (case-insensitive)
    var sessionContains: String? = nil  // lattices session contains (case-insensitive)
    var isOnScreen: Bool? = nil         // visible on current Space
    var spaceId: Int? = nil             // member of a specific macOS Space id
    var not: [StudioLayerClause]? = nil // no exclusion clause may match

    func matches(_ e: WindowEntry) -> Bool {
        guard positiveCriteriaMatch(e) else { return false }
        if let not, not.contains(where: { $0.matches(e) }) {
            return false
        }
        return true
    }

    var summary: String {
        let positives = positiveSummaryParts
        guard !positives.isEmpty else { return "no rule" }
        let exclusions = (not ?? []).map { "not(\($0.summary))" }
        return (positives + exclusions).joined(separator: " · ")
    }

    var positiveSummaryParts: [String] {
        var parts: [String] = []
        appendNonEmpty(app, prefix: "App contains ", to: &parts)
        appendNonEmpty(appEquals, prefix: "App: ", to: &parts)
        appendNonEmpty(appRegex, prefix: "App matches /", suffix: "/", to: &parts)
        appendNonEmpty(titleContains, prefix: "Name: ", to: &parts)
        appendNonEmpty(titleEquals, prefix: "Name: ", to: &parts)
        appendNonEmpty(titleRegex, prefix: "Name matches /", suffix: "/", to: &parts)
        appendNonEmpty(session, prefix: "Session: ", to: &parts)
        appendNonEmpty(sessionContains, prefix: "Session contains ", to: &parts)
        if let isOnScreen {
            parts.append(isOnScreen ? "Visible" : "Offscreen")
        }
        if let spaceId {
            parts.append("Space \(spaceId)")
        }
        return parts
    }

    private func positiveCriteriaMatch(_ e: WindowEntry) -> Bool {
        var matched = false

        if let app = trimmed(app) {
            guard e.app.localizedCaseInsensitiveContains(app) else { return false }
            matched = true
        }
        if let appEquals = trimmed(appEquals) {
            guard e.app.localizedCaseInsensitiveCompare(appEquals) == .orderedSame else { return false }
            matched = true
        }
        if let appRegex = trimmed(appRegex) {
            guard Self.regex(appRegex, matches: e.app) else { return false }
            matched = true
        }
        if let titleContains = trimmed(titleContains) {
            guard e.title.localizedCaseInsensitiveContains(titleContains) else { return false }
            matched = true
        }
        if let titleEquals = trimmed(titleEquals) {
            guard e.title.localizedCaseInsensitiveCompare(titleEquals) == .orderedSame else { return false }
            matched = true
        }
        if let titleRegex = trimmed(titleRegex) {
            guard Self.regex(titleRegex, matches: e.title) else { return false }
            matched = true
        }
        if let session = trimmed(session) {
            guard e.latticesSession?.localizedCaseInsensitiveCompare(session) == .orderedSame else { return false }
            matched = true
        }
        if let sessionContains = trimmed(sessionContains) {
            guard e.latticesSession?.localizedCaseInsensitiveContains(sessionContains) == true else { return false }
            matched = true
        }
        if let isOnScreen {
            guard e.isOnScreen == isOnScreen else { return false }
            matched = true
        }
        if let spaceId {
            guard e.spaceIds.contains(spaceId) else { return false }
            matched = true
        }

        return matched
    }

    private static func regex(_ pattern: String, matches value: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func appendNonEmpty(_ value: String?, prefix: String?, suffix: String = "", to parts: inout [String]) {
        guard let value = trimmed(value) else { return }
        parts.append("\(prefix ?? "")\(value)\(suffix)")
    }
}
