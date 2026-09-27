import type { SVGProps } from 'react'
import { latticesAccent, latticesGrid, latticesPalette, type BrandTheme, type MarkPalette } from '../lib/marks'

/** Left column and bottom row lit — the L — with the rest of the 3 × 3 grid dim. */
const cells = [true, false, false, true, false, false, true, true, true]

/** The accent: the centre cell, the tile snapping into the crook of the L. */
const accentCell = 4

export interface LatticesMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children'> {
  size?: number
  /** Bake a palette in for export. Omit to follow the page's logo tokens. */
  theme?: BrandTheme
  /** The accent cell's colour, or `false` for one ink. Defaults to the family green. */
  accent?: string | false
  /** Colours over `theme`'s. The brand exporter paints one role at a time to split the mark into icon layers. */
  palette?: Partial<MarkPalette>
  /** Accessible name. Ignored when decorative. */
  label?: string
  decorative?: boolean
}

export function LatticesMark({
  size = 20, theme, accent, palette, label = 'Lattices', decorative = true,
  className = theme ? undefined : 'site-mark', ...svgProps
}: LatticesMarkProps) {
  const { box, pad, gap, radius } = latticesGrid
  const cell = (box - 2 * pad - 2 * gap) / 3
  const colors = theme ? { ...latticesPalette[theme], ...palette } : undefined
  const accentFill = accent === false ? undefined : accent ?? (theme ? latticesAccent[theme] : 'var(--logo-accent)')

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      width={size}
      height={size}
      viewBox={`0 0 ${box} ${box}`}
      fill="none"
      role={decorative ? undefined : 'img'}
      aria-hidden={decorative || undefined}
      aria-label={decorative ? undefined : label}
      {...svgProps}
    >
      {cells.map((lit, index) => {
        const accented = accentFill !== undefined && index === accentCell
        return (
          <rect
            key={index}
            x={pad + (index % 3) * (cell + gap)}
            y={pad + Math.floor(index / 3) * (cell + gap)}
            width={cell}
            height={cell}
            rx={radius}
            className={colors ? undefined : 'site-mark-cell'}
            fill={colors ? (accented ? accentFill : lit ? colors.ink : colors.dim) : undefined}
            fillOpacity={colors && !lit && !accented ? colors.dimOpacity : undefined}
            style={colors ? undefined : { fill: accented ? accentFill : lit ? 'var(--logo-ink)' : 'var(--logo-dim)' }}
          />
        )
      })}
    </svg>
  )
}
