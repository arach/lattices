/**
 * Colours and geometry the product marks share with the brand exporter
 * (`scripts/export-brand.tsx`). They live apart from the components so that
 * each component module exports only its component.
 */

export type BrandTheme = 'light' | 'dark'

/** A grid mark's baked colours: the lit ink and the dim cells beside it. */
export interface MarkPalette {
  ink: string
  dim: string
  dimOpacity: number
}

/**
 * The family ink for exported kits. Every product mark draws in it, and every
 * app icon sits on a tile of the light ink. Theme names describe the intended
 * background, so `light` is dark ink. The live site leaves `theme` unset and
 * reads the `--logo-ink` / `--logo-dim` tokens instead, which lets hover states
 * recolour it.
 */
export const latticesPalette = {
  light: { ink: '#101518', dim: '#101518', dimOpacity: 0.22 },
  dark: { ink: '#f2f2f2', dim: '#ffffff', dimOpacity: 0.18 },
} as const

/**
 * Speech keeps the Lattices ink but lifts its queued bars, which are words still
 * to come rather than empty cells. The family's dim reads at about 1.6:1 on
 * white and 1.7:1 on the dark tile; 45% and 35% bring the bars to about 3:1.
 * The live site reads `--speech-dim`, which matches.
 */
export const speechPalette = {
  light: { ...latticesPalette.light, dimOpacity: 0.45 },
  dark: { ...latticesPalette.dark, dimOpacity: 0.35 },
} as const

/**
 * Each mark carries one accent, on the part doing the work: the tile Lattices
 * is snapping into place, Blink's front note, Speech's current bar. They take
 * the family green, stepped darker on light so it holds 3:1 against white, as
 * the site's `--green` does. The live site reads `--logo-accent`.
 */
export const latticesAccent = { light: '#1a9d52', dark: '#33c773' } as const

/**
 * Action's cursor takes the contrasting coral instead: the colour that already
 * means "live" in its menu bar, and 3:1 or better on white and on the tile.
 */
export const actionAccent = { light: '#ef6a47', dark: '#ef6a47' } as const

/** The family grid: a 20-unit box, 2 units of padding, 1.2-unit gaps, 1-unit corners. */
export const latticesGrid = { box: 20, pad: 2, gap: 1.2, radius: 1 } as const

/**
 * The square the Action kit crops from ActionMark's 720 × 640 construction
 * drawing: the A's 460-unit square plus the family margin, so the glyph spans
 * 80% of the box, as the grid's 16 units span 20.
 */
export const actionMarkBox = [12.5, 12.5, 575, 575] as const
