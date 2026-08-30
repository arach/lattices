# Blink iOS — Ledger

Pure visual direction by **Kimi**, returned through Scout as
`ref:0-4qjlsi`. Product behavior is deliberately unchanged.

## Thesis

Blink on iOS should be a page from the same book as the macOS capture popover,
not a rounded cousin. Notes become entries in a ruled field log: sharp corners,
numbered rows, mono metadata, and signal blue reserved for scope, selection,
and sync.

## Composition

- Standard large-title navigation with `blink` and native toolbar controls.
- Native top search field; the floating bottom dock is intentionally rejected.
- A 44pt, full-width sync strip with a six-point **square** state pip.
- `LOG / ALL NOTES · N REC` sits directly on the canvas.
- Full-bleed zero-radius rows with numbered mono indices, hairlines, and a
  two-point selection rule.
- Reader: flat canvas, mono kicker, New York title, one metadata line, and no
  decorative material.

## Tokens

| Token | Light | Dark |
| --- | --- | --- |
| canvas | `#F3EEE2` | `#0C0E10` |
| raised | `#FAF6EC` | `#131619` |
| hairline | `#D8CDB6` | `#262B30` |
| ink | `#1A1915` | `#E8E9E4` |
| secondary | `#5A5446` | `#9BA09C` |
| faint | `#746C5F` | `#7C8280` |
| signal | `#2D5DAF` | `#7FA9F5` |
| amber | `#8B6B2F` | `#D6B96C` |

No gradients, shadows, or blur materials. Dark mode is neutral graphite rather
than the landing page's forest.

## Row anatomy

`%02d` index or signal pin → title + short relative time → two-line excerpt →
uppercase workspace + first tag. The disclosure chevron is removed. Selected
rows receive only a signal wash and a two-point leading rule.

## Must have

1. Zero-radius ruled rows—no card stack, rounded sync card, or floating search.
2. A square sync pip paired with explicit state copy.
3. SF Pro for content, SF Mono for telemetry, and New York only in the reader.
4. Neutral graphite dark mode and one signal-blue accent.
5. iPad keeps the same ruled list in a 320pt sidebar with a flat reader column.

## Optional flourish

- Numbered rows may be cut if density becomes too mechanical.
- The syncing pip may blink at the landing page's 1.06s caret cadence.
- Search matches may receive a restrained signal tint.
- Pins may replace rather than precede the row index.
