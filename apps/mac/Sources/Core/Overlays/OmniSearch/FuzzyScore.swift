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
        if wordStarts(in: c).contains(where: { c[$0...].hasPrefix(q) }) { return 85 }
        if c.contains(q) { return 60 }
        return subsequenceScore(q: q, c: c)
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Indices that begin a new word (after a separator or a camelCase hump).
    private static func wordStarts(in s: String) -> [String.Index] {
        var starts: [String.Index] = []
        var previous: Character?
        for i in s.indices {
            if let p = previous {
                if p == " " || p == "-" || p == "_" || p == "/" || p == "." || p == ":" {
                    starts.append(i)
                } else if p.isLowercase, s[i].isUppercase {
                    starts.append(i)
                }
            }
            previous = s[i]
        }
        return starts
    }

    /// Ordered-character (subsequence) match: base 40 with bonuses for adjacency
    /// and word starts, capped below the substring tier so loose matches never
    /// outrank a real substring hit.
    private static func subsequenceScore(q: String, c: String) -> Int {
        let starts = Set(wordStarts(in: c))
        var score = 40
        var qi = q.startIndex
        var previousMatch: String.Index?
        for ci in c.indices {
            guard qi < q.endIndex else { break }
            guard c[ci] == q[qi] else { continue }
            if let p = previousMatch, c.index(after: p) == ci { score += 2 }
            if ci == c.startIndex || starts.contains(ci) { score += 3 }
            previousMatch = ci
            qi = q.index(after: qi)
        }
        guard qi == q.endIndex else { return 0 }
        return min(score, 55)
    }
}
