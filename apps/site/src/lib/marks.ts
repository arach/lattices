/**
 * Colours and geometry the product marks share with the brand exporter
 * (`scripts/export-brand.tsx`). They live apart from the components so that
 * each component module exports only its component.
 */

export type BrandTheme = 'light' | 'dark'

/**
 * Lattices ink for exported kits. Theme names describe the intended background,
 * so `light` is dark ink. The live site leaves `theme` unset and reads the
 * `--logo-ink` / `--logo-dim` tokens instead, which lets hover states recolour it.
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
 * Blink ink for exported kits, matching the landing: bottle green on parchment
 * and near-white on black. Theme names describe the intended background. The
 * live site leaves `theme` unset and inherits `currentColor` from `text-acc`.
 */
export const blinkPalette = { light: '#2f6447', dark: '#f4f4f5' } as const

/** Blink's app icon keeps the desk's amber on near-black. */
export const blinkIcon = { mark: '#f0b45a', tile: '#0a0a0b' } as const
