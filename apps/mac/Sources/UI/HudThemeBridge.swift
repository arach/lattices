import SwiftUI
import HudsonUI

extension HudTheme {
    /// Lattices' `Palette` mapped onto Hudson's runtime theme so HudsonUI
    /// primitives (composer, agent transcript rows, markdown) render in the app's dark
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

extension HudTheme {
    /// The assistant page: neutral ink accent instead of the app's green,
    /// which is kept for one thing, the live mark. Every ink and hairline is
    /// opaque, pre-composited over the page (`AssistantInk`, dark or light):
    /// translucent ink over the page rasterizes soft at 1x.
    static var latticesAssistant: HudTheme {
        let set = AssistantInk.set
        let light = AssistantAppearance.current == .light
        func over(_ alpha: CGFloat) -> Color { Color(nsColor: set.over(alpha)) }
        return HudTheme(
            palette: HudThemePalette(
                bg:          Color(nsColor: set.ground),
                surface:     light ? over(0.04) : Palette.surface,
                chrome:      light ? over(0.06) : Palette.bgSidebar,
                ink:         Color(nsColor: set.prose),
                muted:       Color(nsColor: set.dim),
                dim:         over(0.42),
                border:      over(0.10),
                accent:      over(0.90),
                accentSoft:  over(0.10),
                statusOk:    Palette.running,
                statusWarn:  Palette.detach,
                statusError: Palette.kill,
                statusInfo:  Palette.launch
            ),
            hairline: HudThemeHairline(subtle: over(0.09), standard: over(0.16)),
            radius:   HudThemeRadius(tight: 3, standard: 4, card: 4),
            focus:    HudThemeFocus(ring: over(0.32), ringWidth: 1)
        )
    }
}
