/**
 * Colours and geometry the product marks share with the brand exporter
 * (`scripts/export-brand.tsx`). They live apart from the components so that
 * each component module exports only its component.
 */

export type BrandTheme = 'light' | 'dark'

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
 * Speech keeps the Lattices ink but lifts its queued bars on dark. Its icon and
 * favicon always sit on a dark tile, where the family's 18% reads at about 1.7:1;
 * 35% brings them to 3.2:1. The live site reads `--speech-dim`, which matches.
 */
export const speechPalette = {
  light: latticesPalette.light,
  dark: { ...latticesPalette.dark, dimOpacity: 0.35 },
} as const

/** The family grid: a 20-unit box, 2 units of padding, 1.2-unit gaps, 1-unit corners. */
export const latticesGrid = { box: 20, pad: 2, gap: 1.2, radius: 1 } as const

/**
 * The square the Action kit crops from ActionMark's 720 × 640 construction
 * drawing: the A's 460-unit square plus the family margin, so the glyph spans
 * 80% of the box, as the grid's 16 units span 20.
 */
export const actionMarkBox = [12.5, 12.5, 575, 575] as const
