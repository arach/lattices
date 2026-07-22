import Foundation

/// Shared fuzzy scorer for the command bar's local matching (projects, apps,
/// slash-commands). Returns 0 for no match; higher = better. Case- and
/// diacritic-insensitive.
enum FuzzyScore {
    static func score(query raw: String, candidate rawCandidate: String) -> Int {
        let q = normalize(raw)
        let c = normalize(rawCandidate)
        guard !q.isEmpty, !c.isEmpty else { return 0 }

        if c == q { return 120 }
        if c.hasPrefix(q) { return 100 }
        // Word detection runs on the ORIGINAL text so camelCase humps count as
        // boundaries (folding lowercases everything first).
        let words = words(in: rawCandidate)
        if words.contains(where: { normalize($0).hasPrefix(q) }) { return 85 }
        // Initials abbreviation: "tw" → "Tile Window", "gc" → "Google Chrome".
        let initials = words.compactMap { normalize($0).first }.map(String.init).joined()
        if !initials.isEmpty, initials.hasPrefix(q) { return 80 }
        if c.contains(q) { return 60 }
        return subsequenceScore(q: q, c: c)
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func normalize(_ s: Substring) -> String {
        normalize(String(s))
    }

    private static let separators: Set<Character> = [" ", "-", "_", "/", ".", ":"]

    /// Words split at separators and camelCase humps, original text preserved.
    private static func words(in s: String) -> [Substring] {
        var out: [Substring] = []
        var start = s.startIndex
        var previous: Character?
        for i in s.indices {
            if let p = previous,
               separators.contains(p) || (p.isLowercase && s[i].isUppercase) {
                let word = s[start..<i]
                if !word.isEmpty, !word.allSatisfy({ separators.contains($0) }) {
                    out.append(word)
                }
                start = i
            }
            previous = s[i]
        }
        let last = s[start...]
        if !last.isEmpty, !last.allSatisfy({ separators.contains($0) }) {
            out.append(last)
        }
        return out
    }

    /// Ordered-character (subsequence) match: base 40 with bonuses for adjacency
    /// and word starts, capped below the substring tier so loose matches never
    /// outrank a real substring hit.
    private static func subsequenceScore(q: String, c: String) -> Int {
        var score = 40
        var qi = q.startIndex
        var previousMatch: String.Index?
        for ci in c.indices {
            guard qi < q.endIndex else { break }
            guard c[ci] == q[qi] else { continue }
            if let p = previousMatch, c.index(after: p) == ci { score += 2 }
            if ci == c.startIndex || separators.contains(c[c.index(before: ci)]) { score += 3 }
            previousMatch = ci
            qi = q.index(after: qi)
        }
        guard qi == q.endIndex else { return 0 }
        return min(score, 55)
    }
}
