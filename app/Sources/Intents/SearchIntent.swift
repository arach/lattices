import Foundation

struct SearchIntent: LatticeIntent {
    static let name = "search"
    static let title = "Find windows by name, title, or content"

    static let phrases = [
        // Primary operator: find
        "find {query}",
        "find all {query}",
        "find all the {query}",
        // search
        "search {query}",
        "search for {query}",
        "search for all {query}",
        // look for
        "look for {query}",
        "look up {query}",
        // where
        "where is {query}",
        "where's {query}",
        "where does it say {query}",
        "where did i see {query}",
        // which / can you
        "which window has {query}",
        "which window shows {query}",
        "can you find {query}",
        "help me find {query}",
        // locate
        "locate {query}",
        "locate all {query}",
        // "open up all the X windows" = find, not launch
        "open up all the {query} windows",
        "open up all {query} windows",
        "open all the {query} windows",
        "open all {query} windows",
        "show me all the {query} windows",
        "show me all {query} windows",
        "show all the {query} windows",
        "show all {query} windows",
        // "pull up" = find/focus
        "pull up {query}",
        "pull up all {query}",
        "pull up everything with {query} in it",
        "bring up all the {query}",
        "bring up all {query}",
        // Casual / natural
        "where'd my {query} go",
        "where'd {query} go",
        "i lost my {query}",
        "i lost {query}",
        "where the hell is {query}",
        "get {query} on screen",
        "{query} windows",
    ]

    static let slots = [
        SlotDef(name: "query", type: .string, required: true),
    ]

    func perform(slots: [String: JSON]) throws -> JSON {
        guard let query = slots["query"]?.stringValue, !query.isEmpty else {
            throw IntentError.missingSlot("query")
        }
        DiagnosticLog.shared.info("search: query='\(query)'")

        // Quick first — title, app, session, OCR (instant)
        let quick = try LatticesApi.shared.dispatch(
            method: "lattices.search",
            params: .object(["query": .string(query), "mode": .string("quick")])
        )
        if case .array(let items) = quick, !items.isEmpty {
            DiagnosticLog.shared.info("search: \(items.count) results for '\(query)' (quick)")
            return quick
        }

        // Escalate to complete — adds terminal cwd/processes + OCR
        let result = try LatticesApi.shared.dispatch(
            method: "lattices.search",
            params: .object(["query": .string(query)])
        )
        if case .array(let items) = result {
            DiagnosticLog.shared.info("search: \(items.count) results for '\(query)' (complete)")
        }
        return result
    }
}
