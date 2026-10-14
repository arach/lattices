import type { SVGProps } from 'react'
import { latticesGrid, latticesPalette, type BrandTheme } from '../lib/marks'

/** Left column and bottom row lit — the L — with the rest of the 3 × 3 grid dim. */
const cells = [true, false, false, true, false, false, true, true, true]

export interface LatticesMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children'> {
  size?: number
  /** Bake a palette in for export. Omit to follow the page's logo tokens. */
  theme?: BrandTheme
  /** Accessible name. Ignored when decorative. */
  label?: string
  decorative?: boolean
}

export function LatticesMark({
  size = 20, theme, label = 'Lattices', decorative = true,
  className = theme ? undefined : 'site-mark', ...svgProps
}: LatticesMarkProps) {
  const { box, pad, gap, radius } = latticesGrid
  const cell = (box - 2 * pad - 2 * gap) / 3
  const colors = theme ? latticesPalette[theme] : undefined

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
      {cells.map((lit, index) => (
        <rect
          key={index}
          x={pad + (index % 3) * (cell + gap)}
          y={pad + Math.floor(index / 3) * (cell + gap)}
          width={cell}
          height={cell}
          rx={radius}
          className={colors ? undefined : 'site-mark-cell'}
          fill={colors ? (lit ? colors.ink : colors.dim) : undefined}
          fillOpacity={colors && !lit ? colors.dimOpacity : undefined}
          style={colors ? undefined : { fill: lit ? 'var(--logo-ink)' : 'var(--logo-dim)' }}
        />
      ))}
    </svg>
  )
}
