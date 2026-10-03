import Foundation

/// Turns a selection copied out of a terminal into prose-shaped markdown for
/// the reader layer.
///
/// Terminals already join rows they soft-wrapped when copying, so every
/// newline that survives was written by the program — including the hard
/// wraps a TUI (Claude Code, `fmt`, man pages) inserts at its own width. Those
/// are the ones this undoes. The test for a wrap is the classic reflow one: a
/// break is a wrap when the next line's first word would not have fit on the
/// line before it. Short lines followed by a word that would have fit were
/// broken on purpose, and stay broken.
public enum TerminalText {
    /// Below this widest-line width the selection is treated as intentionally
    /// short lines (a list of paths, a poem, a log tail) and never joined.
    static let minimumWrapWidth = 30

    public static func clean(_ raw: String) -> String {
        var lines = stripANSI(raw)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(stripTrailingWhitespace)

        lines = lines.compactMap(unframe)
        lines = lines.map(replaceLeadingMarker)
        lines = trimBlankEdges(lines)
        lines = dedent(lines)
        lines = fenceBoxDrawing(lines)
        lines = unwrap(lines)
        return lines.joined(separator: "\n")
    }

    // MARK: - Steps

    /// CSI (`ESC [ … final`) and OSC (`ESC ] … BEL|ST`) sequences. Copies from
    /// a terminal are normally plain, but a pasted log or `script` capture is not.
    static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        let patterns = [
            "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)",
            "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",
            "\u{1B}[@-Z\\\\-_]",
        ]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }

    static func stripTrailingWhitespace(_ line: String) -> String {
        var line = Substring(line)
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return String(line)
    }

    private static let frameEdges: Set<Character> = ["╭", "╮", "╰", "╯", "┌", "┐", "└", "┘", "─", "━", "═"]
    private static let boxDrawing: Set<Character> = [
        "│", "┃", "║", "├", "┤", "┬", "┴", "┼", "╞", "╡", "╪", "╟", "╢", "╫",
        "┌", "┐", "└", "┘", "─", "━", "═", "╭", "╮", "╰", "╯",
    ]

    /// A TUI box (`╭──╮ │ text │ ╰──╯`): drop pure border rows and peel the
    /// side rails off content rows. A row with inner rails is a table and is
    /// left for `fenceBoxDrawing`.
    static func unframe(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 3, trimmed.allSatisfy({ frameEdges.contains($0) || $0 == " " }),
           trimmed.contains(where: { $0 == "─" || $0 == "━" || $0 == "═" }),
           !trimmed.contains("┬"), !trimmed.contains("┴") {
            return nil
        }
        guard trimmed.count >= 2,
              let first = trimmed.first, let last = trimmed.last,
              first == "│" || first == "┃", last == "│" || last == "┃"
        else { return line }
        let inner = trimmed.dropFirst().dropLast()
        guard !inner.contains("│"), !inner.contains("┃") else { return line }
        let indent = line.prefix { $0 == " " }
        // Keep the column the rail occupied so dedent treats every framed row alike.
        return stripTrailingWhitespace(indent + " " + inner)
    }

    /// Claude Code prefixes a turn with `⏺` and a tool result with `⎿`. Blank
    /// the marker (keeping its columns) so the text lines up with its own
    /// continuation rows and dedents cleanly.
    static func replaceLeadingMarker(_ line: String) -> String {
        let indent = line.prefix { $0 == " " }
        let rest = line.dropFirst(indent.count)
        for marker in ["⏺ ", "● ", "⎿ "] where rest.hasPrefix(marker) {
            return indent + String(repeating: " ", count: marker.count) + rest.dropFirst(marker.count)
        }
        return line
    }

    static func trimBlankEdges(_ lines: [String]) -> [String] {
        guard let first = lines.firstIndex(where: { !$0.isEmpty }),
              let last = lines.lastIndex(where: { !$0.isEmpty })
        else { return [] }
        return Array(lines[first...last])
    }

    static func dedent(_ lines: [String]) -> [String] {
        let indents = lines.filter { !$0.isEmpty }.map { $0.prefix { $0 == " " }.count }
        guard let common = indents.min(), common > 0 else { return lines }
        return lines.map { $0.isEmpty ? $0 : String($0.dropFirst(common)) }
    }

    /// Runs of box-drawn rows (tables, trees) only survive as monospace.
    static func fenceBoxDrawing(_ lines: [String]) -> [String] {
        var out: [String] = []
        var inFence = false
        var inBox = false
        for line in lines {
            if isFence(line) { inFence.toggle() }
            let boxed = !inFence && !isFence(line) && line.contains(where: boxDrawing.contains)
            if boxed && !inBox { out.append("```") }
            if !boxed && inBox { out.append("```") }
            inBox = boxed
            out.append(line)
        }
        if inBox { out.append("```") }
        return out
    }

    static func unwrap(_ lines: [String]) -> [String] {
        let width = lines.map(\.count).max() ?? 0
        guard width >= minimumWrapWidth else { return lines }

        var out: [String] = []
        // The on-screen row `out.last` ended with; joins grow the line past it.
        var lastRow = ""
        var inFence = false
        for line in lines {
            if isFence(line) {
                inFence.toggle()
                out.append(line)
                lastRow = line
                continue
            }
            if !inFence, let previous = out.last, isWrap(lastRow, then: line, width: width) {
                out[out.count - 1] = previous + " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                out.append(line)
            }
            lastRow = line
        }
        return out
    }

    // MARK: - Predicates

    static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// True when `next` continues the row `previous` because that row ran out
    /// of room: `next`'s first word would not have fit after it.
    static func isWrap(_ previous: String, then next: String, width: Int) -> Bool {
        let body = next.trimmingCharacters(in: .whitespaces)
        guard !previous.isEmpty, !body.isEmpty,
              !isFence(previous), !startsBlock(body),
              // A lead-in ("…these files:") introduces what follows on its own line.
              !previous.hasSuffix(":"),
              !previous.contains(where: boxDrawing.contains)
        else { return false }
        let firstWord = body.prefix { $0 != " " }.count
        return previous.count + 1 + firstWord > width
    }

    /// Markdown block starts never continue the line above.
    static func startsBlock(_ body: String) -> Bool {
        if body.hasPrefix("#") || body.hasPrefix(">") || body.hasPrefix("|") { return true }
        for bullet in ["- ", "* ", "+ ", "• ", "◦ ", "▪ ", "☐ ", "☒ ", "✔ ", "✓ ", "✗ "] where body.hasPrefix(bullet) {
            return true
        }
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = body.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return true }
        }
        return false
    }
}
