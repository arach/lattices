import Foundation

/// Shared question-vs-command heuristics so the typed command bar and the voice
/// path (`AudioLayer`) classify utterances the same way — one source of truth
/// for "is this a Lattices question to hand to the assistant, or a command?".
enum IntentHeuristics {
    /// True when an utterance is a Lattices-flavoured *question* (and not a
    /// command) — i.e. it should be answered by the assistant rather than run.
    static func shouldAskAssistant(_ text: String) -> Bool {
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
}
