import SwiftUI

// MARK: - DeckTheme
//
// The single token layer for the iPad companion. Replaces `LatsPalette`/`LatsFont`
// and `FleetV6`, which had drifted into two design systems with near-miss values
// (amber #F5BD5C vs #E4B65C, green #6EDB8C vs #81DD85) that read as a mistake
// rather than a choice.
//
// Spec: design/fleet-deck/token-spec-v7.md
// Brief: "full font sizes, smaller is better, fewest possible colors,
//         no mono / technical vibe across the board"
//
// The governing idea: this app operates *agents*, dictation, and the Mac's
// window surface — it is a remote control, not a terminal. Remote controls
// should look like the OS they live on, not like the thing they point at.

enum DeckTheme {

    // MARK: - Surfaces
    //
    // Five levels, all opaque, ~4-5% luminance apart. `well` and `card` sit
    // either side of `canvas`: that pair *is* the depth model — down for a
    // group, up for an item, nothing in between. If two adjacent surfaces don't
    // need a visible seam, they are the same level. Do not invent a sixth.

    /// Root background. Everything sits on this.
    static let canvas = adaptive(light: 0xF1F1EC, dark: 0x0D0F12)

    /// Recessed group — channel strip, activity screen, voice bar. Depth −1.
    static let well = adaptive(light: 0xE9E9E3, dark: 0x0A0B0D)

    /// Flush item — cards, tiles, list rows. Depth +1.
    static let card = adaptive(light: 0xFAFAF7, dark: 0x131518)

    /// Focused/hero console, popovers, sheets. Reserved; never an ordinary card.
    static let raised = adaptive(light: 0xFFFFFF, dark: 0x181B1F)

    /// Anything tappable inside a card — buttons, inputs, chips.
    static let control = adaptive(light: 0xE5E5DE, dark: 0x1E2126)

    // MARK: - Text
    //
    // Four opaque greys, carried over from v6 unchanged. Opaque rather than
    // white-at-opacity so a label reads the same on `well` as on `raised`, and
    // warm-neutral so the amber doesn't vibrate against it.

    static let text          = adaptive(light: 0x1C1C19, dark: 0xE2E2DF)
    static let textSecondary = adaptive(light: 0x585850, dark: 0xA0A09B)
    static let textTertiary  = adaptive(light: 0x8B8B83, dark: 0x71716C)
    static let textDisabled  = adaptive(light: 0xB9B9B1, dark: 0x4A4A4D)

    // MARK: - Hairlines
    //
    // Two, and mostly forbidden. Not between a well and the canvas (spacing
    // carries the recess), not between sections inside one card, not under card
    // heads. No dotted rules, no black seams.

    /// Stroke on a flush card; row separator only when the gap is under 8pt.
    static let hairline = adaptive(light: 0x000000, dark: 0xFFFFFF, alphaLight: 0.08, alphaDark: 0.08)

    /// Focused / selected / recently-changed. The only "look at me" that is not amber.
    static let hairlineStrong = adaptive(light: 0x000000, dark: 0xFFFFFF, alphaLight: 0.14, alphaDark: 0.14)

    // MARK: - Accent
    //
    // Two hues for the whole app. Attention and selection share one, because
    // they share a meaning: look here.

    static let accent        = adaptive(light: 0xB3822A, dark: 0xE4B65C)
    static let accentPressed = adaptive(light: 0x96691F, dark: 0xC29B4E)
    static let accentFill    = adaptive(light: 0xB3822A, dark: 0xE4B65C, alphaLight: 0.16, alphaDark: 0.14)
    static let accentDisabled = adaptive(light: 0xB3822A, dark: 0xE4B65C, alphaLight: 0.35, alphaDark: 0.35)

    static let error        = adaptive(light: 0xC94F4A, dark: 0xEA6A64)
    static let errorPressed = adaptive(light: 0xA8403B, dark: 0xC85A55)
    static let errorFill    = adaptive(light: 0xC94F4A, dark: 0xEA6A64, alphaLight: 0.14, alphaDark: 0.14)

    // MARK: - Radii

    static let radiusSmall: CGFloat = 4   // chips, badges
    static let radiusCard:  CGFloat = 8   // cards, tiles, controls
    static let radiusWell:  CGFloat = 12  // wells, panels, sheets

    // MARK: - Spacing (8pt grid)

    enum Space {
        static let x2:  CGFloat = 2
        static let x4:  CGFloat = 4
        static let x8:  CGFloat = 8
        static let x12: CGFloat = 12
        static let x16: CGFloat = 16
        static let x24: CGFloat = 24
        static let x32: CGFloat = 32

        /// Screen margin.
        static let margin: CGFloat = 16
        /// Card interior — the 14 is v6's own vertical rhythm, kept.
        static let cardPadH: CGFloat = 16
        static let cardPadV: CGFloat = 14
        /// Inside a recessed well.
        static let wellPad: CGFloat = 12
        /// Between sibling cards.
        static let cardGap: CGFloat = 8
        /// Between sections within one card.
        static let sectionGap: CGFloat = 12
        /// Icon to its label.
        static let iconGap: CGFloat = 8
    }

    // MARK: - Type
    //
    // Two faces, split by *who is speaking* rather than by data shape.
    //
    // SF Pro is the system voice: every label, name, value, and control. No
    // tracking, no uppercase — size and weight carry the emphasis that 9pt
    // tracked caps used to fake.
    //
    // The serif is the communication voice, and only that: an agent's question,
    // a voice transcript, an agent's message. It marks *someone is talking to
    // you*, which on a surface whose signature state is an agent blocked on a
    // human is worth a face of its own.

    /// Console names, sheet titles, the thing you would tap.
    static func title(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 17, weight: weight)
    }

    /// Primary rows, channel names, input text.
    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 15, weight: weight)
    }

    /// Metadata, descriptions, the activity narrative.
    static func secondary(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 13, weight: weight)
    }

    /// Timestamps, status words, and everything the tracked micro-caps used to do.
    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight)
    }

    /// An agent asking you something.
    static let said = Font.system(size: 17, design: .serif)

    /// Voice transcript and agent message bodies.
    static let saidSecondary = Font.system(size: 15, design: .serif)

    // MARK: - Helpers

    static func rgb(_ hex: UInt32) -> Color {
        Color(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
    /// A light/dark pair. Dark keeps the v7 values untouched; light mirrors
    /// the depth model — `well` recessed below `canvas`, `card` floating
    /// above — in warm-neutral steps so the amber doesn't vibrate.
    static func adaptive(light: UInt32, dark: UInt32, alphaLight: Double = 1, alphaDark: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let darkMode = traits.userInterfaceStyle == .dark
            let hex = darkMode ? dark : light
            return UIColor(
                red:   CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue:  CGFloat(hex & 0xFF) / 255,
                alpha: darkMode ? alphaDark : alphaLight
            )
        })
    }
}
// MARK: - Appearance

/// System / Dark / Light for the whole companion. Stored as a raw string in
/// UserDefaults; read with `@AppStorage(DeckAppearanceMode.storageKey)` and
/// applied once at the root via `.preferredColorScheme`.
enum DeckAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    static let storageKey = "deck.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}

// MARK: - State presentation
//
// Running is the default healthy condition, so running looks like *nothing*.
// Health is the absence of signal — which is what stops the deck reading as a
// status board where everything is lit and therefore nothing is.

extension DeckTheme {
    /// How a channel's state renders. `nil` dot means draw no dot at all.
    struct StatePresentation {
        var dotFill: Color?
        var dotStroke: Color?
        var glows: Bool
        var label: Color
        var rowFill: Color?
    }

    static func presentation(running: Bool) -> StatePresentation {
        StatePresentation(
            dotFill: nil, dotStroke: nil, glows: false,
            label: running ? text : textTertiary, rowFill: nil
        )
    }

    static var idlePresentation: StatePresentation {
        // Hollow dot, demoted row. Present but not asking for anything.
        StatePresentation(
            dotFill: nil, dotStroke: textTertiary, glows: false,
            label: textTertiary, rowFill: nil
        )
    }

    static var attentionPresentation: StatePresentation {
        // The one place colour is spent. Never amber the whole row.
        StatePresentation(
            dotFill: accent, dotStroke: nil, glows: true,
            label: text, rowFill: nil
        )
    }

    static var errorPresentation: StatePresentation {
        StatePresentation(
            dotFill: error, dotStroke: nil, glows: false,
            label: text, rowFill: errorFill
        )
    }
}
