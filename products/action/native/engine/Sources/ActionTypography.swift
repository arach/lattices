import AppKit
import CoreText
import Foundation
import SwiftUI

/// Action's type scale.
///
/// Three families, and only three:
///
/// - **Mono — JetBrains Mono.** The house monospace across Talkie, Scout and
///   Lattices, so a number or a command reads the same wherever it appears. It
///   is not a system font, so every call falls back to the platform monospace
///   when it is missing rather than silently landing on something else.
/// - **Editorial — Charter**, falling back to New York via `.serif`. It sets
///   exactly one thing: the sentence on the status card that says whether
///   anyone is driving this Mac. That is the app's voice, not its chrome, and
///   it is the only place the face is large enough to read as a choice rather
///   than as "a different font". Page titles, row titles and captions are all
///   sans; a theme can drop the face entirely with `"editorial": "none"`.
/// - **UI — SF Pro**, via `.system`. The rest of macOS, and the right default
///   for anything the operator reads as chrome rather than as content.
///
/// The named roles below are the whole scale. Reaching past them for an ad-hoc
/// `.system(size:)` is how a surface ends up with ten sizes that are each two
/// points apart and none of which mean anything.
///
/// The families and the overall scale come from the installed theme, so a theme
/// meant for a recording can set `"type": {"scale": 1.15}` and open the whole
/// app up by one step without any layout code learning a new number.
enum ActionType {
    // MARK: Roles

    /// The one sentence a panel exists to say, and the only editorial line in
    /// the app. See the family note above for why it is the only one.
    static var panelLead: Font { scale.panelLead }
    /// Row titles that are literally code (a calculator expression, a verb).
    static var bodyMono: Font { scale.bodyMono }

    /// A number meant to be read across the room: the elapsed clock.
    static var display: Font { scale.display }
    /// Commands, counts, durations, timestamps.
    static var code: Font { scale.code }
    /// The same size, for numbers that should sit on the digit grid.
    static var meta: Font { scale.meta }
    /// Eyebrows, chips, column headers. Always paired with `labelTracking`.
    static var label: Font { scale.label }
    /// Unemphasised twin of `label`, for values beside a label.
    static var labelRegular: Font { scale.labelRegular }

    // MARK: UI — SF Pro
    //
    // The scale this file's own warning said would be needed, and was not
    // there: the sans had no named roles at all, so 163 call sites picked their
    // own size and the app ended up with fifteen of them between 7 and 22
    // points, most a single point apart. Seven roles replace thirty-one
    // combinations.
    //
    // Sizes are stated once here and nowhere else. A view that needs a size
    // this scale does not have is describing a role the app does not have.

    /// The one line a page opens with, when the page's whole job is to name a
    /// single thing. Light, because at this size weight is not what makes a
    /// line read — size already did that, and light lets the counters open up
    /// and the negative tracking close the words into a single shape. Pair it
    /// with `headlineTracking`, and set it in full ink: presence here comes
    /// from scale and contrast, never from mass.
    static var uiHeadline: Font { .system(size: sized(34), weight: .light) }
    /// The largest sans in the app: a page that wants to open with a statement.
    ///
    /// Medium, not semibold, and tracked in. Past about 20pt SF Pro's semibold
    /// starts to read as emphasis rather than as scale — the size is already
    /// doing that job, and the extra weight only coarsens the letterforms.
    /// Lighter and tighter is where the elegance is.
    static var uiDisplay: Font { .system(size: sized(28), weight: .medium) }
    /// Page and section titles. The one heading size in the chrome.
    ///
    /// Regular, not medium. A page title sits directly under its eyebrow, and
    /// the eyebrow is mono, uppercase and tracked — the contrast between the
    /// two faces is what separates them, so the title does not also need extra
    /// weight to be found. At 22pt regular the line is quieter and sharper, and
    /// nothing else on the page has to get heavier to keep up with it.
    static var uiTitle: Font { .system(size: sized(22), weight: .regular) }
    /// Panel headings inside a page.
    static var uiSubhead: Font { .system(size: sized(15), weight: .semibold) }
    /// Navigation and other chrome the eye scans rather than reads. Medium at
    /// rest and medium when selected: swapping to semibold on selection changes
    /// the string's width, which nudges everything after it by a pixel or two
    /// every time you change page. Colour carries the state instead.
    static var uiNav: Font { .system(size: sized(13), weight: .medium) }
    /// Emphasised body: row titles, control labels, anything that leads a line.
    static var uiBodyStrong: Font { .system(size: sized(13), weight: .semibold) }
    /// Content rows: a line the operator reads as the thing itself — a step in
    /// a plan, a take in the library — rather than as chrome around it.
    ///
    /// The app had no role here, so content borrowed `uiBody`, and `uiBody` is
    /// a settings-pane size. A row of real content set at 12pt beside a 9pt
    /// mono column header is the shape of a preferences window, not of a page
    /// you came to read.
    static var uiRow: Font { .system(size: sized(13)) }
    /// Body. The default for a sentence the operator reads as chrome.
    static var uiBody: Font { .system(size: sized(12)) }
    /// Emphasised supporting text: chips, badges, column headers.
    static var uiCaptionStrong: Font { .system(size: sized(11), weight: .semibold) }
    /// Supporting text.
    static var uiCaption: Font { .system(size: sized(11)) }
    /// The smallest text the app sets. Semibold because at 10pt regular is mush.
    static var uiMicro: Font { .system(size: sized(10), weight: .semibold) }

    // MARK: Mono — JetBrains

    /// Numbers and code that line up in a column.
    static var monoCaption: Font { scale.code }
    /// Body-weight mono: a command, an expression, a value read as text.
    static var monoBody: Font { scale.monoBody }
    /// Emphasised mono: the value a row is about.
    static var monoBodyStrong: Font { scale.monoBodyStrong }

    /// The themed monospace at an arbitrary size.
    ///
    /// For the handful of places that genuinely compute a size — a readout that
    /// shrinks as its digits grow, a caption sized to its own thumbnail. Not an
    /// escape hatch: a fixed size that is not in the roles above is a role the
    /// app has not named yet.
    ///
    /// It exists at all because `.system(design: .monospaced)` is *not* this
    /// app's monospace. That call gets SF Mono, so fifty-five sites claiming to
    /// be "the house mono" were quietly setting a different face from the one
    /// beside them, and none of them scaled with the theme.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        ActionTypeScale.current.mono(size, weight)
    }

    /// Type scales with the theme; a hard-coded point size would not.
    private static func sized(_ size: CGFloat) -> CGFloat {
        (size * min(max(ActionThemePalette.type.scale, 0.85), 1.3)).rounded()
    }

    /// Tracking for `label`. Small mono caps close up without it; this is the
    /// value at which the letters read as a set rather than a word.
    static let labelTracking: CGFloat = 0.9
    /// The page eyebrow sits alone above the title and can carry more air.
    static let eyebrowTracking: CGFloat = 1.3
    /// Large type is set loose by default. SF Pro's metrics are tuned for
    /// running text at reading sizes; at 22pt and up the same spacing leaves
    /// the words looking slack, so headings are drawn back in. Negative
    /// tracking is the cheapest elegance in the whole scale.
    static let titleTracking: CGFloat = -0.25
    static let displayTracking: CGFloat = -0.5
    /// `uiHeadline`. Tighter again: the bigger the line, the more air the
    /// default spacing leaves between letters, and closing it is what turns a
    /// row of words into one object.
    static let headlineTracking: CGFloat = -0.7

    /// The resolved monospace family, or nil when the app is falling back to the
    /// platform monospace. Exposed for diagnostics.
    static var monoFamily: String? { scale.monoFamily }
    /// The resolved editorial family, or nil when falling back to New York.
    static var editorialFamily: String? { scale.editorialFamily }

    private static var scale: ActionTypeScale { ActionTypeScale.current }
}

/// One resolved scale.
///
/// Font resolution is not free — `NSFont(name:)` plus a descriptor rebuild for
/// the ligature settings, eleven times — and the roles are read on every label
/// of every row. So a scale is built once per distinct `ActionThemeType` and
/// then handed out.
private final class ActionTypeScale: @unchecked Sendable {
    let monoFamily: String?
    let editorialFamily: String?
    let typeScale: CGFloat

    let panelLead: Font
    let bodyMono: Font
    let monoBody: Font
    let monoBodyStrong: Font
    let display: Font
    let code: Font
    let meta: Font
    let label: Font
    let labelRegular: Font

    init(_ type: ActionThemeType) {
        monoFamily = Self.resolveMono(requested: type.monoFamily)
        editorialFamily = Self.resolveEditorial(requested: type.editorialFamily)

        let scale = min(max(type.scale, 0.85), 1.3)
        typeScale = scale
        let mono = monoFamily
        let editorial = editorialFamily

        func monoFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            Self.mono(family: mono, size: (size * scale).rounded(), weight: weight)
        }
        func editorialFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            Self.editorial(family: editorial, size: (size * scale).rounded(), weight: weight)
        }

        panelLead = editorialFont(21)
        bodyMono = monoFont(14)
        monoBody = monoFont(12)
        monoBodyStrong = monoFont(13, .semibold)
        display = monoFont(26, .medium)
        code = monoFont(11)
        meta = monoFont(11)
        label = monoFont(9, .semibold)
        labelRegular = monoFont(9)
    }

    /// The themed face at an arbitrary size, honouring the theme's scale and
    /// the same ligature suppression as the named roles.
    func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        Self.mono(family: monoFamily, size: (size * typeScale).rounded(), weight: weight)
    }

    // MARK: Cache

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedKey: ActionThemeType?
    nonisolated(unsafe) private static var cached: ActionTypeScale?

    static var current: ActionTypeScale {
        let type = ActionThemePalette.type
        lock.lock()
        defer { lock.unlock() }
        if let cached, cachedKey == type {
            return cached
        }
        let scale = ActionTypeScale(type)
        cached = scale
        cachedKey = type
        return scale
    }

    // MARK: Resolution

    private static func resolveMono(requested: String?) -> String? {
        var candidates: [String] = []
        if let requested, !requested.isEmpty, requested.lowercased() != "system" {
            candidates.append(requested)
        }
        candidates.append(contentsOf: ["JetBrains Mono", "JetBrainsMono-Regular", "JetBrainsMonoNL-Regular"])
        return candidates.first { NSFont(name: $0, size: 12) != nil }
    }

    /// Sentinel for "no editorial face at all" — the two display roles fall
    /// back to SF Pro rather than to New York. A theme that wants nothing
    /// bookish anywhere says `"type": {"editorial": "none"}`.
    static let noEditorialFace = "none"

    /// Still honours `defaults write dev.lattices.Action ActionEditorialFont
    /// "<family>"` so the choice can be judged in the real UI rather than in a
    /// specimen. The default write wins over the theme, because it exists for
    /// exactly that kind of one-off comparison.
    private static func resolveEditorial(requested: String?) -> String? {
        let override = UserDefaults.standard.string(forKey: "ActionEditorialFont")
        let name = override ?? requested
        guard let name, !name.isEmpty else { return nil }
        if name.lowercased() == noEditorialFace { return noEditorialFace }
        guard name.lowercased() != "system", NSFont(name: name, size: 12) != nil else {
            return nil
        }
        return name
    }

    // MARK: Faces

    /// `fixedSize` on purpose: this is an operator console with alignment that
    /// depends on the grid holding, not body copy that should track Dynamic Type.
    ///
    /// Ligatures are turned off. JetBrains Mono ships them on, and it renders the
    /// `--` in `-- bun --cwd` as a single long dash — in a command the operator
    /// is meant to read and retype, that is a wrong character on screen, not a
    /// stylistic flourish.
    private static func mono(family: String?, size: CGFloat, weight: Font.Weight) -> Font {
        guard let family, let base = NSFont(name: family, size: size) else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector,
                ],
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kRareLigaturesOffSelector,
                ],
            ],
        ])
        guard let resolved = NSFont(descriptor: descriptor, size: size) else {
            return .custom(family, fixedSize: size).weight(weight)
        }
        return Font(resolved).weight(weight)
    }

    private static func editorial(family: String?, size: CGFloat, weight: Font.Weight) -> Font {
        guard let family else {
            return .system(size: size, weight: weight, design: .serif)
        }
        if family == ActionTypeScale.noEditorialFace {
            return .system(size: size, weight: .semibold)
        }
        return .custom(family, fixedSize: size).weight(weight)
    }
}

/// Glyph sizes for SF Symbols.
///
/// Deliberately separate from the type scale. An icon's point size sets its
/// drawn height, not a cap height, so folding icons into text roles snaps a
/// 22pt empty-state glyph to the same value as a 22pt heading and makes both
/// wrong. Five steps, matched to what the app actually draws.
enum ActionIcon {
    /// Inline markers inside a chip or a row.
    static var micro: Font { .system(size: 9, weight: .semibold) }
    /// Row and control glyphs.
    static var small: Font { .system(size: 11, weight: .medium) }
    /// The default: sidebar items, settings rows, toolbar buttons.
    static var medium: Font { .system(size: 13, weight: .medium) }
    /// Section and page-header glyphs.
    static var large: Font { .system(size: 17, weight: .medium) }
    /// Empty-state glyphs, which are drawn light because they are decoration
    /// standing in for content that is not there yet.
    static var display: Font { .system(size: 22, weight: .light) }
}
