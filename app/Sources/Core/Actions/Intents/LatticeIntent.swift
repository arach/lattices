import Foundation

// MARK: - Core Protocol

/// A self-contained voice intent. Each intent declares its phrases, slots, and execution.
protocol LatticeIntent {
    static var name: String { get }
    static var title: String { get }
    static var phrases: [String] { get }       // e.g. "find {query}", "search for {query}"
    static var slots: [SlotDef] { get }

    func perform(slots: [String: JSON]) throws -> JSON
}

// MARK: - Compiled Phrase Template

struct CompiledPhrase {
    let original: String                  // "find {query}"
    let regex: NSRegularExpression        // ^find (.+)$
    let slotNames: [String]              // ["query"] in capture-group order
    let intentName: String
}

// MARK: - Match Result

struct IntentMatch {
    let intentName: String
    let slots: [String: JSON]
    let confidence: Double
    let matchedPhrase: String
}

// MARK: - Phrase Matcher

final class PhraseMatcher {
    static let shared = PhraseMatcher()

    private init() {
        DiagnosticLog.shared.info("PhraseMatcher: semantic resolver active (\(IntentEngine.shared.definitions().count) intents)")
    }

    func match(text: String) -> IntentMatch? {
        VoiceIntentResolver.shared.match(text: text)
    }

    func execute(_ match: IntentMatch) throws -> JSON {
        try VoiceIntentResolver.shared.execute(match)
    }

    func catalog() -> JSON {
        VoiceIntentResolver.shared.catalog()
    }
}
