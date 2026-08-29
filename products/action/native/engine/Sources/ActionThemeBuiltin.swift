import Foundation

/// The built-in themes.
///
/// `.action` is the look the app shipped with, transcribed slot for slot rather
/// than regenerated from a seed. That is deliberate: the values are hand-tuned
/// against real screens, and a derivation that reproduced them to within a
/// point would still be a different palette. Seeds are what an *author* gets to
/// skip the tuning with; the house theme keeps its tuning.
///
/// Three sets of near-duplicates were folded together on the way in, because
/// they were variance rather than intent:
///
/// - the footer was 4/255 off the rail in light mode and identical in dark;
///   both are now the one chrome `band`, which is what they were drawn as
/// - the panel top, panel bottom, card fill and secondary-button fill were four
///   names for one value; they are now `panel`
/// - the panel border and the card border differed by 2% alpha in dark and by
///   hue in light; they are now `edge`, on the ink
extension ActionTheme {
    static let action = ActionTheme(
        identity: ActionThemeIdentity(
            id: "action",
            name: "Action",
            author: "Action",
            summary: "Paper and graphite"
        ),
        chrome: .actionChrome,
        field: .actionField,
        review: .actionReview,
        hud: .action,
        control: ActionControlPalette(
            primaryTop: ActionThemeColor(
                light: ActionRGBA(white: 0.10),
                dark: ActionRGBA(white: 0.95)
            ),
            primaryBottom: ActionThemeColor(
                light: ActionRGBA(white: 0.18),
                dark: ActionRGBA(white: 0.82)
            ),
            primaryInk: ActionThemeColor(
                light: ActionRGBA(white: 1),
                dark: ActionRGBA(white: 0.08)
            )
        ),
        status: .action,
        metrics: .default,
        type: .default
    )

    /// Every built-in, in the order the picker shows them.
    static let builtins: [ActionTheme] = [.action]

    static func builtin(id: String) -> ActionTheme? {
        builtins.first { $0.identity.id == id }
    }
}

// MARK: - Surfaces

private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> ActionRGBA {
    ActionRGBA(r, g, b, a)
}

private func hex(_ value: UInt32, _ alpha: Double = 1) -> ActionRGBA {
    ActionRGBA(hex: value, alpha: alpha)
}

extension ActionSurface {
    /// The operator chrome: rail, footer, cards, ledgers. Neutral on purpose —
    /// it is the frame around the work, not the work.
    static let actionChrome = ActionSurface(
        canvas: ActionThemeColor(
            light: rgb(0.953, 0.922, 0.867),
            dark: rgb(0.078, 0.098, 0.102)
        ),
        band: ActionThemeColor(
            light: rgb(0.925, 0.886, 0.812),
            dark: rgb(0.055, 0.071, 0.074)
        ),
        panel: ActionThemeColor(
            light: rgb(0.980, 0.961, 0.922),
            dark: rgb(0.110, 0.133, 0.137)
        ),
        panelRaised: ActionThemeColor(
            light: rgb(0.996, 0.984, 0.957),
            dark: rgb(0.137, 0.165, 0.169)
        ),
        recess: ActionThemeColor(
            light: rgb(0.925, 0.886, 0.812),
            dark: rgb(0.055, 0.071, 0.074)
        ),
        deep: ActionThemeColor(light: hex(0x25231F), dark: hex(0x0A0E0F)),
        edge: ActionThemeColor(
            light: rgb(0.125, 0.157, 0.169, 0.12),
            dark: rgb(1, 1, 1, 0.10)
        ),
        rule: ActionThemeColor(
            light: rgb(0.125, 0.157, 0.169, 0.12),
            dark: rgb(1, 1, 1, 0.10)
        ),
        grid: ActionThemeColor(
            light: rgb(0.125, 0.157, 0.169, 0.025),
            dark: rgb(1, 1, 1, 0.028)
        ),
        shadow: ActionThemeColor(light: rgb(0, 0, 0, 0.05), dark: rgb(0, 0, 0, 0.22)),
        ink: ActionThemeColor(
            light: rgb(0.125, 0.157, 0.169),
            dark: rgb(0.953, 0.922, 0.867)
        ),
        inkSecondary: ActionThemeColor(
            light: rgb(0.349, 0.384, 0.380),
            dark: rgb(0.659, 0.702, 0.694)
        ),
        inkRow: ActionThemeColor(light: hex(0x3D4241), dark: hex(0xD5D0C4)),
        inkMuted: ActionThemeColor(
            light: rgb(0.529, 0.502, 0.463),
            dark: rgb(0.482, 0.529, 0.522)
        ),
        inkMeta: ActionThemeColor(light: hex(0x8A8175), dark: hex(0x6F7A78)),
        onDeep: ActionThemeColor(hex(0xF3EBDD)),
        onDeepMeta: ActionThemeColor(hex(0x8D9997)),
        accent: ActionThemeColor(light: ActionRGBA(white: 0.14), dark: ActionRGBA(white: 0.86)),
        accentInk: ActionThemeColor(light: ActionRGBA(white: 1), dark: ActionRGBA(white: 0.08)),
        accentSoft: ActionThemeColor(
            light: rgb(0.125, 0.157, 0.169, 0.10),
            dark: rgb(1, 1, 1, 0.12)
        ),
        signal: ActionThemeColor(rgb(0.122, 0.725, 0.776))
    )

    /// Home. The one surface that speaks in the brand's own voice: the paper /
    /// graphite pair from `assets/brand`, split across the two appearances.
    ///
    /// Both appearances keep the same coral and the same cyan, so a live drive
    /// reads identically either way — the colour that means "running" must not
    /// depend on the operator's theme.
    static let actionField = ActionSurface(
        canvas: ActionThemeColor(light: hex(0xF3EBDD), dark: hex(0x14191A)),
        band: ActionThemeColor(
            light: rgb(0.925, 0.886, 0.812),
            dark: rgb(0.055, 0.071, 0.074)
        ),
        panel: ActionThemeColor(light: hex(0xFAF5EB), dark: hex(0x1C2223)),
        panelRaised: ActionThemeColor(light: hex(0xFFFDF6), dark: hex(0x232A2B)),
        // A shade *below* the canvas where the panels sit a shade above it, so
        // the console reads as recessed into the page rather than as one more
        // card on it.
        recess: ActionThemeColor(light: hex(0xEDE4D3), dark: hex(0x111617)),
        // Warmed in light mode. The brand graphite (#20282B) is a cool
        // blue-green, and against warm paper it reads as a foreign object
        // dropped on the page. This keeps the darkness and drops the blue. Dark
        // mode keeps the cool graphite, because there it sits on a cool ground
        // and already agrees with it.
        deep: ActionThemeColor(light: hex(0x25231F), dark: hex(0x0A0E0F)),
        edge: ActionThemeColor(light: hex(0x20282B, 0.12), dark: rgb(1, 1, 1, 0.10)),
        rule: ActionThemeColor(light: hex(0x20282B, 0.22), dark: hex(0xF3EBDD, 0.18)),
        // Near-invisible on purpose: it should register as paper texture, not as
        // a ruled sheet.
        grid: ActionThemeColor(light: hex(0x20282B, 0.025), dark: rgb(1, 1, 1, 0.028)),
        shadow: ActionThemeColor(light: rgb(0, 0, 0, 0.05), dark: rgb(0, 0, 0, 0.22)),
        ink: ActionThemeColor(light: hex(0x20282B), dark: hex(0xF3EBDD)),
        inkSecondary: ActionThemeColor(light: hex(0x596261), dark: hex(0xA8B3B1)),
        inkRow: ActionThemeColor(light: hex(0x3D4241), dark: hex(0xD5D0C4)),
        // Field tan. An accent voice, not a demotion — it carries the editorial
        // subtitle beside a panel label. Deliberately not used for numbers: tan
        // is saturated enough that applying it to every duration made the
        // metadata louder than the row titles it describes.
        inkMuted: ActionThemeColor(light: hex(0xA77850), dark: hex(0x7B8785)),
        inkMeta: ActionThemeColor(light: hex(0x8A8175), dark: hex(0x6F7A78)),
        onDeep: ActionThemeColor(hex(0xF3EBDD)),
        onDeepMeta: ActionThemeColor(hex(0x8D9997)),
        accent: ActionThemeColor(rgb(0.937, 0.416, 0.278)),
        accentInk: ActionThemeColor(light: hex(0xFAF5EB), dark: hex(0x0E1213)),
        accentSoft: ActionThemeColor(rgb(0.937, 0.416, 0.278, 0.16)),
        signal: ActionThemeColor(rgb(0.122, 0.725, 0.776))
    )

    /// Review. A cool neutral sheet — the one place the warm paper would fight
    /// the thing being reviewed.
    static let actionReview = ActionSurface(
        canvas: ActionThemeColor(
            light: rgb(0.975, 0.978, 0.985),
            dark: ActionRGBA(white: 0.055)
        ),
        band: ActionThemeColor(
            light: rgb(0.955, 0.960, 0.972),
            dark: ActionRGBA(white: 0.040)
        ),
        panel: ActionThemeColor(
            light: rgb(0.992, 0.993, 0.996),
            dark: ActionRGBA(white: 0.08)
        ),
        panelRaised: ActionThemeColor(
            light: ActionRGBA(white: 1),
            dark: ActionRGBA(white: 0.095)
        ),
        recess: ActionThemeColor(
            light: rgb(0.945, 0.950, 0.964),
            dark: ActionRGBA(white: 0.035)
        ),
        deep: ActionThemeColor(light: hex(0x1B1F26), dark: hex(0x08090B)),
        edge: ActionThemeColor(
            light: ActionRGBA(white: 0.08, alpha: 0.08),
            dark: rgb(1, 1, 1, 0.08)
        ),
        rule: ActionThemeColor(
            light: ActionRGBA(white: 0.08, alpha: 0.16),
            dark: rgb(1, 1, 1, 0.16)
        ),
        grid: ActionThemeColor(
            light: ActionRGBA(white: 0.08, alpha: 0.025),
            dark: rgb(1, 1, 1, 0.028)
        ),
        shadow: ActionThemeColor(light: rgb(0, 0, 0, 0.05), dark: rgb(0, 0, 0, 0.22)),
        ink: ActionThemeColor(
            light: rgb(0.125, 0.157, 0.169),
            dark: rgb(0.953, 0.922, 0.867)
        ),
        inkSecondary: ActionThemeColor(
            light: rgb(0.349, 0.384, 0.380),
            dark: rgb(0.659, 0.702, 0.694)
        ),
        inkRow: ActionThemeColor(light: hex(0x3D4241), dark: hex(0xD5D0C4)),
        inkMuted: ActionThemeColor(
            light: rgb(0.529, 0.502, 0.463),
            dark: rgb(0.482, 0.529, 0.522)
        ),
        inkMeta: ActionThemeColor(light: hex(0x8A8175), dark: hex(0x6F7A78)),
        onDeep: ActionThemeColor(hex(0xF3EBDD)),
        onDeepMeta: ActionThemeColor(hex(0x8D9997)),
        accent: ActionThemeColor(
            light: rgb(0.19, 0.47, 0.90),
            dark: rgb(0.47, 0.71, 1.00)
        ),
        accentInk: ActionThemeColor(light: ActionRGBA(white: 1), dark: ActionRGBA(white: 0.06)),
        accentSoft: ActionThemeColor(
            light: rgb(0.19, 0.47, 0.90, 0.18),
            dark: rgb(0.47, 0.71, 1.00, 0.22)
        ),
        signal: ActionThemeColor(rgb(0.122, 0.725, 0.776))
    )
}

// MARK: - Status

extension ActionStatusPalette {
    static let action = ActionStatusPalette(
        ok: ActionThemeColor(light: rgb(0.13, 0.55, 0.33), dark: rgb(0.38, 0.80, 0.55)),
        running: ActionThemeColor(light: rgb(0.72, 0.50, 0.06), dark: rgb(0.95, 0.76, 0.34)),
        failed: ActionThemeColor(light: rgb(0.78, 0.21, 0.19), dark: rgb(0.98, 0.45, 0.42)),
        stopped: ActionThemeColor(light: ActionRGBA(white: 0.52), dark: ActionRGBA(white: 0.55)),
        recording: ActionThemeColor(rgb(0.98, 0.38, 0.38)),
        paused: ActionThemeColor(rgb(0.95, 0.76, 0.34)),
        rowAlternate: ActionThemeColor(light: rgb(0, 0, 0, 0.018), dark: rgb(1, 1, 1, 0.022)),
        selection: ActionThemeColor(
            light: rgb(0.19, 0.47, 0.90, 0.13),
            dark: rgb(0.47, 0.71, 1.00, 0.17)
        ),
        selectionHover: ActionThemeColor(
            light: rgb(0.19, 0.47, 0.90, 0.22),
            dark: rgb(0.47, 0.71, 1.00, 0.27)
        ),
        actionChip: ActionThemeColor(
            light: rgb(0.19, 0.47, 0.90, 0.11),
            dark: rgb(0.47, 0.71, 1.00, 0.15)
        )
    )
}

// MARK: - HUD

extension ActionHUDMaterial {
    static let action = ActionHUDMaterial(
        canvas: rgb(0.055, 0.071, 0.074),
        panel: rgb(0.095, 0.118, 0.122),
        panelRaised: rgb(0.125, 0.153, 0.157),
        paper: rgb(0.953, 0.922, 0.867),
        ink: rgb(0.055, 0.071, 0.074),
        muted: rgb(0.60, 0.65, 0.64),
        recess: rgb(0.026, 0.031, 0.031),
        etch: rgb(0.68, 0.68, 0.61),
        coral: rgb(0.937, 0.416, 0.278),
        coralHot: rgb(1.0, 0.49, 0.32),
        cyan: rgb(0.122, 0.725, 0.776),
        amber: rgb(0.894, 0.725, 0.412),
        metalTop: rgb(0.115, 0.118, 0.112),
        metalEdge: rgb(0.39, 0.39, 0.35),
        metalSheen: rgb(0.30, 0.31, 0.29),
        metalCore: rgb(0.165, 0.170, 0.160),
        metalTrough: rgb(0.045, 0.048, 0.046),
        polish: 1,
        gridAlpha: 0.045,
        strokeAlpha: 0.10,
        strokeStrongAlpha: 0.19,
        shadowAlpha: 0.58
    )
}
