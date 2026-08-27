import Foundation
import SwiftUI

// MARK: - Tokens
//
// The names the app paints with. This enum is the contract between three
// audiences that were previously reading the same 80 `static let`s and meaning
// different things by them:
//
//   - views, which want a name per role;
//   - theme authors (people and agents), who want to change a *family* without
//     naming 80 things;
//   - the validator, which wants to know which pairs have to stay legible.
//
// A token is never authored directly in a theme file's main body. It is
// produced by a surface, and can then be patched by name through `overrides`.
// The raw values below are exactly the keys an override uses.

/// Every colour the app can paint.
enum ActionToken: String, CaseIterable, Sendable {
    // Chrome — the launcher shell.
    case appBackground
    case railBackground
    case footerBackground
    case panelBackgroundTop
    case panelBackgroundBottom
    case panelBorder
    case panelShadow
    case textPrimary
    case textSecondary
    case textMuted
    case cardFill
    case cardBorder
    case accentIdle
    case buttonPrimaryTop
    case buttonPrimaryBottom
    case buttonSecondary
    case buttonSecondaryHover
    case buttonPrimaryText

    // Status — run outcomes and the ledger washes that carry them.
    case accentRecording
    case accentPaused
    case runOk
    case runRunning
    case runFailed
    case runStopped
    case rowAlternate
    case runSelection
    case runSelectionHover
    case runActionChip

    // Capture HUD — a machined dark material, not a palette.
    case hudCanvas
    case hudPanel
    case hudPanelRaised
    case hudPaper
    case hudInk
    case hudMuted
    case hudGrid
    case hudStroke
    case hudStrokeStrong
    case hudCoral
    case hudCoralHot
    case hudCyan
    case hudAmber
    case hudMetalTop
    case hudMetalEdge
    case hudRecess
    case hudEtch
    case hudShadow
    case hudBevelLight
    case hudBevelHairline
    case hudBevelShadow
    case hudGrain
    case hudGrainDark
    case hudMetalSheen
    case hudMetalCore
    case hudMetalTrough

    // Field — Home, in the brand's own voice.
    case fieldCanvas
    case fieldPanel
    case fieldConsole
    case fieldPanelEdge
    case fieldRule
    case fieldGrid
    case fieldInk
    case fieldInkSecondary
    case fieldInkRow
    case fieldInkMuted
    case fieldInkMeta
    case fieldDeep
    case fieldDeepText
    case fieldDeepMeta
    case fieldDeepEdge
    case fieldDeepChip
    case fieldAccent
    case fieldAccentText
    case fieldSignal

    // Review.
    case reviewCanvas
    case reviewPanel
    case reviewPanelRaised
    case reviewStrokeSoft
    case reviewStrokeStrong
    case reviewAccent
    case reviewAccentMuted

    // Media overlays — plates, edges and ink floating above captured frames.
    // They sit over arbitrary footage, not over a themed ground, so the built-in
    // values are appearance-independent black and white; a theme retints them
    // here or not at all.
    case overlayScrim
    case overlayHairline
    case overlayInk

    /// Dense index into the resolved colour table. `allCases` order.
    var slot: Int {
        Self.slots[self] ?? 0
    }

    private static let slots: [ActionToken: Int] = {
        var map: [ActionToken: Int] = [:]
        for (index, token) in ActionToken.allCases.enumerated() {
            map[token] = index
        }
        return map
    }()
}

// MARK: - Surface

/// One place the app can stand: a ground, the things that sit on it, the lines
/// that divide it, the ink that goes on it, and the two colours it speaks with.
///
/// Action has four of these and they are not variations of each other — Home
/// speaks in paper and graphite, the ledgers in neutral operator chrome, review
/// in a cool sheet, the capture HUD in machined metal. That is the composition
/// the old file was missing: it had 80 flat constants where it had four
/// surfaces, so "make Home warmer" meant finding and editing nineteen of them
/// and hoping none had been missed.
struct ActionSurface: Equatable, Sendable {
    // Grounds, from the page outward.
    /// The page.
    var canvas: ActionThemeColor
    /// A chrome band across an edge of the page: the rail, the title bar, the
    /// footer. One value, because they are one band.
    var band: ActionThemeColor
    /// A card laid on the page.
    var panel: ActionThemeColor
    /// The same card, hovered or one level further up.
    var panelRaised: ActionThemeColor
    /// A well cut *into* the page. Below the canvas where panels are above it,
    /// which is the whole hierarchy: panels are content on the surface, a recess
    /// is a window into the machine's state.
    var recess: ActionThemeColor
    /// The block that stays dark in both appearances, because what it reports is
    /// operational state rather than decoration.
    var deep: ActionThemeColor

    // Lines.
    var edge: ActionThemeColor
    var rule: ActionThemeColor
    /// Texture, not ruling. If it reads as a grid it is too strong.
    var grid: ActionThemeColor
    var shadow: ActionThemeColor

    // Ink, darkest first.
    var ink: ActionThemeColor
    var inkSecondary: ActionThemeColor
    /// Row titles: still the most prominent thing on their line without
    /// printing as black.
    var inkRow: ActionThemeColor
    /// An accent voice rather than a demotion — the editorial aside beside a
    /// panel label. Not for numbers.
    var inkMuted: ActionThemeColor
    /// Numeric metadata: durations, timestamps, counts. Genuinely quiet, so a
    /// row reads title-first.
    var inkMeta: ActionThemeColor
    var onDeep: ActionThemeColor
    var onDeepMeta: ActionThemeColor

    // Voice.
    /// Runtime truth: something is happening to this Mac right now.
    var accent: ActionThemeColor
    /// What goes on top of the accent.
    var accentInk: ActionThemeColor
    var accentSoft: ActionThemeColor
    /// The secondary signal. Never competes with the accent.
    var signal: ActionThemeColor
}

// MARK: - Seeds

/// The seven decisions a surface actually rests on.
///
/// This is the agent-facing shape. Handing an agent 21 slots invites 21
/// independent guesses and a surface that does not hold together; handing it a
/// ground, an ink and an accent produces a surface whose separations were
/// computed rather than guessed, and whose contrast can then be checked.
///
/// Anything the derivation gets wrong for a particular surface is fixed with a
/// token override, which is a deliberate, named exception rather than the
/// default way to work.
struct ActionSurfaceSeed: Equatable, Sendable, Codable {
    /// The page.
    var ground: ActionThemeColor
    /// The darkest text that goes on it.
    var ink: ActionThemeColor
    /// Runtime truth.
    var accent: ActionThemeColor
    /// The secondary signal. Defaults to a desaturated step off the accent.
    var signal: ActionThemeColor?
    /// The dark block. Defaults to a warmed, deepened ink.
    var deep: ActionThemeColor?
    /// How far apart the grounds sit. 1.0 is Action's own separation; below 1
    /// flattens the surface, above 1 makes panels read as cards on a tray.
    var lift: Double

    init(
        ground: ActionThemeColor,
        ink: ActionThemeColor,
        accent: ActionThemeColor,
        signal: ActionThemeColor? = nil,
        deep: ActionThemeColor? = nil,
        lift: Double = 1
    ) {
        self.ground = ground
        self.ink = ink
        self.accent = accent
        self.signal = signal
        self.deep = deep
        self.lift = lift
    }

    private enum CodingKeys: String, CodingKey {
        case ground, ink, accent, signal, deep, lift
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ground = try container.decode(ActionThemeColor.self, forKey: .ground)
        ink = try container.decode(ActionThemeColor.self, forKey: .ink)
        accent = try container.decode(ActionThemeColor.self, forKey: .accent)
        signal = try container.decodeIfPresent(ActionThemeColor.self, forKey: .signal)
        deep = try container.decodeIfPresent(ActionThemeColor.self, forKey: .deep)
        lift = try container.decodeIfPresent(Double.self, forKey: .lift) ?? 1
    }

    /// Grows a full surface out of the seed.
    ///
    /// The steps below were measured off Action's own palette, so seeding with
    /// Action's paper and graphite lands within a point or two of the shipped
    /// surface in both appearances. They are stated as *moves* rather than as
    /// values, which is what makes a new ground produce a coherent surface
    /// instead of a set of unrelated colours:
    ///
    /// - grounds are L\* steps off the page — a panel is three points lighter,
    ///   a recess two and a bit darker, a chrome band three darker — so the same
    ///   rule holds on paper and on graphite
    /// - lines are the ink at low alpha in light and white at low alpha in dark,
    ///   because a hairline on paper is darker paper and a hairline on graphite
    ///   is a lit edge
    /// - the ink ramp walks the ink toward the ground, which keeps every step on
    ///   the hue of the page it sits on
    /// - `accentInk` picks whichever of the ink and the ground survives the
    ///   accent better, rather than assuming light-on-accent
    ///
    /// `inkMuted` is the one slot the rules cannot reach: Action's field tan is
    /// its own decision, not a point on a ramp. The derivation makes a
    /// reasonable warm step and expects a theme that cares to override it.
    func surface() -> ActionSurface {
        let lift = max(0, self.lift)
        func step(_ points: Double) -> (ActionRGBA) -> ActionRGBA {
            { $0.lightnessAdjusted(by: points * lift) }
        }

        let panel = ground.mapped(step(3.2))
        let lit = ActionThemeColor(light: ink.light, dark: ActionRGBA(white: 1))
        let deep = self.deep ?? ActionThemeColor(
            light: ink.light.lightnessAdjusted(by: -2).mixed(with: ActionRGBA(hex: 0x8A6A3C), 0.10),
            dark: ground.dark.lightnessAdjusted(by: -3.5)
        )
        let onDeep = ActionThemeColor(ground.light)

        return ActionSurface(
            canvas: ground,
            band: ground.mapped(step(-3.0)),
            panel: panel,
            panelRaised: panel.mapped(step(2.2)),
            recess: ground.mapped(step(-2.3)),
            deep: deep,
            edge: ActionThemeColor(light: ink.light.withAlpha(0.12), dark: ActionRGBA(white: 1, alpha: 0.10)),
            rule: lit.withAlpha(0.20),
            grid: lit.withAlpha(0.027),
            shadow: ActionThemeColor(
                light: ActionRGBA(0, 0, 0, 0.05),
                dark: ActionRGBA(0, 0, 0, 0.22)
            ),
            ink: ink,
            inkSecondary: ink.mixed(with: ground, 0.29),
            inkRow: ink.mixed(with: ground, 0.13),
            inkMuted: ink.mixed(with: accent, 0.55).mixed(with: ground, 0.12),
            // Asymmetric on purpose. On paper the metadata step that reads as
            // "quiet" is just under half way to the page; on graphite it has to
            // travel further before it stops competing with the row title.
            inkMeta: ActionThemeColor(
                light: ink.light.mixed(with: ground.light, 0.46),
                dark: ink.dark.mixed(with: ground.dark, 0.58)
            ),
            onDeep: onDeep,
            onDeepMeta: onDeep.mixed(with: deep, 0.45),
            accent: accent,
            accentInk: ActionThemeColor(
                light: Self.legibleOn(accent.light, ink: ink.light, ground: ground.light),
                dark: Self.legibleOn(accent.dark, ink: ink.dark, ground: ground.dark)
            ),
            accentSoft: accent.mapped(
                light: { $0.withAlpha(0.16) },
                dark: { $0.withAlpha(0.20) }
            ),
            signal: signal ?? accent.mapped { $0.mixed(with: ActionRGBA(hex: 0x1FB9C6), 0.85) }
        )
    }

    /// Whichever of the two the accent can actually carry.
    private static func legibleOn(_ accent: ActionRGBA, ink: ActionRGBA, ground: ActionRGBA) -> ActionRGBA {
        ink.contrastRatio(against: accent) >= ground.contrastRatio(against: accent) ? ink : ground
    }
}

// MARK: - Satellites

/// The gradient-filled primary control. Kept out of `ActionSurface` because it
/// is one component, not a place to stand.
///
/// The label colour lives here rather than on the chrome surface, and that is
/// not tidiness. It was `chrome.accentInk` — "what goes on top of the accent" —
/// which happens to be right in Action's own theme only because Action's chrome
/// accent is a near-black that matches the button. Seed a theme with any other
/// accent and the derivation picks a label for *that* colour, which is then
/// painted on a near-black button: a 1.0:1 invisible label. The button and its
/// label have to be chosen as a pair, so they are stated as one.
struct ActionControlPalette: Equatable, Sendable {
    var primaryTop: ActionThemeColor
    var primaryBottom: ActionThemeColor
    var primaryInk: ActionThemeColor
}

/// Outcome colours and the washes that carry them across a ledger.
///
/// One glanceable colour per row state, legible at 6pt dot size against the
/// panel fill in both appearances. The selection and hover washes are tuned as
/// a pair — hover has to survive being laid over selection — which is why they
/// are here rather than derived independently.
struct ActionStatusPalette: Equatable, Sendable {
    var ok: ActionThemeColor
    var running: ActionThemeColor
    var failed: ActionThemeColor
    var stopped: ActionThemeColor
    var recording: ActionThemeColor
    var paused: ActionThemeColor
    /// Zebra wash. Deliberately near-invisible: it should steady the eye across
    /// a 260-row scan without reading as a stripe.
    var rowAlternate: ActionThemeColor
    var selection: ActionThemeColor
    var selectionHover: ActionThemeColor
    var actionChip: ActionThemeColor
}

/// The capture HUD's material.
///
/// Modelled apart from the surfaces because it is not one: it is a fixed dark
/// instrument face with a brushed-graphite finish, and it stays that way in
/// both system appearances so the operator's theme can never change what
/// "recording" looks like. What a theme gets to move here is the tint set and
/// how hard the finish is polished — not the machine.
struct ActionHUDMaterial: Equatable, Sendable {
    var canvas: ActionRGBA
    var panel: ActionRGBA
    var panelRaised: ActionRGBA
    var paper: ActionRGBA
    var ink: ActionRGBA
    var muted: ActionRGBA
    var recess: ActionRGBA
    var etch: ActionRGBA

    // Tints. `coral` is runtime truth and is shared with the field surface.
    var coral: ActionRGBA
    var coralHot: ActionRGBA
    var cyan: ActionRGBA
    var amber: ActionRGBA

    // Machining.
    var metalTop: ActionRGBA
    var metalEdge: ActionRGBA
    var metalSheen: ActionRGBA
    var metalCore: ActionRGBA
    var metalTrough: ActionRGBA

    /// Finishing-pass strength: the rolled highlight, the settled shadow, the
    /// brushed grain. 0 leaves a flat matte face, 1 is the shipped finish.
    var polish: Double

    var gridAlpha: Double
    var strokeAlpha: Double
    var strokeStrongAlpha: Double
    var shadowAlpha: Double
}

/// Everything that is a number rather than a colour.
///
/// Both this and `ActionThemeType` carry a record of which keys the file
/// actually wrote, because a theme is a patch: `{"metrics": {"grain": 0.5}}`
/// has to leave the density it inherited alone, and "absent" and "written with
/// the default value" are not the same statement. The record is set by
/// `init(from:)` and consumed by `merged(onto:)`; every value that reaches a
/// resolved theme goes through the memberwise initialiser, which marks all of
/// them authored, so nothing downstream ever sees a half-stated set.
struct ActionThemeMetrics: Equatable, Sendable, Codable {
    var cornerRadius: Double
    var cornerRadiusSmall: Double
    var hairline: Double
    /// Multiplier on row heights and padding. Below 1 tightens a ledger; above
    /// 1 opens it for a demo recording where the audience is across a room.
    var density: Double
    /// Multiplier on every texture alpha — the field grid, the HUD grain.
    var grain: Double
    var shadowStrength: Double

    /// Which keys the theme file stated. See the note on the type above.
    private var authoredKeys: Set<String>

    static let `default` = ActionThemeMetrics(
        cornerRadius: 8,
        cornerRadiusSmall: 6,
        hairline: 1,
        density: 1,
        grain: 1,
        shadowStrength: 1
    )

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cornerRadius, cornerRadiusSmall, hairline, density, grain, shadowStrength
    }

    init(
        cornerRadius: Double,
        cornerRadiusSmall: Double,
        hairline: Double,
        density: Double,
        grain: Double,
        shadowStrength: Double
    ) {
        self.cornerRadius = cornerRadius
        self.cornerRadiusSmall = cornerRadiusSmall
        self.hairline = hairline
        self.density = density
        self.grain = grain
        self.shadowStrength = shadowStrength
        authoredKeys = Set(CodingKeys.allCases.map(\.rawValue))
    }

    /// Every field optional, so a theme can say `{"density": 1.1}` and mean it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = ActionThemeMetrics.default
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? base.cornerRadius
        cornerRadiusSmall = try container.decodeIfPresent(Double.self, forKey: .cornerRadiusSmall) ?? base.cornerRadiusSmall
        hairline = try container.decodeIfPresent(Double.self, forKey: .hairline) ?? base.hairline
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? base.density
        grain = try container.decodeIfPresent(Double.self, forKey: .grain) ?? base.grain
        shadowStrength = try container.decodeIfPresent(Double.self, forKey: .shadowStrength) ?? base.shadowStrength
        authoredKeys = Set(CodingKeys.allCases.filter(container.contains).map(\.rawValue))
    }

    /// This patch folded onto what it inherited: stated keys win, the rest keep
    /// the base's tuning.
    func merged(onto base: Self) -> Self {
        func pick(_ key: CodingKeys, _ stated: Double, _ inherited: Double) -> Double {
            authoredKeys.contains(key.rawValue) ? stated : inherited
        }
        return Self(
            cornerRadius: pick(.cornerRadius, cornerRadius, base.cornerRadius),
            cornerRadiusSmall: pick(.cornerRadiusSmall, cornerRadiusSmall, base.cornerRadiusSmall),
            hairline: pick(.hairline, hairline, base.hairline),
            density: pick(.density, density, base.density),
            grain: pick(.grain, grain, base.grain),
            shadowStrength: pick(.shadowStrength, shadowStrength, base.shadowStrength)
        )
    }
}

/// Type is part of a theme, not a separate setting.
///
/// Families are named rather than bundled: a theme that asks for a face the Mac
/// does not have falls back to the platform equivalent rather than silently
/// landing on something else.
///
/// Patch semantics as in `ActionThemeMetrics`. They matter more here, because
/// the value that gets lost by clobbering is a face: a theme asking only for
/// `{"scale": 1.12}` must not also decide that the app stops setting Charter.
struct ActionThemeType: Equatable, Sendable, Codable {
    /// The editorial face. `nil` means New York, via `.serif`.
    var editorialFamily: String?
    /// The house monospace. `nil` means the platform monospace.
    var monoFamily: String?
    /// Multiplier on every point size in the scale. Clamped when applied.
    var scale: Double

    /// Which keys the theme file stated. See the note on the type above.
    private var authoredEditorial: Bool
    private var authoredMono: Bool
    private var authoredScale: Bool

    static let `default` = ActionThemeType(
        editorialFamily: "Charter",
        monoFamily: nil,
        scale: 1
    )

    private enum CodingKeys: String, CodingKey {
        case editorial, mono, scale
    }

    init(editorialFamily: String?, monoFamily: String?, scale: Double) {
        self.editorialFamily = editorialFamily
        self.monoFamily = monoFamily
        self.scale = scale
        authoredEditorial = true
        authoredMono = true
        authoredScale = true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        editorialFamily = try container.decodeIfPresent(String.self, forKey: .editorial)
        monoFamily = try container.decodeIfPresent(String.self, forKey: .mono)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        authoredEditorial = container.contains(.editorial)
        authoredMono = container.contains(.mono)
        authoredScale = container.contains(.scale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if authoredEditorial { try container.encodeIfPresent(editorialFamily, forKey: .editorial) }
        if authoredMono { try container.encodeIfPresent(monoFamily, forKey: .mono) }
        if authoredScale { try container.encode(scale, forKey: .scale) }
    }

    /// This patch folded onto what it inherited. `"editorial": "none"` is still
    /// how a theme says "no bookish face anywhere" — that is a stated key, and
    /// so it wins, where an absent one inherits.
    func merged(onto base: Self) -> Self {
        Self(
            editorialFamily: authoredEditorial ? editorialFamily : base.editorialFamily,
            monoFamily: authoredMono ? monoFamily : base.monoFamily,
            scale: authoredScale ? scale : base.scale
        )
    }
}

struct ActionThemeIdentity: Equatable, Sendable, Codable {
    var id: String
    var name: String
    var author: String?
    var summary: String?
}

// MARK: - Theme

/// A complete look: four surfaces, the satellites, the numbers, the type.
struct ActionTheme: Equatable, Sendable {
    var identity: ActionThemeIdentity
    var chrome: ActionSurface
    var field: ActionSurface
    var review: ActionSurface
    var hud: ActionHUDMaterial
    var control: ActionControlPalette
    var status: ActionStatusPalette
    var metrics: ActionThemeMetrics
    var type: ActionThemeType

    /// Flattens the composition into the flat table the app paints from.
    ///
    /// This is the only place that knows both models. Views never see a surface
    /// and theme files never see a token except by name in `overrides`, which
    /// means the surface shape can grow without touching 488 call sites and the
    /// token list can grow without changing what an author writes.
    func tokens() -> [ActionToken: ActionThemeColor] {
        let grain = max(0, metrics.grain)
        let shadow = max(0, metrics.shadowStrength)
        func textured(_ color: ActionThemeColor) -> ActionThemeColor {
            grain == 1 ? color : color.mapped { $0.withAlpha($0.alpha * grain) }
        }
        func shadowed(_ color: ActionThemeColor) -> ActionThemeColor {
            shadow == 1 ? color : color.mapped { $0.withAlpha($0.alpha * shadow) }
        }
        func flat(_ value: ActionRGBA) -> ActionThemeColor {
            ActionThemeColor(value)
        }
        let polish = max(0, hud.polish)

        return [
            .appBackground: chrome.canvas,
            .railBackground: chrome.band,
            .footerBackground: chrome.band,
            .panelBackgroundTop: chrome.panel,
            .panelBackgroundBottom: chrome.panel,
            .panelBorder: chrome.edge,
            .panelShadow: shadowed(chrome.shadow),
            .textPrimary: chrome.ink,
            .textSecondary: chrome.inkSecondary,
            .textMuted: chrome.inkMuted,
            .cardFill: chrome.panel,
            .cardBorder: chrome.edge,
            .accentIdle: chrome.accent,
            .buttonPrimaryTop: control.primaryTop,
            .buttonPrimaryBottom: control.primaryBottom,
            .buttonSecondary: chrome.panel,
            .buttonSecondaryHover: chrome.panelRaised,
            .buttonPrimaryText: control.primaryInk,

            .accentRecording: status.recording,
            .accentPaused: status.paused,
            .runOk: status.ok,
            .runRunning: status.running,
            .runFailed: status.failed,
            .runStopped: status.stopped,
            .rowAlternate: textured(status.rowAlternate),
            .runSelection: status.selection,
            .runSelectionHover: status.selectionHover,
            .runActionChip: status.actionChip,

            .hudCanvas: flat(hud.canvas),
            .hudPanel: flat(hud.panel),
            .hudPanelRaised: flat(hud.panelRaised),
            .hudPaper: flat(hud.paper),
            .hudInk: flat(hud.ink),
            .hudMuted: flat(hud.muted),
            .hudGrid: flat(ActionRGBA(white: 1, alpha: hud.gridAlpha * grain)),
            .hudStroke: flat(ActionRGBA(white: 1, alpha: hud.strokeAlpha)),
            .hudStrokeStrong: flat(ActionRGBA(white: 1, alpha: hud.strokeStrongAlpha)),
            .hudCoral: flat(hud.coral),
            .hudCoralHot: flat(hud.coralHot),
            .hudCyan: flat(hud.cyan),
            .hudAmber: flat(hud.amber),
            .hudMetalTop: flat(hud.metalTop),
            .hudMetalEdge: flat(hud.metalEdge),
            .hudRecess: flat(hud.recess),
            .hudEtch: flat(hud.etch),
            .hudShadow: flat(ActionRGBA(0, 0, 0, hud.shadowAlpha * shadow)),
            .hudBevelLight: flat(ActionRGBA(white: 1, alpha: 0.055 * polish)),
            .hudBevelHairline: flat(ActionRGBA(white: 1, alpha: 0.11 * polish)),
            .hudBevelShadow: flat(ActionRGBA(0, 0, 0, 0.34 * polish)),
            .hudGrain: flat(ActionRGBA(white: 1, alpha: 0.028 * polish * grain)),
            .hudGrainDark: flat(ActionRGBA(0, 0, 0, 0.05 * polish * grain)),
            .hudMetalSheen: flat(hud.metalSheen),
            .hudMetalCore: flat(hud.metalCore),
            .hudMetalTrough: flat(hud.metalTrough),

            .fieldCanvas: field.canvas,
            .fieldPanel: field.panel,
            .fieldConsole: field.recess,
            .fieldPanelEdge: field.edge,
            .fieldRule: field.rule,
            .fieldGrid: textured(field.grid),
            .fieldInk: field.ink,
            .fieldInkSecondary: field.inkSecondary,
            .fieldInkRow: field.inkRow,
            .fieldInkMuted: field.inkMuted,
            .fieldInkMeta: field.inkMeta,
            .fieldDeep: field.deep,
            .fieldDeepText: field.onDeep,
            .fieldDeepMeta: field.onDeepMeta,
            .fieldDeepEdge: field.onDeep.withAlpha(0.12),
            .fieldDeepChip: field.onDeep.withAlpha(0.10),
            .fieldAccent: field.accent,
            .fieldAccentText: field.accentInk,
            .fieldSignal: field.signal,

            .reviewCanvas: review.canvas,
            .reviewPanel: review.panel,
            .reviewPanelRaised: review.panelRaised,
            .reviewStrokeSoft: review.edge,
            .reviewStrokeStrong: review.rule,
            .reviewAccent: review.accent,
            .reviewAccentMuted: review.accentSoft,

            .overlayScrim: flat(ActionRGBA(white: 0)),
            .overlayHairline: flat(ActionRGBA(white: 1, alpha: 0.08)),
            .overlayInk: flat(ActionRGBA(white: 1)),
        ]
    }
}
