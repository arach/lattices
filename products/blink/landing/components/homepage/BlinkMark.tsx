import type { SVGProps } from 'react'

export function BlinkMark(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 18 18" fill="none" aria-hidden="true" {...props}>
      <rect x="2.5" y="2.5" width="13" height="13" rx="3.1" stroke="currentColor" strokeWidth="1" />
      <rect x="5.75" y="5.75" width="3.25" height="3.25" fill="currentColor" />
      <rect x="9" y="9" width="3.25" height="3.25" fill="currentColor" />
    </svg>
  )
}
