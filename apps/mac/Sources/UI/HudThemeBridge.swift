import SwiftUI
import HudsonUI

extension HudTheme {
    /// Lattices' `Palette` mapped onto Hudson's runtime theme so HudsonUI
    /// primitives (starting with `HudComposer`) render in the app's dark
    /// aesthetic. Inject with `.environment(\.hudTheme, .lattices)`.
    ///
    /// `statusError → kill` makes the composer's morphing Stop button the exact
    /// Lattices red; `accent → running` gives the Send disc its green.
    static let lattices = HudTheme(
        palette: HudThemePalette(
            bg:          Palette.bg,
            surface:     Palette.surface,
            chrome:      Palette.bgSidebar,
            ink:         Palette.text,
            muted:       Palette.textDim,
            dim:         Palette.textMuted,
            border:      Palette.border,
            accent:      Palette.running,
            accentSoft:  Palette.running.opacity(0.12),
            statusOk:    Palette.running,
            statusWarn:  Palette.detach,
            statusError: Palette.kill,
            statusInfo:  Palette.launch
        ),
        hairline: HudThemeHairline(subtle: Palette.border, standard: Palette.borderLit),
        radius:   .default,
        focus:    HudThemeFocus(ring: Palette.borderLit, ringWidth: 1)
    )
}
