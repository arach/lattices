import Foundation

/// Shared question-vs-command heuristics so the typed command bar and the voice
/// path (`AudioLayer`) classify utterances the same way — one source of truth
/// for "is this a Lattices question to hand to the assistant, or a command?".
enum IntentHeuristics {
    /// If the utterance explicitly addresses the assistant, return the prompt
    /// after the wake phrase. This lets "assistant ..." bypass command matching.
    static func assistantWakePrompt(_ text: String) -> String? {
        let trimmed = normalizedWhitespace(text)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let wakePhrases = [
            "ask the assistant",
            "ask assistant",
            "hey lattices",
            "hey lattice",
            "assistant",
            "lattices",
            "lattice"
        ]

        for phrase in wakePhrases {
            if lower == phrase {
                return trimmed
            }
            guard lower.hasPrefix(phrase) else { continue }

            let index = trimmed.index(trimmed.startIndex, offsetBy: phrase.count)
            guard let first = trimmed[index...].first,
                  first.isWhitespace || first.isPunctuation else { continue }
            let remainder = trimmed[index...]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            if !remainder.isEmpty {
                return remainder
            }
        }

        return nil
    }

    static func assistantPromptText(_ text: String) -> String {
        assistantWakePrompt(text) ?? normalizedWhitespace(text)
    }

    /// True when an utterance is a Lattices-flavoured *question* (and not a
    /// command) — i.e. it should be answered by the assistant rather than run.
    static func shouldAskAssistant(_ text: String) -> Bool {
        if assistantWakePrompt(text) != nil { return true }

        let lower = text.lowercased()
        let questionStarters = [
            "what", "how", "why", "where", "when", "who",
            "can you tell", "tell me about", "explain", "summarize", "describe"
        ]
        let asksQuestion = text.contains("?") || questionStarters.contains(where: lower.hasPrefix)
        guard asksQuestion else { return false }
        guard !looksLikeCommand(lower) else { return false }

        let assistantTopics = [
            "setting", "settings", "configured", "enabled", "disabled",
            "mouse", "shortcut", "shortcuts", "gesture", "gestures",
            "ocr", "terminal", "scan root", "assistant", "provider",
            "lattices", "workspace"
        ]
        return assistantTopics.contains(where: lower.contains)
    }

    /// True when a (lowercased) utterance reads like an actionable command.
    static func looksLikeCommand(_ lower: String) -> Bool {
        let commandWords = [
            "open", "launch", "start", "focus", "show", "bring up", "pull up",
            "tile", "move", "put", "snap", "maximize", "center", "kill", "close",
            "stop", "switch", "go to", "find", "search", "scan", "read the screen",
            "organize", "arrange", "grid", "run"
        ]
        let questionOnlyStarters = [
            "what can", "what should", "what is", "what s", "how do", "how can",
            "why", "where is", "when", "who"
        ]
        if questionOnlyStarters.contains(where: lower.hasPrefix) { return false }
        return commandWords.contains { word in
            lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
        }
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
