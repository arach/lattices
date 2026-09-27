import type { SVGProps } from 'react'
import { blinkPalette, type BrandTheme } from '../../lib/marks'

export interface BlinkMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children' | 'color'> {
  /** Bake a palette in for export. Omit to follow `currentColor`. */
  theme?: BrandTheme
  /** Explicit ink. Overrides `theme`. */
  color?: string
  /** Accessible name. Ignored when decorative. */
  label?: string
  decorative?: boolean
}

/** A panel frame with two blocks stepping across it. */
export function BlinkMark({
  theme, color, label = 'Blink', decorative = true, ...svgProps
}: BlinkMarkProps) {
  const ink = color ?? (theme ? blinkPalette[theme] : 'currentColor')

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 18 18"
      fill="none"
      role={decorative ? undefined : 'img'}
      aria-hidden={decorative || undefined}
      aria-label={decorative ? undefined : label}
      {...svgProps}
    >
      <rect x="2.5" y="2.5" width="13" height="13" rx="3.1" stroke={ink} strokeWidth="1" />
      <rect x="5.75" y="5.75" width="3.25" height="3.25" fill={ink} />
      <rect x="9" y="9" width="3.25" height="3.25" fill={ink} />
    </svg>
  )
}
