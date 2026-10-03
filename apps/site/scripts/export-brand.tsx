/**
 * Exports each product's brand kit from its React mark.
 *
 *   bun scripts/export-brand.tsx               # every product
 *   bun scripts/export-brand.tsx blink speech  # just these
 *
 * Writes public/brand/<product>/ and, on macOS, the .icns each native app
 * bundles. The mark components are the source of truth. Everything here is
 * generated and committed, so the site and the app builds stay offline.
 */
import { createElement as h, type ReactElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import sharp from 'sharp'
import { execFileSync } from 'node:child_process'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ActionMark } from '../src/components/ActionMark'
import { BlinkMark } from '../src/components/blink/BlinkMark'
import { LatticesMark } from '../src/components/LatticesMark'
import { SpeechMark } from '../src/components/SpeechMark'
import { actionMarkBox, latticesPalette, speechPalette } from '../src/lib/marks'

type Theme = 'light' | 'dark'
type Box = { x: number; y: number; width: number; height: number }

const siteDir = fileURLToPath(new URL('..', import.meta.url))
const repoRoot = join(siteDir, '..', '..')
const brandDir = join(siteDir, 'public', 'brand')
const themes = ['light', 'dark'] as const
const ladder = [16, 24, 32, 48, 64, 80, 128, 256, 512, 1024]

/**
 * The app icon grid every product shares: Apple's 824-pixel tile in a 1024
 * canvas. The corners are superellipse quadrants reaching 34.5% along each
 * edge with exponent 2.85, fitted to the mask macOS 26 draws around system
 * icons (within a pixel at 1024). Every mark fills the same square of its own
 * box, so one glyph share puts them all on the same guides, and every tile is
 * the family's light ink with a hairline just inside the edge, so it holds its
 * shape on a dark Dock. ActionBrandMark.swift draws Action's in-app chip with
 * the same numbers.
 */
const grid = {
  canvas: 1024, inset: 100, cornerRatio: 0.345, exponent: 2.85, samples: 48,
  /** The glyph's longer side as a share of the tile. */
  glyph: 0.56,
  tile: latticesPalette.light.ink,
  edge: 'rgba(255,255,255,.08)',
}

/** Favicons have no margin to spare, so the glyph grows to fill the tile. */
const faviconGlyphScale = 1.18

interface Product {
  slug: string
  name: string
  source: string
  viewBox: readonly [number, number, number, number]
  /** The mark alone, baked for a light or dark background. */
  mark: (theme: Theme) => ReactElement
  /** The mark as it sits on the icon tile. */
  iconMark: (box?: Box) => ReactElement
  /** Repo-relative paths of the .icns files the native builds copy. */
  icns: string[]
  /** Extra flat icon PNGs some product folders keep beside their .icns. */
  iconPngs?: { dir: string; sizes: number[] }
  /** A repo-relative copy of the icon SVG, for product folders that keep the vector beside their .icns. */
  iconSvg?: string
  colours: Array<[string, string]>
  notes: string[]
}

const actionKitProps = { guides: false, background: false, viewBox: actionMarkBox.join(' ') } as const

const products: Product[] = [
  {
    slug: 'lattices',
    name: 'Lattices',
    source: 'src/components/LatticesMark.tsx',
    viewBox: [0, 0, 20, 20],
    mark: (theme) => h(LatticesMark, { theme, size: 512 }),
    iconMark: (box) => h(LatticesMark, { theme: 'dark', ...box }),
    icns: ['assets/AppIcon.icns'],
    colours: [
      ['Ink on light', latticesPalette.light.ink],
      ['Dim cells on light', `${latticesPalette.light.dim} at ${latticesPalette.light.dimOpacity * 100}%`],
      ['Ink on dark', latticesPalette.dark.ink],
      ['Dim cells on dark', `${latticesPalette.dark.dim} at ${latticesPalette.dark.dimOpacity * 100}%`],
      ['Icon tile', grid.tile],
    ],
    notes: [
      'A 3 × 3 grid with the left column and bottom row lit: the L. The site header draws the same component with `theme` unset, so it follows the `--logo-ink` and `--logo-dim` tokens and their hover states.',
      '`public/favicon.svg` is a copy of `lattices-favicon.svg`.',
    ],
  },
  {
    slug: 'action',
    name: 'Action',
    source: 'src/components/ActionMark.tsx',
    viewBox: actionMarkBox,
    mark: (theme) => h(ActionMark, { theme, ...actionKitProps, width: 512, height: 512 }),
    iconMark: (box) => h(ActionMark, {
      theme: 'dark', ...actionKitProps, decorative: true,
      // The component styles itself to fill its container; inside the icon the
      // placement attributes have to win.
      style: { width: undefined, height: undefined },
      ...box,
    }),
    icns: ['products/action/assets/brand/Action.icns'],
    iconPngs: { dir: 'products/action/assets/brand', sizes: [512, 1024] },
    colours: [
      ['Ink on light', latticesPalette.light.ink],
      ['Ink on dark', latticesPalette.dark.ink],
      ['Icon tile', grid.tile],
    ],
    notes: [
      `The A fills a square and the cursor lies on its diagonal: the tip sits on the counter's edge and the tail touches the square's right and bottom sides, so the glyph is the square. The kit crops ActionMark's construction drawing to \`${actionMarkBox.join(' ')}\`, the square plus the family margin, so the glyph spans 80% of the box, as the Lattices grid's 16 units span 20.`,
      'Letter and cursor share the family ink; the 10-unit gap separates them.',
      'The site hero uses the precomputed SVG. The full construction drawing remains a configurable React component.',
      '`products/action/native/engine/CoreSources/ActionBrandMark.swift` ports the same geometry for the menu bar and the in-app chip.',
    ],
  },
  {
    slug: 'blink',
    name: 'Blink',
    source: 'src/components/blink/BlinkMark.tsx',
    viewBox: [0, 0, 20, 20],
    mark: (theme) => h(BlinkMark, { theme, width: 512, height: 512 }),
    iconMark: (box) => h(BlinkMark, { theme: 'dark', ...box }),
    icns: ['products/blink/assets/AppIcon.icns'],
    iconSvg: 'products/blink/assets/AppIcon.svg',
    colours: [
      ['Ink on light', latticesPalette.light.ink],
      ['Ink on dark', latticesPalette.dark.ink],
      ['Icon tile', grid.tile],
    ],
    notes: [
      'A panel frame with two blocks stepping across it, on the Lattices grid: the frame’s outer edge sits on the 16-unit square and its stroke is the grid’s 1.2-unit gap. The page header draws the same component in `currentColor`.',
    ],
  },
  {
    slug: 'speech',
    name: 'Speech',
    source: 'src/components/SpeechMark.tsx',
    viewBox: [0, 0, 20, 20],
    mark: (theme) => h(SpeechMark, { theme, size: 512 }),
    iconMark: (box) => h(SpeechMark, { theme: 'dark', ...box }),
    icns: ['products/voice/assets/AppIcon.icns'],
    colours: [
      ['Ink on light', latticesPalette.light.ink],
      ['Queued bars on light', `${speechPalette.light.dim} at ${speechPalette.light.dimOpacity * 100}%`],
      ['Ink on dark', latticesPalette.dark.ink],
      ['Queued bars on dark', `${speechPalette.dark.dim} at ${speechPalette.dark.dimOpacity * 100}%`],
      ['Icon tile', grid.tile],
    ],
    notes: [
      'Four waveform bars on the Lattices grid, the first two lit: a readout part-way through, with the words still queued dimmed. It uses the Lattices palette and cell geometry, except that the queued bars sit at 35% on dark, against the family’s 18%, so they read on the icon’s dark tile.',
    ],
  },
]

const round = (value: number) => Math.round(value * 1000) / 1000

/** A rounded square with superellipse corners, sampled the way ActionBrandMark.swift samples it. */
function tilePath(x0: number, y0: number, side: number, cornerRatio = grid.cornerRatio) {
  const x1 = x0 + side
  const y1 = y0 + side
  const r = side * cornerRatio
  const exponent = 2 / grid.exponent
  const points: string[] = []
  const at = (x: number, y: number) => points.push(`${round(x)} ${round(y)}`)
  const corner = (cx: number, cy: number, sx: number, sy: number, reversed: boolean) => {
    for (let i = 0; i <= grid.samples; i++) {
      const t = (Math.PI / 2) * ((reversed ? grid.samples - i : i) / grid.samples)
      at(cx + sx * r * Math.cos(t) ** exponent, cy + sy * r * Math.sin(t) ** exponent)
    }
  }

  at(x0 + r, y0)
  at(x1 - r, y0)
  corner(x1 - r, y0 + r, 1, -1, true)
  at(x1, y1 - r)
  corner(x1 - r, y1 - r, 1, 1, false)
  at(x0 + r, y1)
  corner(x0 + r, y1 - r, -1, 1, true)
  at(x0, y0 + r)
  corner(x0 + r, y0 + r, -1, -1, false)
  return `M${points.join('L')}Z`
}

/** The drawn glyph's bounds in the mark's own viewBox units, measured from a large raster. */
async function glyphBounds(product: Product): Promise<Box> {
  const px = 2048
  const svg = renderToStaticMarkup(product.iconMark({ x: 0, y: 0, width: px, height: px }))
  const { data } = await sharp(Buffer.from(svg)).resize(px, px).ensureAlpha().raw()
    .toBuffer({ resolveWithObject: true })
  let minX = px, minY = px, maxX = -1, maxY = -1
  for (let y = 0; y < px; y++) {
    for (let x = 0; x < px; x++) {
      if (data[(y * px + x) * 4 + 3] < 16) continue
      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
    }
  }
  const [vx, vy, vw] = product.viewBox
  const unit = vw / px
  return { x: vx + minX * unit, y: vy + minY * unit, width: (maxX + 1 - minX) * unit, height: (maxY + 1 - minY) * unit }
}

interface Composition {
  /** The tile's square inside the 1024 canvas. */
  body: Box
  glyphScale?: number
  /** Square corners, for icons the platform masks itself. */
  square?: boolean
  /** Draw the hairline. Favicons are too small for it. */
  finish?: boolean
}

function composeIcon(product: Product, bounds: Box, { body, glyphScale = 1, square = false, finish = true }: Composition) {
  const [vx, vy, vw, vh] = product.viewBox
  const scale = (body.width * grid.glyph * glyphScale) / Math.max(bounds.width, bounds.height)
  const cx = body.x + body.width / 2
  const cy = body.y + body.height / 2
  const placement: Box = {
    x: round(cx - (bounds.x - vx + bounds.width / 2) * scale),
    y: round(cy - (bounds.y - vy + bounds.height / 2) * scale),
    width: round(vw * scale),
    height: round(vh * scale),
  }
  const d = square
    ? `M${body.x} ${body.y}H${body.x + body.width}V${body.y + body.height}H${body.x}Z`
    : tilePath(body.x, body.y, body.width)

  return renderToStaticMarkup(
    h('svg', { xmlns: 'http://www.w3.org/2000/svg', viewBox: `0 0 ${grid.canvas} ${grid.canvas}`, role: 'img', 'aria-label': product.name },
      h('path', { d, fill: grid.tile }),
      finish ? h('path', { d, fill: 'none', stroke: grid.edge, strokeWidth: 2 }) : null,
      product.iconMark(placement)),
  )
}

async function png(svg: string, size: number, file?: string, flatten?: string) {
  let image = sharp(Buffer.from(svg)).resize(size, size)
  if (flatten) image = image.flatten({ background: flatten })
  const buffer = await image.png().toBuffer()
  if (file && !(await samePixels(file, buffer))) await writeFile(file, buffer)
  return buffer
}

/** Leaves a PNG alone when only its encoding would change, so a sharp upgrade doesn't churn the kit. */
async function samePixels(file: string, buffer: Buffer) {
  const existing = await readFile(file).catch(() => undefined)
  if (!existing) return false
  const [before, after] = await Promise.all(
    [existing, buffer].map((image) => sharp(image).ensureAlpha().raw().toBuffer()),
  )
  return before.equals(after)
}

/** iconutil wants exactly these names. */
const iconset: Array<[string, number]> = [
  ['icon_16x16', 16], ['icon_16x16@2x', 32],
  ['icon_32x32', 32], ['icon_32x32@2x', 64],
  ['icon_128x128', 128], ['icon_128x128@2x', 256],
  ['icon_256x256', 256], ['icon_256x256@2x', 512],
  ['icon_512x512', 512], ['icon_512x512@2x', 1024],
]

async function writeIcns(product: Product, svg: string) {
  const work = await mkdtemp(join(tmpdir(), `${product.slug}-icon-`))
  try {
    const set = join(work, `${product.name}.iconset`)
    await mkdir(set)
    for (const [name, size] of iconset) await png(svg, size, join(set, `${name}.png`))
    for (const target of product.icns) {
      const file = join(repoRoot, target)
      await mkdir(dirname(file), { recursive: true })
      execFileSync('iconutil', ['--convert', 'icns', set, '--output', file])
    }
  } finally {
    await rm(work, { recursive: true, force: true })
  }
}

/** "a", "a and b", "a, b and c". */
const prose = (items: string[]) =>
  items.length < 2 ? items.join('') : `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`

function readme(product: Product, bounds: Box) {
  const { slug, name, iconPngs, iconSvg } = product
  const copies = [
    ...(iconSvg ? [iconSvg] : []),
    ...(iconPngs ? iconPngs.sizes.map((size) => `${iconPngs.dir}/${slug}-icon-${size}.png`) : []),
  ]
  const sizes = ladder.join(', ')
  const glyph = Math.round(grid.glyph * 100)
  const lines = [
    `# ${name} logo assets`,
    '',
    `Generated by \`bun run brand\` from \`${product.source}\`. Edit the component, not these files.`,
    '',
    '| File | Use |',
    '| --- | --- |',
    `| \`${slug}-light.svg\`, \`${slug}-dark.svg\` | The mark for light and dark backgrounds |`,
    `| \`${slug}-{light,dark}-{size}.png\` | The same, transparent, at ${sizes} px |`,
    `| \`${slug}-icon.svg\`, \`${slug}-icon-{size}.png\` | The app icon on Apple's grid |`,
    `| \`${slug}-favicon.svg\` | Browser tab icon: the tile edge to edge |`,
    `| \`${slug}-touch-icon.png\` | 180 px home screen icon, square and opaque |`,
    '',
    'Theme names describe the intended background, so `light` is dark ink. The PNGs are proportional exports, not separately optically adjusted drawings.',
    '',
    ...product.notes.flatMap((note) => [note, '']),
    '## Colour',
    '',
    '| Role | Value |',
    '| --- | --- |',
    ...product.colours.map(([role, value]) => `| ${role} | \`${value}\` |`),
    '',
    '## App icon',
    '',
    `An 824 px tile in a 1024 canvas with continuous corners, shared by every Lattices product. The glyph's longer side spans ${glyph}% of the tile, as in every product icon. The favicon drops the margin and grows the glyph ${Math.round((faviconGlyphScale - 1) * 100)}%.`,
    '',
    `Measured glyph bounds in viewBox units: ${round(bounds.x)}, ${round(bounds.y)}, ${round(bounds.width)} × ${round(bounds.height)}.`,
    '',
    ...(product.icns.length
      ? [`On macOS the export also writes ${product.icns.map((file) => `\`${file}\``).join(', ')}, which the app build copies into the bundle.`, '']
      : []),
    ...(copies.length ? [`It also keeps ${prose(copies.map((file) => `\`${file}\``))} in step with the icon.`, ''] : []),
  ]
  return lines.join('\n')
}

/** public/brand/README.md: the kits at a glance and the grid they share. */
function indexReadme() {
  const tile = grid.canvas - grid.inset * 2
  const lines = [
    '# Brand kits',
    '',
    'One kit per product, generated by `bun run brand` (`scripts/export-brand.tsx`) from the React marks. Edit a component or the exporter and rerun it; the files here are output.',
    '',
    '| Product | Mark | Kit |',
    '| --- | --- | --- |',
    ...products.map(({ slug, name, source }) => `| ${name} | \`${source}\` | [\`${slug}/\`](${slug}/README.md) |`),
    '',
    'Each kit holds the mark for light and dark backgrounds as SVG and as transparent PNGs at ' +
      `${ladder.join(', ')} px, the app icon at the same sizes, a favicon, a 180 px touch icon, and a README with the colours and icon measurements.`,
    '',
    '## App icon grid',
    '',
    'Every product icon shares one grid, so they sit together in the Dock:',
    '',
    `- An ${tile} px tile inset ${grid.inset} px in a ${grid.canvas} px canvas: Apple's macOS icon grid.`,
    `- Continuous corners: superellipse quadrants reaching ${round(grid.cornerRatio * 100)}% along each edge with exponent ${grid.exponent}, fitted to the mask macOS 26 draws around system icons.`,
    `- One tile colour, the family's light ink \`${grid.tile}\`, with the mark in its dark-background ink.`,
    '- A 2 px hairline on the tile edge, so the tile holds its shape on a dark Dock.',
    `- The glyph centred on its measured bounds, its longer side ${Math.round(grid.glyph * 100)}% of the tile. Every mark fills the same square of its box, the 16 units of the Lattices grid's 20, so overlaid the glyphs touch the same guides.`,
    '',
    `Favicons drop the margin: the tile runs edge to edge and the glyph grows ${Math.round((faviconGlyphScale - 1) * 100)}%, with no hairline. The touch icon is square and opaque, because iOS applies its own mask.`,
    '',
    '## Where they are used',
    '',
    '| Surface | Source |',
    '| --- | --- |',
    '| Tab and home screen icons on lattices.dev | Chosen per route by `src/lib/brand.ts` |',
    '| Social cards (`public/og*.png`) | `bun run og`, which reads the kits |',
    '| Native app icons | The `.icns` files listed in each kit README |',
    '',
  ]
  return lines.join('\n')
}

const requested = process.argv.slice(2)
const unknown = requested.filter((slug) => !products.some((product) => product.slug === slug))
if (unknown.length) {
  console.error(`unknown product: ${unknown.join(', ')}. Choose from ${products.map((p) => p.slug).join(', ')}.`)
  process.exit(2)
}
const selected = requested.length ? products.filter((product) => requested.includes(product.slug)) : products
const canBuildIcns = process.platform === 'darwin'

for (const product of selected) {
  const { slug } = product
  const out = join(brandDir, slug)
  await mkdir(out, { recursive: true })

  for (const theme of themes) {
    const svg = renderToStaticMarkup(product.mark(theme))
    await writeFile(join(out, `${slug}-${theme}.svg`), svg)
    for (const size of ladder) await png(svg, size, join(out, `${slug}-${theme}-${size}.png`))
  }

  const bounds = await glyphBounds(product)
  const inset = grid.inset
  const body = { x: inset, y: inset, width: grid.canvas - inset * 2, height: grid.canvas - inset * 2 }
  const full = { x: 0, y: 0, width: grid.canvas, height: grid.canvas }

  const icon = composeIcon(product, bounds, { body })
  await writeFile(join(out, `${slug}-icon.svg`), icon)
  for (const size of ladder) await png(icon, size, join(out, `${slug}-icon-${size}.png`))

  const favicon = composeIcon(product, bounds, { body: full, glyphScale: faviconGlyphScale, finish: false })
  await writeFile(join(out, `${slug}-favicon.svg`), favicon)

  const touch = composeIcon(product, bounds, { body: full, glyphScale: faviconGlyphScale, square: true, finish: false })
  await png(touch, 180, join(out, `${slug}-touch-icon.png`), grid.tile)

  await writeFile(join(out, 'README.md'), readme(product, bounds))

  if (product.iconPngs) {
    for (const size of product.iconPngs.sizes) {
      await png(icon, size, join(repoRoot, product.iconPngs.dir, `${slug}-icon-${size}.png`))
    }
  }
  if (product.iconSvg) await writeFile(join(repoRoot, product.iconSvg), icon)
  if (slug === 'lattices') await writeFile(join(siteDir, 'public', 'favicon.svg'), favicon)

  if (canBuildIcns) await writeIcns(product, icon)
  const icns = canBuildIcns ? product.icns : []
  console.log(`${slug}: ${relative(repoRoot, out)}${icns.length ? ` + ${icns.join(', ')}` : ''}`)
}

await writeFile(join(brandDir, 'README.md'), indexReadme())

if (!canBuildIcns) console.log('Skipped .icns files: iconutil needs macOS.')
