import Foundation

/// The typed view of a note's `blink:` frontmatter block — the presentation and
/// placement *intent* Blink owns (see `docs/notes-representation.md` Appendix A).
/// Every field is optional; an absent field means "inherit the config default".
/// Loose overrides here win over a named `style`, which wins over config.
///
/// The codec types only *valid* scalars into these fields. An unparseable value
/// (a non-numeric `slot`, say) is never coerced or dropped — it is preserved
/// verbatim in `Note.extraBlink` and simply not surfaced here (never-erase).
public struct NotePresentation: Equatable, Sendable, Codable {
    /// The workspace this note belongs to — a name defined in `config.json` →
    /// `workspaces.<name>`. Membership only: the brand itself never enters the
    /// markdown, so the file stays portable and presentation-free. An unknown
    /// or absent name renders unbranded.
    public var workspace: String?
    /// Named treatment defined in `config.json` → `styles.<name>`.
    public var style: String?
    /// Sheet template: glass | card | dotted | bracket | marginalia.
    public var sheet: String?
    /// Accent color, e.g. `#d08770` (quoted in the file — a bare `#…` is a comment).
    public var accent: String?
    /// Editor font family override.
    public var font: String?
    public var fontSize: Double?
    public var lineHeight: Double?
    /// Shorthand tint; the app applies it to read+edit when the pair is unset.
    public var tint: Double?
    public var tintRead: Double?
    public var tintEdit: Double?
    /// Panel corner radius.
    public var radius: Double?
    /// Durable grid-slot intent, 1...9 (not pixels — pixels are device state).
    public var slot: Int?
    /// Last known writer for display. Overwritten on each attributed write.
    /// Full history lives in `edits.sqlite`, not here.
    public var lastWriter: String?

    public init() {}

    /// True when no field is set — nothing for the codec to emit.
    public var isEmpty: Bool {
        workspace == nil && style == nil && sheet == nil && accent == nil && font == nil
            && fontSize == nil && lineHeight == nil && tint == nil
            && tintRead == nil && tintEdit == nil && radius == nil && slot == nil
            && lastWriter == nil
    }

}

/// A single note. The `id` is the slug identity (see `Slug`), the `content` is the
/// raw markdown body *without* any frontmatter block. `title` is derived from the
/// content and never stored separately.
public struct Note: Equatable, Sendable, Codable {
    public var id: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String]
    public var pinned: Bool
    /// Blink's presentation & placement intent (the `blink:` block).
    public var presentation: NotePresentation
    /// Frontmatter lines Blink does not own (agent- or tool-authored keys like
    /// `source:` or `x-*:`), kept verbatim in their original order so a
    /// decode → edit → encode cycle never destroys another tool's metadata.
    public var extraFrontmatter: [String]
    /// Sub-lines of the `blink:` block Blink does not recognize (a future or
    /// invalid key), kept verbatim and indented so they round-trip untouched.
    public var extraBlink: [String]

    public init(
        id: String,
        content: String,
        createdAt: Date,
        updatedAt: Date,
        tags: [String] = [],
        pinned: Bool = false,
        presentation: NotePresentation = NotePresentation(),
        extraFrontmatter: [String] = [],
        extraBlink: [String] = []
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.pinned = pinned
        self.presentation = presentation
        self.extraFrontmatter = extraFrontmatter
        self.extraBlink = extraBlink
    }

    /// The display title, derived from the content.
    public var title: String {
        Note.extractTitle(from: content)
    }

    /// Read a scalar value from the note's foreign frontmatter lines
    /// (`extraFrontmatter`) — e.g. `sheet: dotted` or `source: agent://x`.
    /// Only top-level (unindented) `key: value` lines match.
    public func extraFrontmatterValue(for key: String) -> String? {
        for line in extraFrontmatter {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"),
                  let colon = line.firstIndex(of: ":"),
                  line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces) == key
            else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Extract a display title from markdown content.
    ///
    /// Rules (ported from v1 `extractTitleFromContent`, extended per the v2 spec):
    /// 1. Use the first non-empty line.
    /// 2. Strip a leading blockquote marker (`>`).
    /// 3. Strip leading heading markers (`#`).
    /// 4. Strip a leading list marker (`-`, `*`, `+`, or numbered like `1.`).
    /// 5. Strip surrounding/leading bold, italic (`**`, `__`, `*`, `_`).
    /// 6. Strip inline backticks.
    /// 7. Trim whitespace and cap at 50 characters.
    /// 8. Empty content (or nothing left) → "Untitled".
    public static func extractTitle(from content: String) -> String {
        let fallback = "Untitled"
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }

        // First non-empty (non-whitespace-only) line.
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard var title = firstLine.map({ String($0).trimmingCharacters(in: .whitespaces) }),
              !title.isEmpty
        else {
            return fallback
        }

        // Strip a leading blockquote marker (possibly repeated, e.g. "> > ").
        while title.hasPrefix(">") {
            title.removeFirst()
            title = title.trimmingCharacters(in: .whitespaces)
        }

        // Strip leading heading markers.
        title = stripLeadingPrefix(title, pattern: "^#+\\s*")

        // Strip a leading list marker: bullet (-, *, +) or numbered (1. / 1) ).
        title = stripLeadingPrefix(title, pattern: "^([-*+]|\\d+[.)])\\s+")

        // Strip surrounding bold/italic emphasis, then any leftover leading markers.
        title = stripEmphasis(title)

        // Strip inline backticks entirely.
        title = title.replacingOccurrences(of: "`", with: "")

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 50 {
            title = String(title.prefix(50))
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? fallback : title
    }

    /// Remove wrapping emphasis (`**...**`, `__...__`, `*...*`, `_..._`) and any
    /// leading emphasis markers that remain unbalanced.
    private static func stripEmphasis(_ input: String) -> String {
        var s = input
        // Wrapping pairs, strongest first.
        let wraps = ["**", "__", "*", "_"]
        var changed = true
        while changed {
            changed = false
            for marker in wraps {
                if s.count > marker.count * 2,
                   s.hasPrefix(marker), s.hasSuffix(marker) {
                    s.removeFirst(marker.count)
                    s.removeLast(marker.count)
                    s = s.trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
        }
        // Leading-only markers (e.g. "*Note without close").
        s = stripLeadingPrefix(s, pattern: "^(\\*\\*|__|\\*|_)+\\s*")
        return s
    }

    /// Remove a leading regex match from `input`.
    private static func stripLeadingPrefix(_ input: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range),
              match.range.location == 0,
              let r = Range(match.range, in: input)
        else {
            return input
        }
        return String(input[r.upperBound...])
    }
}
