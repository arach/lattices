import type { SVGProps } from 'react'
import { latticesAccent, latticesGrid, speechPalette, type BrandTheme, type MarkPalette } from '../lib/marks'

/**
 * Four bars of a waveform on the Lattices grid. The first two are lit and the
 * rest dim: a readout part-way through, spoken words in ink and the queue still
 * ahead of the playhead faded — the same lit/dim split as the Lattices L, with
 * the queued bars a step stronger than the family's dim (`speechPalette`).
 */
const speechBars = [
  { height: 0.5, spoken: true },
  { height: 1, spoken: true },
  { height: 0.7, spoken: false },
  { height: 0.36, spoken: false },
] as const

/** The accent: the last spoken bar, where the playhead is. */
const accentBar = 1

export interface SpeechMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children'> {
  size?: number
  /** Bake a palette in for export. Omit to follow the page's logo tokens. */
  theme?: BrandTheme
  /** The current bar's colour, or `false` for one ink. Defaults to the family green. */
  accent?: string | false
  /** Colours over `theme`'s. The brand exporter paints one role at a time to split the mark into icon layers. */
  palette?: Partial<MarkPalette>
  label?: string
  decorative?: boolean
}

export function SpeechMark({
  size = 20, theme, accent, palette, label = 'Speech', decorative = true,
  className = theme ? undefined : 'site-mark', ...svgProps
}: SpeechMarkProps) {
  const { box, pad, gap, radius } = latticesGrid
  const span = box - 2 * pad
  const width = (span - gap * (speechBars.length - 1)) / speechBars.length
  const colors = theme ? { ...speechPalette[theme], ...palette } : undefined
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
      {speechBars.map(({ height, spoken }, index) => {
        const accented = accentFill !== undefined && index === accentBar
        return (
          <rect
            key={index}
            x={pad + index * (width + gap)}
            y={(box - height * span) / 2}
            width={width}
            height={height * span}
            rx={radius}
            className={colors ? undefined : 'site-mark-cell'}
            fill={colors ? (accented ? accentFill : spoken ? colors.ink : colors.dim) : undefined}
            fillOpacity={colors && !spoken ? colors.dimOpacity : undefined}
            style={colors ? undefined : { fill: accented ? accentFill : spoken ? 'var(--logo-ink)' : 'var(--speech-dim)' }}
          />
        )
      })}
    </svg>
  )
}
