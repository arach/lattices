import { describe, test, expect } from 'bun:test'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { LatticesMark } from './LatticesMark'
import { latticesGrid } from '../lib/marks'

const render = (props = {}) => renderToStaticMarkup(createElement(LatticesMark, props))

/** The endpoints of each segment in a path built from M, V, H and A commands. */
function endpoints(d: string) {
  let x = 0, y = 0
  return [...d.matchAll(/([MVHA])([^MVHAZ]*)/g)].map(([, command, args]) => {
    const n = args.trim().split(/[\s,]+/).map(Number)
    if (command === 'V') y = n[0]
    else if (command === 'H') x = n[0]
    else [x, y] = n.slice(-2)
    return [x, y]
  })
}

describe('LatticesMark', () => {
  const { box, pad, gap } = latticesGrid
  const cell = (box - 2 * pad - 2 * gap) / 3
  const lo = pad + cell + gap, hi = lo + cell

  test('draws the centre as a quarter turn in the accent, inside its cell', () => {
    const html = render({ theme: 'light' })
    expect(html.match(/<rect/g)).toHaveLength(8)
    const [, d, fill] = html.match(/<path d="([^"]+)" fill="([^"]+)"/)!
    expect(fill).toBe('#ef6a47')
    expect(d).toContain(`A${cell.toFixed(3)} ${cell.toFixed(3)} 0 0 1`)
    for (const [x, y] of endpoints(d)) {
      expect(x).toBeGreaterThanOrEqual(lo - 1e-3)
      expect(x).toBeLessThanOrEqual(hi + 1e-3)
      expect(y).toBeGreaterThanOrEqual(lo - 1e-3)
      expect(y).toBeLessThanOrEqual(hi + 1e-3)
    }
  })

  test('accent={false} draws nine plain cells in one ink', () => {
    const html = render({ theme: 'dark', accent: false })
    expect(html).not.toContain('<path')
    expect(html.match(/<rect/g)).toHaveLength(9)
    expect(html).not.toContain('#ef6a47')
  })

  test('follows the page tokens when no theme is set', () => {
    const html = render()
    expect(html).toContain('style="fill:var(--logo-accent)"')
    expect(html).toContain('style="fill:var(--logo-ink)"')
  })
})
