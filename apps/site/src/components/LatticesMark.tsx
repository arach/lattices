import type { SVGProps } from 'react'
import { latticesAccent, latticesGrid, latticesPalette, type BrandTheme, type MarkPalette } from '../lib/marks'

/** Left column and bottom row lit — the L — with the rest of the 3 × 3 grid dim. */
const cells = [true, false, false, true, false, false, true, true, true]

/** The accent sits in the centre cell, in the crook of the L. */
const accentCell = 4

/**
 * The accent's shape: a quarter turn filling the cell, the arc a tile sweeps as
 * it swings into the crook. It pivots on the cell's bottom-left corner, where
 * the L's arms meet, which keeps the cells' corner radius; its two tips ease by
 * half that radius.
 */
function sweep(x: number, y: number, side: number, corner: number) {
  const tip = corner / 2
  const px = x, py = y + side
  // Each tip's fillet touches the straight edge and runs inside the arc.
  const reach = Math.sqrt((side - tip) ** 2 - tip ** 2)
  const out = side / (side - tip)
  const n = (v: number) => Number(v.toFixed(3))
  return [
    `M${n(px)} ${n(py - corner)}`,
    `V${n(py - reach)}`,
    `A${n(tip)} ${n(tip)} 0 0 1 ${n(px + tip * out)} ${n(py - reach * out)}`,
    `A${n(side)} ${n(side)} 0 0 1 ${n(px + reach * out)} ${n(py - tip * out)}`,
    `A${n(tip)} ${n(tip)} 0 0 1 ${n(px + reach)} ${n(py)}`,
    `H${n(px + corner)}`,
    `A${n(corner)} ${n(corner)} 0 0 1 ${n(px)} ${n(py - corner)}Z`,
  ].join('')
}

export interface LatticesMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children'> {
  size?: number
  /** Bake a palette in for export. Omit to follow the page's logo tokens. */
  theme?: BrandTheme
  /** The accent's colour, or `false` for one ink, which draws the centre as a plain dim cell. Defaults to the family coral. */
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
        const x = pad + (index % 3) * (cell + gap)
        const y = pad + Math.floor(index / 3) * (cell + gap)
        if (accentFill !== undefined && index === accentCell) {
          return (
            <path
              key={index}
              d={sweep(x, y, cell, radius)}
              className={colors ? undefined : 'site-mark-cell'}
              fill={colors ? accentFill : undefined}
              style={colors ? undefined : { fill: accentFill }}
            />
          )
        }
        return (
          <rect
            key={index}
            x={x}
            y={y}
            width={cell}
            height={cell}
            rx={radius}
            className={colors ? undefined : 'site-mark-cell'}
            fill={colors ? (lit ? colors.ink : colors.dim) : undefined}
            fillOpacity={colors && !lit ? colors.dimOpacity : undefined}
            style={colors ? undefined : { fill: lit ? 'var(--logo-ink)' : 'var(--logo-dim)' }}
          />
        )
      })}
    </svg>
  )
}
