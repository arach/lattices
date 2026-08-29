import Foundation

/// Errors thrown by the frontmatter codec.
public enum FrontmatterError: Error, Equatable, Sendable {
    /// The file did not begin with a `---` frontmatter block.
    case missingFrontmatter
    /// The opening `---` was never closed by a second `---`.
    case unterminatedFrontmatter
    /// A required date field was missing or unparseable.
    case invalidDate(field: String)
    /// A required field (`id`) was missing.
    case missingField(String)
}

/// A minimal, purpose-built frontmatter codec for Blink notes.
///
/// This is *not* a general YAML parser. It handles exactly this schema:
/// ```
/// ---
/// id: <slug>
/// created: <ISO8601 with fractional seconds>
/// updated: <ISO8601 with fractional seconds>
/// tags: [a, b]
/// pinned: true
/// ---
/// <content>
/// ```
///
/// Behavior choices (all covered by tests):
/// - `encode` always emits `id`, `created`, `updated`, and always emits `tags`
///   and `pinned` (even when empty/false) for a stable, deterministic file. Decode
///   tolerates their absence and defaults to `[]` / `false`.
/// - Exactly one newline separates the closing `---` from the content, and that
///   newline is not part of the content. `decode` strips exactly one leading
///   newline after the closing delimiter; `encode` writes exactly one. Round-trips
///   are therefore byte-exact for the content, including any trailing newlines.
/// - Header lines Blink does not own — unknown keys, their indented continuation
///   lines, blank lines — are preserved *verbatim and in order* through the
///   round-trip (`Note.extraFrontmatter`), emitted after Blink's own fields.
///   Agents may stamp their own keys into a note without Blink erasing them.
///   Known keys are only recognized at the top level (unindented); Blink itself
///   always writes the inline forms (`tags: [a, b]`).
public enum Frontmatter {
    // A fresh formatter per call: ISO8601DateFormatter is not Sendable, so it
    // cannot be a shared static under strict concurrency.
    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    // MARK: - Encode

    public static func encode(_ note: Note) -> String {
        let dateFormatter = makeFormatter()
        var lines: [String] = ["---"]
        lines.append("id: \(note.id)")
        lines.append("created: \(dateFormatter.string(from: note.createdAt))")
        lines.append("updated: \(dateFormatter.string(from: note.updatedAt))")
        lines.append("tags: [\(note.tags.joined(separator: ", "))]")
        lines.append("pinned: \(note.pinned)")
        appendBlinkBlock(note, to: &lines)
        lines.append(contentsOf: note.extraFrontmatter)
        lines.append("---")

        // Join header, then exactly one newline, then content verbatim.
        return lines.joined(separator: "\n") + "\n" + note.content
    }

    /// Emit the `blink:` presentation block: known keys in canonical order and
    /// indentation, then any preserved unknown/invalid sub-lines verbatim. Nothing
    /// is emitted when there is neither typed presentation nor a preserved line.
    private static func appendBlinkBlock(_ note: Note, to lines: inout [String]) {
        let p = note.presentation
        guard !p.isEmpty || !note.extraBlink.isEmpty else { return }
        lines.append("blink:")
        if let v = p.workspace { lines.append("  workspace: \(quoteIfNeeded(v))") }
        if let v = p.style { lines.append("  style: \(v)") }
        if let v = p.sheet { lines.append("  sheet: \(v)") }
        if let v = p.accent { lines.append("  accent: \(quoteIfNeeded(v))") }
        if let v = p.font { lines.append("  font: \(quoteIfNeeded(v))") }
        if let v = p.fontSize { lines.append("  fontSize: \(formatDouble(v))") }
        if let v = p.lineHeight { lines.append("  lineHeight: \(formatDouble(v))") }
        if let v = p.tint { lines.append("  tint: \(formatDouble(v))") }
        if let v = p.tintRead { lines.append("  tintRead: \(formatDouble(v))") }
        if let v = p.tintEdit { lines.append("  tintEdit: \(formatDouble(v))") }
        if let v = p.radius { lines.append("  radius: \(formatDouble(v))") }
        if let v = p.slot { lines.append("  slot: \(v)") }
        if let v = p.lastWriter { lines.append("  lastWriter: \(quoteIfNeeded(v))") }
        lines.append(contentsOf: note.extraBlink)
    }

    // MARK: - Decode

    public static func decode(_ fileContents: String) throws -> Note {
        guard fileContents.hasPrefix("---\n") || fileContents == "---" || fileContents.hasPrefix("---\r\n") else {
            throw FrontmatterError.missingFrontmatter
        }

        // Work on lines but keep enough structure to recover exact content.
        // Split into the frontmatter body and the remainder after the closing "---".
        let afterOpen = String(fileContents.dropFirst("---".count))
        // Drop the newline that follows the opening delimiter.
        let afterOpenTrimmed = dropLeadingNewline(afterOpen)

        // Find the closing delimiter: a line that is exactly "---".
        guard let close = findClosingDelimiter(in: afterOpenTrimmed) else {
            throw FrontmatterError.unterminatedFrontmatter
        }

        let header = String(afterOpenTrimmed[afterOpenTrimmed.startIndex..<close.delimiterStart])
        var content = String(afterOpenTrimmed[close.contentStart...])
        // Strip exactly one leading newline between the closing "---" and content.
        content = dropLeadingNewline(content)

        // Parse header lines.
        var id: String?
        var createdRaw: String?
        var updatedRaw: String?
        var tags: [String] = []
        var pinned = false
        var presentation = NotePresentation()
        var extra: [String] = []
        var extraBlink: [String] = []

        // The header ends with the newline before the closing "---"; drop the
        // phantom empty element that trailing newline produces on split.
        var headerLines = header.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if header.hasSuffix("\n") || header.isEmpty {
            headerLines = Array(headerLines.dropLast())
        }

        var index = 0
        while index < headerLines.count {
            let line = headerLines[index]
            index += 1
            // Blink's own keys are only recognized at the top level: an indented
            // line is a continuation of someone else's block, never ours.
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
            guard !isIndented, let colon = line.firstIndex(of: ":") else {
                extra.append(line)
                continue
            }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "id":
                id = value
            case "created":
                createdRaw = value
            case "updated":
                updatedRaw = value
            case "tags":
                tags = parseTags(value)
            case "pinned":
                pinned = (value.lowercased() == "true")
            case "blink" where value.isEmpty:
                // The `blink:` presentation block: consume the immediately
                // following indented lines and parse the ones we own; anything
                // unknown or unparseable is preserved verbatim (never-erase).
                var block: [String] = []
                while index < headerLines.count,
                      headerLines[index].hasPrefix(" ") || headerLines[index].hasPrefix("\t") {
                    block.append(headerLines[index])
                    index += 1
                }
                parseBlinkBlock(block, into: &presentation, unknown: &extraBlink)
            default:
                extra.append(line) // not ours — preserve verbatim
            }
        }

        guard let id, !id.isEmpty else {
            throw FrontmatterError.missingField("id")
        }
        guard let createdRaw, let createdAt = parseDate(createdRaw) else {
            throw FrontmatterError.invalidDate(field: "created")
        }
        guard let updatedRaw, let updatedAt = parseDate(updatedRaw) else {
            throw FrontmatterError.invalidDate(field: "updated")
        }

        return Note(
            id: id,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: tags,
            pinned: pinned,
            presentation: presentation,
            extraFrontmatter: extra,
            extraBlink: extraBlink
        )
    }

    /// Parse the indented lines of a `blink:` block. Known scalar keys are typed
    /// into `presentation`; an empty value, an unknown key, or a value that fails
    /// to parse as its type is left verbatim in `unknown` (indentation intact) so
    /// it round-trips and is simply ignored for rendering.
    private static func parseBlinkBlock(
        _ lines: [String],
        into presentation: inout NotePresentation,
        unknown: inout [String]
    ) {
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else {
                unknown.append(raw)
                continue
            }
            let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = unquote(
                String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            )
            guard !value.isEmpty else { unknown.append(raw); continue }
            switch key {
            case "workspace": presentation.workspace = value
            case "style": presentation.style = value
            case "sheet": presentation.sheet = value
            case "accent": presentation.accent = value
            case "font": presentation.font = value
            case "fontSize": if let d = Double(value) { presentation.fontSize = d } else { unknown.append(raw) }
            case "lineHeight": if let d = Double(value) { presentation.lineHeight = d } else { unknown.append(raw) }
            case "tint": if let d = Double(value) { presentation.tint = d } else { unknown.append(raw) }
            case "tintRead": if let d = Double(value) { presentation.tintRead = d } else { unknown.append(raw) }
            case "tintEdit": if let d = Double(value) { presentation.tintEdit = d } else { unknown.append(raw) }
            case "radius": if let d = Double(value) { presentation.radius = d } else { unknown.append(raw) }
            case "slot": if let i = Int(value) { presentation.slot = i } else { unknown.append(raw) }
            case "lastWriter": presentation.lastWriter = value
            default: unknown.append(raw)
            }
        }
    }

    // MARK: - Helpers

    private static func parseDate(_ raw: String) -> Date? {
        if let d = makeFormatter().date(from: raw) { return d }
        // Tolerate timestamps without fractional seconds.
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }

    /// Strip one layer of matching surrounding quotes (single or double).
    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, let first = s.first, let last = s.last else { return s }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    /// Quote a `blink:` scalar value when a bare form would be ambiguous — a
    /// leading `#` (YAML comment), an embedded `:` or `#`, or edge whitespace.
    private static func quoteIfNeeded(_ v: String) -> String {
        let needsQuote = v.isEmpty
            || v.hasPrefix("#") || v.hasPrefix(" ") || v.hasSuffix(" ")
            || v.contains(":") || v.contains("#")
        return needsQuote ? "\"\(v)\"" : v
    }

    /// Render a Double without a trailing `.0` (so `11.0` → `11`, `1.4` → `1.4`).
    private static func formatDouble(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }

    private static func parseTags(_ raw: String) -> [String] {
        var s = raw
        if s.hasPrefix("[") { s.removeFirst() }
        if s.hasSuffix("]") { s.removeLast() }
        return s
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Remove a single leading `\n` (or `\r\n`) if present.
    private static func dropLeadingNewline(_ s: String) -> String {
        if s.hasPrefix("\r\n") { return String(s.dropFirst(2)) }
        if s.hasPrefix("\n") { return String(s.dropFirst()) }
        return s
    }

    private struct ClosingDelimiter {
        /// Index in the source string where the delimiter line begins.
        let delimiterStart: String.Index
        /// Index just past the closing "---" line's delimiter text.
        let contentStart: String.Index
    }

    /// Scan `body` (frontmatter header + content, with the opening delimiter/newline
    /// already removed) for a line consisting exactly of "---".
    private static func findClosingDelimiter(in body: String) -> ClosingDelimiter? {
        var lineStart = body.startIndex
        while true {
            let lineEnd = body[lineStart...].firstIndex(of: "\n") ?? body.endIndex
            var line = body[lineStart..<lineEnd]
            if line.hasSuffix("\r") { line = line.dropLast() }
            if line == "---" {
                // contentStart is right after the "---" delimiter text (before any
                // trailing newline), so the caller strips exactly one newline.
                return ClosingDelimiter(delimiterStart: lineStart, contentStart: lineEnd)
            }
            if lineEnd == body.endIndex { return nil }
            lineStart = body.index(after: lineEnd)
        }
    }
}
