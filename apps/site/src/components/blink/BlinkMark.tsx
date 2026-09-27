import type { SVGProps } from 'react'
import { latticesPalette, type BrandTheme } from '../../lib/marks'

export interface BlinkMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children' | 'color'> {
  /** Bake the family ink in for export. Omit to follow `currentColor`. */
  theme?: BrandTheme
  /** Explicit ink. Overrides `theme`. */
  color?: string
  /** Accessible name. Ignored when decorative. */
  label?: string
  decorative?: boolean
}

/**
 * A panel frame with two blocks stepping across it, on the family grid: the
 * frame's outer edge sits on the 16-unit guides and its stroke is the grid's
 * 1.2-unit gap.
 */
export function BlinkMark({
  theme, color, label = 'Blink', decorative = true, ...svgProps
}: BlinkMarkProps) {
  const ink = color ?? (theme ? latticesPalette[theme].ink : 'currentColor')

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="none"
      role={decorative ? undefined : 'img'}
      aria-hidden={decorative || undefined}
      aria-label={decorative ? undefined : label}
      {...svgProps}
    >
      <rect x="2.6" y="2.6" width="14.8" height="14.8" rx="3.5" stroke={ink} strokeWidth="1.2" />
      <rect x="6.3" y="6.3" width="3.7" height="3.7" fill={ink} />
      <rect x="10" y="10" width="3.7" height="3.7" fill={ink} />
    </svg>
  )
}
