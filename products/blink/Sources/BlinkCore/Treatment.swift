import Foundation

/// A named, reusable presentation preset — a *partial* overlay onto the
/// panel/editor defaults, every field optional. Pure data: no AppKit, no
/// rendering opinion, so the app, the CLI, and tests all speak one vocabulary.
///
/// Three things reference a treatment, in ascending precedence:
/// a workspace's brand, a note's `blink.style`, and a note's loose `blink:`
/// overrides. Field → surface mapping lives in `BlinkConfig.apply(treatment:)`;
/// see `docs/notes-representation.md` Appendix A and `docs/workspaces.md`.
///
/// Every field is optional by design: an unset field means "inherit", which is
/// what makes treatments composable and keeps unbranded the default.
public struct Treatment: Codable, Equatable, Sendable {
    // Surface
    /// Sheet template: glass | card | dotted | bracket | marginalia.
    public var sheet: String?
    /// Opaque CSS surface color. Unset keeps the glass sheet transparent.
    public var background: String?
    /// Panel corner radius in px — the corner treatment.
    public var radius: Double?
    /// Glass tint shorthand (0–1); `tintRead`/`tintEdit` win over it.
    public var tint: Double?
    public var tintRead: Double?
    public var tintEdit: Double?

    // Typography
    public var font: String?
    public var mono: String?
    public var titleFont: String?
    public var fontSize: Double?
    public var lineHeight: Double?

    // Palette
    public var text: String?
    public var textStrong: String?
    public var textMuted: String?
    public var dim: String?
    public var border: String?
    public var accent: String?
    public var accentDim: String?
    public var codeBackground: String?
    public var codeText: String?
    public var caret: String?
    public var selection: String?

    // Identity
    /// Relative path under `$BLINK_HOME/attachments` for a restrained identity
    /// mark in the panel's top-left chrome. Never an absolute path — see
    /// `BlinkPaths.attachment(named:)` for the containment rule.
    public var mark: String?

    public init() {}

    /// Decode defensively: a missing key and an explicit `null` both mean
    /// "inherit", so a hand-edited config never fails to load over a blank field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sheet = try c.decodeIfPresent(String.self, forKey: .sheet)
        background = try c.decodeIfPresent(String.self, forKey: .background)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius)
        tint = try c.decodeIfPresent(Double.self, forKey: .tint)
        tintRead = try c.decodeIfPresent(Double.self, forKey: .tintRead)
        tintEdit = try c.decodeIfPresent(Double.self, forKey: .tintEdit)
        font = try c.decodeIfPresent(String.self, forKey: .font)
        mono = try c.decodeIfPresent(String.self, forKey: .mono)
        titleFont = try c.decodeIfPresent(String.self, forKey: .titleFont)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        textStrong = try c.decodeIfPresent(String.self, forKey: .textStrong)
        textMuted = try c.decodeIfPresent(String.self, forKey: .textMuted)
        dim = try c.decodeIfPresent(String.self, forKey: .dim)
        border = try c.decodeIfPresent(String.self, forKey: .border)
        accent = try c.decodeIfPresent(String.self, forKey: .accent)
        accentDim = try c.decodeIfPresent(String.self, forKey: .accentDim)
        codeBackground = try c.decodeIfPresent(String.self, forKey: .codeBackground)
        codeText = try c.decodeIfPresent(String.self, forKey: .codeText)
        caret = try c.decodeIfPresent(String.self, forKey: .caret)
        selection = try c.decodeIfPresent(String.self, forKey: .selection)
        mark = try c.decodeIfPresent(String.self, forKey: .mark)
    }

    /// True when nothing is set — an empty overlay changes no surface.
    public var isEmpty: Bool { self == Treatment() }

    /// Overlay `other`'s set fields onto a copy of this treatment. Used to
    /// compose a workspace's `style` base with its inline `brand` without
    /// either side having to repeat the other's fields.
    public func merging(_ other: Treatment) -> Treatment {
        var t = self
        if let v = other.sheet { t.sheet = v }
        if let v = other.background { t.background = v }
        if let v = other.radius { t.radius = v }
        if let v = other.tint { t.tint = v }
        if let v = other.tintRead { t.tintRead = v }
        if let v = other.tintEdit { t.tintEdit = v }
        if let v = other.font { t.font = v }
        if let v = other.mono { t.mono = v }
        if let v = other.titleFont { t.titleFont = v }
        if let v = other.fontSize { t.fontSize = v }
        if let v = other.lineHeight { t.lineHeight = v }
        if let v = other.text { t.text = v }
        if let v = other.textStrong { t.textStrong = v }
        if let v = other.textMuted { t.textMuted = v }
        if let v = other.dim { t.dim = v }
        if let v = other.border { t.border = v }
        if let v = other.accent { t.accent = v }
        if let v = other.accentDim { t.accentDim = v }
        if let v = other.codeBackground { t.codeBackground = v }
        if let v = other.codeText { t.codeText = v }
        if let v = other.caret { t.caret = v }
        if let v = other.selection { t.selection = v }
        if let v = other.mark { t.mark = v }
        return t
    }
}

/// A **workspace**: a named group of notes plus the brand they render under.
///
/// The definition lives in `config.json` → `workspaces.<name>`; *membership*
/// lives in each note's own frontmatter (`blink.workspace`). That split is the
/// whole design — config holds presentation, the note file holds one portable
/// name, and deleting the definition costs a look, never a note.
public struct Workspace: Codable, Equatable, Sendable {
    /// Human-facing label. Defaults to the workspace name when unset.
    public var title: String?
    /// Optional base: the name of an entry in `config.json` → `styles`, so
    /// several workspaces can share one house style and tint it differently.
    public var style: String?
    /// The workspace's own brand overlay, applied over `style`.
    public var brand: Treatment?

    public init(title: String? = nil, style: String? = nil, brand: Treatment? = nil) {
        self.title = title
        self.style = style
        self.brand = brand
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        brand = try c.decodeIfPresent(Treatment.self, forKey: .brand)
    }

    /// The effective brand: the registered `style` base with `brand` overlaid.
    /// `styles` is the config's style registry; an unknown name contributes
    /// nothing rather than failing — an unbranded workspace is always valid.
    public func resolvedBrand(styles: [String: Treatment]?) -> Treatment {
        let base = style.flatMap { styles?[$0] } ?? Treatment()
        return base.merging(brand ?? Treatment())
    }
}

/// How a note's look is decided. The precedence rule is product logic, not
/// rendering logic, so it lives here where it can be tested without AppKit —
/// `BlinkConfig.resolved(for:)` is a thin loop over this chain.
///
/// Least specific first, so **later wins**:
/// ```
/// config defaults ← workspace brand ← named style ← loose per-note keys
/// ```
/// A note inherits its workspace's identity for free, a per-note `style` can
/// still override the brand, and a loose `blink:` key beats both. An unknown
/// workspace or style name contributes nothing rather than failing, so an
/// unbranded note is always a valid note.
public enum PresentationResolver {
    /// The ordered treatments to overlay onto the config defaults for one note.
    public static func chain(
        for presentation: NotePresentation,
        styles: [String: Treatment]?,
        workspaces: [String: Workspace]?
    ) -> [Treatment] {
        var chain: [Treatment] = []
        if let name = presentation.workspace, let workspace = workspaces?[name] {
            let brand = workspace.resolvedBrand(styles: styles)
            if !brand.isEmpty { chain.append(brand) }
        }
        if let name = presentation.style, let style = styles?[name] {
            chain.append(style)
        }
        let loose = loose(from: presentation)
        if !loose.isEmpty { chain.append(loose) }
        return chain
    }

    /// The whole chain folded into one treatment — what a note effectively
    /// looks like, relative to the config defaults.
    public static func effective(
        for presentation: NotePresentation,
        styles: [String: Treatment]?,
        workspaces: [String: Workspace]?
    ) -> Treatment {
        chain(for: presentation, styles: styles, workspaces: workspaces)
            .reduce(Treatment()) { $0.merging($1) }
    }

    /// A note's loose `blink:` overrides as a treatment. `workspace`, `style`,
    /// and `slot` are excluded: the first two select treatments rather than
    /// being one, and `slot` is placement, not presentation.
    public static func loose(from p: NotePresentation) -> Treatment {
        var t = Treatment()
        t.sheet = p.sheet
        t.accent = p.accent
        t.font = p.font
        t.fontSize = p.fontSize
        t.lineHeight = p.lineHeight
        t.tint = p.tint
        t.tintRead = p.tintRead
        t.tintEdit = p.tintEdit
        t.radius = p.radius
        return t
    }
}
