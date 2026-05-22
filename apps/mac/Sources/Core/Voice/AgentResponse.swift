import Foundation

// MARK: - Response types

struct AgentResponse {
    let commentary: String?
    let suggestion: AgentSuggestion?
    let raw: String

    struct AgentSuggestion {
        let label: String
        let intent: String
        let slots: [String: String]
    }

    static func parse(text: String) -> AgentResponse {
        guard let jsonStr = extractJSON(from: text),
              let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AgentResponse(commentary: text, suggestion: nil, raw: text)
        }

        let commentary = json["commentary"] as? String

        var suggestion: AgentSuggestion?
        if let s = json["suggestion"] as? [String: Any],
           let label = s["label"] as? String,
           let intent = s["intent"] as? String {
            let slots = (s["slots"] as? [String: String]) ?? [:]
            suggestion = AgentSuggestion(label: label, intent: intent, slots: slots)
        }

        return AgentResponse(commentary: commentary, suggestion: suggestion, raw: text)
    }

    private static func extractJSON(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }
        return String(cleaned[start...end])
    }
}
