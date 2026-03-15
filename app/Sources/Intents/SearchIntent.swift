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
        // show me (without "windows" suffix)
        "show me all the {query}",
        "show me all {query}",
        "show me the {query}",
        "show me {query}",
        "show all the {query}",
        "show all {query}",
        // get
        "get {query}",
        "get all {query}",
        "get all the {query}",
        "get me {query}",
        "get me all the {query}",
        // give me
        "give me all the {query}",
        "give me all {query}",
        "give me {query}",
        // list
        "list {query}",
        "list all {query}",
        "list all the {query}",
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

    /// Expand natural-language terms into search-friendly queries.
    /// e.g. "terminals" → ["terminals", "iterm", "terminal", "warp", "kitty", "alacritty"]
    private static let synonyms: [String: [String]] = [
        "terminals": ["iterm", "terminal", "warp", "kitty", "alacritty", "hyper"],
        "terminal": ["iterm", "terminal", "warp", "kitty", "alacritty", "hyper"],
        "browsers": ["safari", "chrome", "firefox", "arc", "brave", "edge"],
        "browser": ["safari", "chrome", "firefox", "arc", "brave", "edge"],
        "editors": ["code", "cursor", "xcode", "vim", "neovim", "zed", "sublime"],
        "editor": ["code", "cursor", "xcode", "vim", "neovim", "zed", "sublime"],
        "chat": ["slack", "discord", "messages", "telegram", "whatsapp"],
        "music": ["spotify", "music", "apple music"],
        "mail": ["mail", "gmail", "outlook", "spark"],
        "notes": ["notes", "obsidian", "notion", "bear"],
    ]

    /// Clean up a voice query: strip filler phrases, qualifiers, and noise.
    private static func cleanQuery(_ raw: String) -> String {
        var q = raw.lowercased().trimmingCharacters(in: .whitespaces)

        // Strip trailing qualifiers ("and sort by ...", "sorted by ...", "ordered by ...")
        for pattern in [" and sort", " and order", " sorted by", " ordered by",
                        " and filter", " and group", " and show", " and list",
                        " please", " for me"] {
            if let range = q.range(of: pattern) {
                q = String(q[q.startIndex..<range.lowerBound])
            }
        }

        // Strip trailing "windows"/"apps"
        for suffix in [" windows", " apps", " applications"] {
            if q.hasSuffix(suffix) {
                q = String(q.dropLast(suffix.count))
                break
            }
        }

        return q.trimmingCharacters(in: .whitespaces)
    }

    func perform(slots: [String: JSON]) throws -> JSON {
        guard let rawQuery = slots["query"]?.stringValue, !rawQuery.isEmpty else {
            throw IntentError.missingSlot("query")
        }

        let queryLower = Self.cleanQuery(rawQuery)
        guard !queryLower.isEmpty else {
            throw IntentError.missingSlot("query")
        }

        if queryLower != rawQuery.lowercased().trimmingCharacters(in: .whitespaces) {
            DiagnosticLog.shared.info("search: cleaned '\(rawQuery)' → '\(queryLower)'")
        }

        // Check for synonym expansion (e.g. "terminals" → ["iterm", "terminal", ...])
        if let expansions = Self.synonyms[queryLower] {
            DiagnosticLog.shared.info("search: query='\(rawQuery)' → expanding to \(expansions)")
            return try searchExpanded(queries: expansions)
        }

        DiagnosticLog.shared.info("search: query='\(queryLower)'")
        return try searchSingle(query: queryLower)
    }

    private func searchSingle(query: String) throws -> JSON {
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

    /// Search for multiple expanded queries and deduplicate by window ID.
    private func searchExpanded(queries: [String]) throws -> JSON {
        var seenWids: Set<Int> = []
        var merged: [JSON] = []

        for q in queries {
            let result = try LatticesApi.shared.dispatch(
                method: "lattices.search",
                params: .object(["query": .string(q), "mode": .string("quick")])
            )
            if case .array(let items) = result {
                for item in items {
                    if let wid = item["wid"]?.intValue, !seenWids.contains(wid) {
                        seenWids.insert(wid)
                        merged.append(item)
                    }
                }
            }
        }

        DiagnosticLog.shared.info("search: \(merged.count) results from expanded search")
        return .array(merged)
    }
}
