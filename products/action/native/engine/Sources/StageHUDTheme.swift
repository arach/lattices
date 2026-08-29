import SwiftUI

/// The names the app paints with.
///
/// This used to *be* the palette: eighty hand-written `static let`s, each its
/// own light/dark pair, with no way to say that nineteen of them were one
/// surface or that four of them were the same colour. It is now a façade over
/// `ActionThemePalette`, which resolves whichever `ActionTheme` is installed.
///
/// Call sites did not have to change and should not change: `StageHUDTheme.x`
/// is still the right way for a view to name a colour. What changed is where
/// the value comes from — see `ActionTheme` for the surfaces, `ActionThemeSpec`
/// for the file format a theme is authored in, and `docs/theming.agent.md` for
/// the guide handed to whoever (or whatever) is doing the authoring.
///
/// Themes are swapped at runtime. Views that want to follow a swap observe
/// `ActionThemeStore.shared` and hang `.id(store.revision)` off their root;
/// there is nothing here to observe, by design, because a `Color` that resolved
/// itself through an environment lookup on every one of five hundred accesses
/// per pass would be the wrong trade.
enum StageHUDTheme {
    static var appBackground: Color { ActionThemePalette.color(.appBackground) }
    static var railBackground: Color { ActionThemePalette.color(.railBackground) }
    static var footerBackground: Color { ActionThemePalette.color(.footerBackground) }
    static var panelBackgroundTop: Color { ActionThemePalette.color(.panelBackgroundTop) }
    static var panelBackgroundBottom: Color { ActionThemePalette.color(.panelBackgroundBottom) }
    static var panelBorder: Color { ActionThemePalette.color(.panelBorder) }
    static var panelShadow: Color { ActionThemePalette.color(.panelShadow) }
    static var textPrimary: Color { ActionThemePalette.color(.textPrimary) }
    static var textSecondary: Color { ActionThemePalette.color(.textSecondary) }
    static var textMuted: Color { ActionThemePalette.color(.textMuted) }
    static var cardFill: Color { ActionThemePalette.color(.cardFill) }
    static var cardBorder: Color { ActionThemePalette.color(.cardBorder) }
    static var accentIdle: Color { ActionThemePalette.color(.accentIdle) }
    static var buttonPrimaryTop: Color { ActionThemePalette.color(.buttonPrimaryTop) }
    static var buttonPrimaryBottom: Color { ActionThemePalette.color(.buttonPrimaryBottom) }
    static var buttonSecondary: Color { ActionThemePalette.color(.buttonSecondary) }
    static var buttonSecondaryHover: Color { ActionThemePalette.color(.buttonSecondaryHover) }
    static var buttonPrimaryText: Color { ActionThemePalette.color(.buttonPrimaryText) }
    static var accentRecording: Color { ActionThemePalette.color(.accentRecording) }
    static var accentPaused: Color { ActionThemePalette.color(.accentPaused) }
    static var runOk: Color { ActionThemePalette.color(.runOk) }
    static var runRunning: Color { ActionThemePalette.color(.runRunning) }
    static var runFailed: Color { ActionThemePalette.color(.runFailed) }
    static var runStopped: Color { ActionThemePalette.color(.runStopped) }
    static var rowAlternate: Color { ActionThemePalette.color(.rowAlternate) }
    static var runSelection: Color { ActionThemePalette.color(.runSelection) }
    static var runSelectionHover: Color { ActionThemePalette.color(.runSelectionHover) }
    static var runActionChip: Color { ActionThemePalette.color(.runActionChip) }
    static var hudCanvas: Color { ActionThemePalette.color(.hudCanvas) }
    static var hudPanel: Color { ActionThemePalette.color(.hudPanel) }
    static var hudPanelRaised: Color { ActionThemePalette.color(.hudPanelRaised) }
    static var hudPaper: Color { ActionThemePalette.color(.hudPaper) }
    static var hudInk: Color { ActionThemePalette.color(.hudInk) }
    static var hudMuted: Color { ActionThemePalette.color(.hudMuted) }
    static var hudGrid: Color { ActionThemePalette.color(.hudGrid) }
    static var hudStroke: Color { ActionThemePalette.color(.hudStroke) }
    static var hudStrokeStrong: Color { ActionThemePalette.color(.hudStrokeStrong) }
    static var hudCoral: Color { ActionThemePalette.color(.hudCoral) }
    static var hudCoralHot: Color { ActionThemePalette.color(.hudCoralHot) }
    static var hudCyan: Color { ActionThemePalette.color(.hudCyan) }
    static var hudAmber: Color { ActionThemePalette.color(.hudAmber) }
    static var hudMetalTop: Color { ActionThemePalette.color(.hudMetalTop) }
    static var hudMetalEdge: Color { ActionThemePalette.color(.hudMetalEdge) }
    static var hudRecess: Color { ActionThemePalette.color(.hudRecess) }
    static var hudEtch: Color { ActionThemePalette.color(.hudEtch) }
    static var hudShadow: Color { ActionThemePalette.color(.hudShadow) }
    static var hudBevelLight: Color { ActionThemePalette.color(.hudBevelLight) }
    static var hudBevelHairline: Color { ActionThemePalette.color(.hudBevelHairline) }
    static var hudBevelShadow: Color { ActionThemePalette.color(.hudBevelShadow) }
    static var hudGrain: Color { ActionThemePalette.color(.hudGrain) }
    static var hudGrainDark: Color { ActionThemePalette.color(.hudGrainDark) }
    static var hudMetalSheen: Color { ActionThemePalette.color(.hudMetalSheen) }
    static var hudMetalCore: Color { ActionThemePalette.color(.hudMetalCore) }
    static var hudMetalTrough: Color { ActionThemePalette.color(.hudMetalTrough) }
    static var fieldCanvas: Color { ActionThemePalette.color(.fieldCanvas) }
    static var fieldPanel: Color { ActionThemePalette.color(.fieldPanel) }
    static var fieldConsole: Color { ActionThemePalette.color(.fieldConsole) }
    static var fieldPanelEdge: Color { ActionThemePalette.color(.fieldPanelEdge) }
    static var fieldRule: Color { ActionThemePalette.color(.fieldRule) }
    static var fieldGrid: Color { ActionThemePalette.color(.fieldGrid) }
    static var fieldInk: Color { ActionThemePalette.color(.fieldInk) }
    static var fieldInkSecondary: Color { ActionThemePalette.color(.fieldInkSecondary) }
    static var fieldInkRow: Color { ActionThemePalette.color(.fieldInkRow) }
    static var fieldInkMuted: Color { ActionThemePalette.color(.fieldInkMuted) }
    static var fieldInkMeta: Color { ActionThemePalette.color(.fieldInkMeta) }
    static var fieldDeep: Color { ActionThemePalette.color(.fieldDeep) }
    static var fieldDeepText: Color { ActionThemePalette.color(.fieldDeepText) }
    static var fieldDeepMeta: Color { ActionThemePalette.color(.fieldDeepMeta) }
    static var fieldDeepEdge: Color { ActionThemePalette.color(.fieldDeepEdge) }
    static var fieldDeepChip: Color { ActionThemePalette.color(.fieldDeepChip) }
    static var fieldAccent: Color { ActionThemePalette.color(.fieldAccent) }
    static var fieldAccentText: Color { ActionThemePalette.color(.fieldAccentText) }
    static var fieldSignal: Color { ActionThemePalette.color(.fieldSignal) }
    static var reviewCanvas: Color { ActionThemePalette.color(.reviewCanvas) }
    static var reviewPanel: Color { ActionThemePalette.color(.reviewPanel) }
    static var reviewPanelRaised: Color { ActionThemePalette.color(.reviewPanelRaised) }
    static var reviewStrokeSoft: Color { ActionThemePalette.color(.reviewStrokeSoft) }
    static var reviewStrokeStrong: Color { ActionThemePalette.color(.reviewStrokeStrong) }
    static var reviewAccent: Color { ActionThemePalette.color(.reviewAccent) }
    static var reviewAccentMuted: Color { ActionThemePalette.color(.reviewAccentMuted) }

    // MARK: - Media overlays

    /// Translucent plates and edges composited over captured frames — chips,
    /// toolbar plates, spotlight veils. Grounded in the footage, not the theme.
    /// Full-strength black; call sites keep their own `.opacity()`.
    static var overlayScrim: Color { ActionThemePalette.color(.overlayScrim) }
    /// Hairline stroke that lifts an overlay plate off the frame beneath it.
    static var overlayHairline: Color { ActionThemePalette.color(.overlayHairline) }
    /// Ink that has to read over any footage, themed or not.
    static var overlayInk: Color { ActionThemePalette.color(.overlayInk) }

    // MARK: - Numbers

    /// Corner radius for cards and panels.
    static var cornerRadius: CGFloat { ActionThemePalette.metrics.cornerRadius }
    /// Corner radius for chips, buttons and selection washes.
    static var cornerRadiusSmall: CGFloat { ActionThemePalette.metrics.cornerRadiusSmall }
    static var hairline: CGFloat { ActionThemePalette.metrics.hairline }
    /// Multiplier for row heights and padding. Applied by callers that lay out
    /// dense lists; a theme meant for a recording can open them up without the
    /// layout code knowing why.
    static var density: CGFloat { ActionThemePalette.metrics.density }
}
