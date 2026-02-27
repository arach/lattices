import AppKit

struct InventoryPath: Equatable {
    let display: String
    let space: String
    let appType: String
    let appName: String
    let windowTitle: String

    var description: String {
        [display, space, appType, appName, windowTitle]
            .map { sanitize($0) }
            .joined(separator: ".")
    }

    func matches(pattern: String) -> Bool {
        let segments = description.split(separator: ".").map(String.init)
        let patternSegments = pattern.lowercased().split(separator: ".").map(String.init)

        for (i, pat) in patternSegments.enumerated() {
            guard i < segments.count else { return false }
            if pat == "*" { continue }
            if !segments[i].hasPrefix(pat) { return false }
        }
        return true
    }

    static func displayName(for screen: NSScreen, isMain: Bool) -> String {
        if isMain { return "main" }
        return sanitizeStatic(screen.localizedName)
    }

    private func sanitize(_ s: String) -> String {
        Self.sanitizeStatic(s)
    }

    private static func sanitizeStatic(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "[\\s./\\\\]+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9_-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
