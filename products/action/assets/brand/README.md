# Action's mark

A play triangle breaking out of four capture-corner marks. The marks are the
frame Action puts around a region; the triangle is the take.

The triangle crosses the right-hand marks rather than sitting politely inside
them, and the marks are cut away where it passes — a real path subtraction, so
the same path fills identically in CoreGraphics, in an `NSImage`, and in a
SwiftUI `Shape`. Without that clearance the crossing reads as a collision, and
below about four units of it the gap closes up at menu bar size.

An earlier round drew a capital A with the play triangle as its counter. It was
rejected as too on the nose: a letter A for an app called Action says the name,
not the job. The frame says the job.

## Where it comes from

`native/engine/CoreSources/ActionBrandMark.swift` is the source of truth. Every
surface draws from that one set of numbers:

| Surface | Drawn by | Colour source |
| --- | --- | --- |
| App icon (`Action.icns`) | `scripts/render-app-icon.swift` | baked, see below |
| In-app brand chip | `ActionBrandTile` in `Sources/ActionBrandMarkView.swift` | live theme |
| Menu bar status item | `ActionBrandMark.statusItemImage(live:)` | template, or coral |

The geometry lives in Core rather than in the app target so the `.icns` on disk
and the mark the app draws at runtime cannot drift apart.

## Colour

The tile is the landing system's warm paper, the capture marks are graphite, and
the play triangle is coral. That split is deliberate: the landing brief reserves
coral for runtime truth — recording state, selected trace event, current target,
primary CTA — so it lands on the take and nowhere else.

| Role | Token | Value |
| --- | --- | --- |
| Tile | paper | `#F3EBDD` |
| Tile foot wash | paper shadow | `#DCCFB9` at 45% |
| Capture marks | graphite | `#20282B` |
| Play triangle | coral | `#EF6A47` |

The in-app chip reads `StageHUDTheme` instead of these constants, so it follows a
theme switch. An `.icns` cannot, which is the one place the two are allowed to
differ.

## Menu bar

At rest the status item is a **template** image: the system tints it for the
current appearance and inverts it on highlight, like every other extra. While a
drive holds the machine it is drawn in coral instead — the same thing coral means
everywhere else. A template image cannot carry colour, so the live variant gives
up template tinting; a coral mark is legible against both a light and a dark bar.

Liveness comes from `ActionSupervisionRegistry.activeRegistrations()`, polled
every two seconds. It is polled rather than watched because a lease can lapse by
running past its TTL, and an expiry writes nothing a file-system watcher sees.

## Regenerating the icon

```sh
native/engine/scripts/build-app-icon.sh
```

Writes `Action.icns` plus `action-icon-512.png` and `action-icon-1024.png` here.
Commit the result — `build-app.sh` copies the `.icns`, it does not build it, so
an ordinary app build stays fast.

## Earlier work

`explorations/` holds the first round of mark studies. `02-stage-frame.svg` is
this mark's direct ancestor — viewport corner brackets around a play triangle,
with a coral record dot. `01-capture-a.svg` is the letter-A branch that was not
taken. `landing/` holds the landing-page art and its palette.
