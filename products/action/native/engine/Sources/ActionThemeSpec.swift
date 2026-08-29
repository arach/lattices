import Foundation

// MARK: - Slot addressing

extension ActionSurface {
    /// The slot names a theme file may patch, in the order they are documented.
    static let slotNames = [
        "canvas", "band", "panel", "panelRaised", "recess", "deep",
        "edge", "rule", "grid", "shadow",
        "ink", "inkSecondary", "inkRow", "inkMuted", "inkMeta", "onDeep", "onDeepMeta",
        "accent", "accentInk", "accentSoft", "signal",
    ]

    /// Returns false for a name that is not a slot, so a typo in a theme file is
    /// reported rather than silently ignored — the failure mode that makes
    /// hand-written design files miserable to debug.
    mutating func patch(slot: String, with color: ActionThemeColor) -> Bool {
        switch slot {
        case "canvas": canvas = color
        case "band": band = color
        case "panel": panel = color
        case "panelRaised": panelRaised = color
        case "recess": recess = color
        case "deep": deep = color
        case "edge": edge = color
        case "rule": rule = color
        case "grid": grid = color
        case "shadow": shadow = color
        case "ink": ink = color
        case "inkSecondary": inkSecondary = color
        case "inkRow": inkRow = color
        case "inkMuted": inkMuted = color
        case "inkMeta": inkMeta = color
        case "onDeep": onDeep = color
        case "onDeepMeta": onDeepMeta = color
        case "accent": accent = color
        case "accentInk": accentInk = color
        case "accentSoft": accentSoft = color
        case "signal": signal = color
        default: return false
        }
        return true
    }
}

extension ActionStatusPalette {
    static let slotNames = [
        "ok", "running", "failed", "stopped", "recording", "paused",
        "rowAlternate", "selection", "selectionHover", "actionChip",
    ]

    mutating func patch(slot: String, with color: ActionThemeColor) -> Bool {
        switch slot {
        case "ok": ok = color
        case "running": running = color
        case "failed": failed = color
        case "stopped": stopped = color
        case "recording": recording = color
        case "paused": paused = color
        case "rowAlternate": rowAlternate = color
        case "selection": selection = color
        case "selectionHover": selectionHover = color
        case "actionChip": actionChip = color
        default: return false
        }
        return true
    }
}

extension ActionControlPalette {
    static let slotNames = ["primaryTop", "primaryBottom", "primaryInk"]

    mutating func patch(slot: String, with color: ActionThemeColor) -> Bool {
        switch slot {
        case "primaryTop": primaryTop = color
        case "primaryBottom": primaryBottom = color
        case "primaryInk": primaryInk = color
        default: return false
        }
        return true
    }
}

// MARK: - Spec

/// A theme file.
///
/// The shape is a *patch*, not a palette: everything is optional, and what is
/// absent is inherited from `extends`. An agent asked to make Home feel colder
/// writes six lines, and every token it did not mention keeps the tuning it
/// already had. That is the difference between a theme system and a fork of the
/// palette.
///
/// Three levels of reach, coarse to fine, and a file may use all three:
///
/// 1. `surfaces.<name>.seed` — regrow a whole surface from a ground, an ink and
///    an accent. The separations are computed, so the result holds together.
/// 2. `surfaces.<name>.tokens` — patch named slots on a surface.
/// 3. `overrides` — patch a single painted token by its app-facing name, for
///    the one place a rule does not fit.
struct ActionThemeSpec: Codable, Sendable {
    var id: String
    var name: String?
    var author: String?
    var summary: String?
    /// Which theme this one starts from. Defaults to the house theme.
    var extends: String?

    var surfaces: [String: ActionSurfaceSpec]?
    var status: [String: ActionThemeColor]?
    var control: [String: ActionThemeColor]?
    var hud: ActionHUDSpec?
    var metrics: ActionThemeMetrics?
    var type: ActionThemeType?
    var overrides: [String: ActionThemeColor]?

    struct ActionSurfaceSpec: Codable, Sendable {
        var seed: ActionSurfaceSeed?
        var tokens: [String: ActionThemeColor]?
    }

    /// What a theme may move in the capture HUD. Not the machining — the HUD is
    /// a fixed instrument face and a theme that could restyle it would be able
    /// to change what "recording" looks like on a Mac being driven remotely.
    struct ActionHUDSpec: Codable, Sendable {
        var coral: ActionRGBA?
        var coralHot: ActionRGBA?
        var cyan: ActionRGBA?
        var amber: ActionRGBA?
        var polish: Double?
    }

    static let surfaceNames = ["chrome", "field", "review"]
}

// MARK: - Resolution

/// A theme plus the token-level exceptions taken against it.
struct ActionThemeDefinition: Sendable, Equatable {
    var theme: ActionTheme
    var overrides: [ActionToken: ActionThemeColor]

    init(theme: ActionTheme, overrides: [ActionToken: ActionThemeColor] = [:]) {
        self.theme = theme
        self.overrides = overrides
    }

    func tokens() -> [ActionToken: ActionThemeColor] {
        guard !overrides.isEmpty else { return theme.tokens() }
        return theme.tokens().merging(overrides) { _, override in override }
    }

    static let action = ActionThemeDefinition(theme: .action)
}

extension ActionThemeSpec {
    /// Folds the patch onto its base.
    ///
    /// Never throws and never partially applies: anything it cannot understand
    /// becomes an issue and the corresponding slot keeps its inherited value, so
    /// a theme with one bad line still renders — with the bad line reported —
    /// rather than dropping the app to an unstyled default.
    func resolve(base: ActionTheme? = nil) -> (definition: ActionThemeDefinition, issues: [ActionThemeIssue]) {
        var issues: [ActionThemeIssue] = []
        let baseID = extends ?? ActionTheme.action.identity.id
        var theme = base ?? ActionTheme.builtin(id: baseID) ?? .action
        let inherited = theme
        if base == nil, extends != nil, ActionTheme.builtin(id: baseID) == nil {
            issues.append(.init(
                severity: .warning,
                message: "Unknown built-in base theme \"\(baseID)\"; extends accepts built-in theme IDs only, so started from \"\(ActionTheme.action.identity.id)\" instead."
            ))
        }

        theme.identity = ActionThemeIdentity(
            id: id,
            name: name ?? id,
            author: author,
            summary: summary
        )

        for (surfaceName, spec) in surfaces ?? [:] {
            guard var surface = theme[surface: surfaceName] else {
                issues.append(.init(
                    severity: .error,
                    message: "Unknown surface \"\(surfaceName)\". Expected one of \(Self.surfaceNames.joined(separator: ", "))."
                ))
                continue
            }
            if let seed = spec.seed {
                surface = seed.surface()
            }
            for (slot, color) in spec.tokens ?? [:] where !surface.patch(slot: slot, with: color) {
                issues.append(.init(
                    severity: .error,
                    message: "Unknown slot \"\(surfaceName).\(slot)\". Valid slots: \(ActionSurface.slotNames.joined(separator: ", "))."
                ))
            }
            theme[surface: surfaceName] = surface
        }

        for (slot, color) in status ?? [:] where !theme.status.patch(slot: slot, with: color) {
            issues.append(.init(
                severity: .error,
                message: "Unknown status slot \"\(slot)\". Valid slots: \(ActionStatusPalette.slotNames.joined(separator: ", "))."
            ))
        }

        for (slot, color) in control ?? [:] where !theme.control.patch(slot: slot, with: color) {
            issues.append(.init(
                severity: .error,
                message: "Unknown control slot \"\(slot)\". Valid slots: \(ActionControlPalette.slotNames.joined(separator: ", "))."
            ))
        }

        if let hud {
            if let coral = hud.coral { theme.hud.coral = coral }
            if let coralHot = hud.coralHot { theme.hud.coralHot = coralHot }
            if let cyan = hud.cyan { theme.hud.cyan = cyan }
            if let amber = hud.amber { theme.hud.amber = amber }
            if let polish = hud.polish { theme.hud.polish = min(max(polish, 0), 2) }
        }

        if let metrics { theme.metrics = metrics.merged(onto: theme.metrics).clamped() }
        if let type { theme.type = type.merged(onto: theme.type).clamped() }

        var resolvedOverrides: [ActionToken: ActionThemeColor] = [:]
        for (name, color) in overrides ?? [:] {
            guard let token = ActionToken(rawValue: name) else {
                issues.append(.init(severity: .error, message: "Unknown token \"\(name)\" in overrides."))
                continue
            }
            resolvedOverrides[token] = color
        }

        let definition = ActionThemeDefinition(theme: theme, overrides: resolvedOverrides)
        issues.append(contentsOf: ActionThemeValidator.check(definition, inheritedFrom: inherited))
        return (definition, issues)
    }
}

extension ActionTheme {
    subscript(surface name: String) -> ActionSurface? {
        get {
            switch name {
            case "chrome": return chrome
            case "field": return field
            case "review": return review
            default: return nil
            }
        }
        set {
            guard let newValue else { return }
            switch name {
            case "chrome": chrome = newValue
            case "field": field = newValue
            case "review": review = newValue
            default: break
            }
        }
    }
}

extension ActionThemeMetrics {
    /// A theme file is data from outside the app; a negative corner radius or a
    /// density of 40 should be brought back into range, not crash a layout.
    func clamped() -> ActionThemeMetrics {
        ActionThemeMetrics(
            cornerRadius: min(max(cornerRadius, 0), 28),
            cornerRadiusSmall: min(max(cornerRadiusSmall, 0), 24),
            hairline: min(max(hairline, 0.5), 3),
            density: min(max(density, 0.85), 1.35),
            grain: min(max(grain, 0), 2.5),
            shadowStrength: min(max(shadowStrength, 0), 2.5)
        )
    }
}

extension ActionThemeType {
    func clamped() -> ActionThemeType {
        ActionThemeType(
            editorialFamily: editorialFamily,
            monoFamily: monoFamily,
            scale: min(max(scale, 0.85), 1.3)
        )
    }
}

// MARK: - Validation

struct ActionThemeIssue: Sendable, Equatable {
    enum Severity: String, Sendable {
        case error
        case warning
    }

    var severity: Severity
    var message: String
}

/// The guardrail that makes it safe to let something else write the palette.
///
/// A generated theme fails in one of two ways, and neither is visible in the
/// file: text that does not survive its background, and a card that has become
/// the same colour as the page it sits on. Both are arithmetic, so both can be
/// checked before a single pixel is painted — in *both* appearances, which is
/// the half that gets skipped when a human eyeballs it in whichever mode they
/// happen to be running.
enum ActionThemeValidator {
    /// Foreground/background pairs the app actually renders, with the ratio
    /// each one has to clear. 4.5 is WCAG AA for body text; 3.0 is the large-
    /// text and non-text threshold, which is the right bar for a 6pt status dot
    /// or a chip.
    private static let contrastPairs: [(String, ActionToken, ActionToken, Double)] = [
        ("primary text on the launcher canvas", .textPrimary, .appBackground, 4.5),
        ("primary text on a card", .textPrimary, .cardFill, 4.5),
        ("secondary text on a card", .textSecondary, .cardFill, 3.5),
        ("muted text on a card", .textMuted, .cardFill, 3.0),
        ("primary-button label", .buttonPrimaryText, .buttonPrimaryTop, 4.5),
        ("Home body ink on the page", .fieldInk, .fieldCanvas, 4.5),
        ("Home row titles on a panel", .fieldInkRow, .fieldPanel, 4.5),
        ("Home secondary ink on a panel", .fieldInkSecondary, .fieldPanel, 3.5),
        ("Home metadata on a panel", .fieldInkMeta, .fieldPanel, 3.0),
        ("Home subtitle tan on a panel", .fieldInkMuted, .fieldPanel, 3.0),
        ("text in the command well", .fieldDeepText, .fieldDeep, 4.5),
        ("metadata in the command well", .fieldDeepMeta, .fieldDeep, 3.0),
        ("label on the accent", .fieldAccentText, .fieldAccent, 3.0),
        ("HUD readout", .hudPaper, .hudCanvas, 4.5),
        ("HUD secondary readout", .hudMuted, .hudPanel, 3.0),
        ("review accent on the review page", .reviewAccent, .reviewCanvas, 3.0),
        ("succeeded dot on a card", .runOk, .cardFill, 3.0),
        ("running dot on a card", .runRunning, .cardFill, 3.0),
        ("failed dot on a card", .runFailed, .cardFill, 3.0),
        ("stopped dot on a card", .runStopped, .cardFill, 3.0),
    ]

    /// Grounds that have to stay apart, or the hierarchy they encode disappears.
    private static let separationPairs: [(String, ActionToken, ActionToken)] = [
        ("a card from the launcher canvas", .cardFill, .appBackground),
        ("the rail from the launcher canvas", .railBackground, .appBackground),
        ("a Home panel from the page", .fieldPanel, .fieldCanvas),
        ("the Home console from the page", .fieldConsole, .fieldCanvas),
        ("a review panel from the review page", .reviewPanel, .reviewCanvas),
    ]

    /// The smallest lightness gap, in L\*, that still reads as an edge on a real
    /// screen. Roughly one step of the eight-bit ramp in the midtones.
    private static let minimumSeparation = 1.2

    /// Colours that must not be mistakable for each other, and the CIE76
    /// distance they need.
    ///
    /// This is the check that would have caught the worst mistake made porting
    /// other projects' palettes in. Every ported theme was pinned to Action's
    /// coral on the theory that "running" should always look the same — and
    /// coral sits 15 ΔE from the failure red, which on Action's warm paper the
    /// ground carries, and on a neutral charcoal does not. The result was a
    /// screen where every accented thing read as an alarm, and not one contrast
    /// or separation check noticed, because both colours were perfectly legible.
    /// They were just the same colour.
    ///
    /// 28 is about where two hues stop being confusable at a glance on a small
    /// element — a 6pt dot, a 2pt eyebrow rule.
    /// The recording red is deliberately *not* in this list. Recording and
    /// driving both mean "something is happening to this Mac right now", so two
    /// adjacent warm reds there are a family resemblance rather than a
    /// collision. Failure is the one that has to stand apart.
    private static let alarmPairs: [(String, ActionToken, ActionToken)] = [
        ("the accent", .fieldAccent, .runFailed),
        ("the idle accent", .accentIdle, .runFailed),
    ]

    private static let minimumAlarmDistance = 28.0

    /// `inheritedFrom` is the theme this one was grown out of, when there is
    /// one. It is used only by the alarm check, and only to stay quiet about a
    /// pair the author never touched — see the loop below.
    static func check(
        _ definition: ActionThemeDefinition,
        inheritedFrom base: ActionTheme? = nil
    ) -> [ActionThemeIssue] {
        let tokens = definition.tokens()
        let inherited = base?.tokens()
        var issues: [ActionThemeIssue] = []

        for side in ActionAppearanceSide.allCases {
            for (label, foreground, background, minimum) in contrastPairs {
                guard let fg = tokens[foreground]?.resolved(for: side),
                      let bg = tokens[background]?.resolved(for: side) else { continue }
                let ratio = fg.contrastRatio(against: bg)
                guard ratio < minimum else { continue }
                issues.append(.init(
                    severity: ratio < minimum * 0.75 ? .error : .warning,
                    message: String(
                        format: "%@ is %.1f:1 in %@ mode, below the %.1f:1 this pair needs (%@ on %@).",
                        label, ratio, side.rawValue, minimum,
                        foreground.rawValue, background.rawValue
                    )
                ))
            }

            for (label, accent, alarm) in alarmPairs {
                // Only pairs this theme actually moved. An accent inherited
                // unchanged is the base theme's decision, already made and
                // already reported against the base; repeating it on a theme
                // that only asked for a larger density is how a notes panel
                // stops being read.
                if let inherited,
                   inherited[accent] == tokens[accent],
                   inherited[alarm] == tokens[alarm] { continue }
                guard let a = tokens[accent]?.resolved(for: side),
                      let b = tokens[alarm]?.resolved(for: side) else { continue }
                let distance = a.difference(from: b)
                guard distance < minimumAlarmDistance else { continue }
                // Always a warning, never a blocker. Whether two hues collide
                // depends on the ground they sit on and on how much of the
                // screen the accent covers, and neither is something ΔE can
                // see. Worth saying every time; not worth refusing to paint.
                issues.append(.init(
                    severity: .warning,
                    message: String(
                        format: "%@ is only %.0f ΔE from %@ in %@ mode, which risks reading as an alarm (%@ vs %@).",
                        label, distance, alarm.rawValue, side.rawValue,
                        accent.rawValue, alarm.rawValue
                    )
                ))
            }

            for (label, near, far) in separationPairs {
                guard let a = tokens[near]?.resolved(for: side),
                      let b = tokens[far]?.resolved(for: side) else { continue }
                let gap = abs(a.perceptualLightness - b.perceptualLightness)
                guard gap < minimumSeparation else { continue }
                issues.append(.init(
                    severity: .warning,
                    message: String(
                        format: "Cannot tell %@ apart in %@ mode: the two grounds are %.1f L* apart, and an edge needs %.1f.",
                        label, side.rawValue, gap, minimumSeparation
                    )
                ))
            }
        }

        return issues.sorted { lhs, rhs in
            lhs.severity == rhs.severity ? lhs.message < rhs.message : lhs.severity == .error
        }
    }

    /// Whether a theme is fit to paint with. Warnings are worth showing and not
    /// worth blocking on; an error means something in it is unreadable.
    static func isUsable(_ issues: [ActionThemeIssue]) -> Bool {
        !issues.contains { $0.severity == .error }
    }
}
