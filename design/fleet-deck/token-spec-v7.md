# Fleet Deck — Token Spec v7

**Author:** kimi (taste), via #fleet-deck · 2026-07-30
**Brief (Arach, verbatim):** "full font sizes, smaller is better, fewest possible colors, no mono / technical vibe across the board"
**Replaces:** `LatsPalette`/`LatsFont` (`apps/ios/Sources/LatsDeckScreen.swift:7-57`) and `FleetV6` (`apps/ios/Sources/FleetDeck/FleetDeckTheme.swift`) with one enum — `DeckTheme`. One Swift file, no gradients, no per-component one-offs.

Framing: the app is a remote control, and should look like the OS it lives on rather than the thing it points at.

**Corrected 2026-07-30 (Arach):** kimi's original framing was "operates terminals". It doesn't. This app operates *agents* (Scout-brokered), *dictation*, and the Mac's window/input surface. Nothing here is a terminal.

That removes the spec's only mono exception. `LatticesDeckHost.swift:1493` is the single record site for the activity log — `tag: "DECK"`, `text: outcome.summary` — so every line is a prose summary of an action, never columnar output. Prose set in mono is the terminal-cosplay this spec exists to kill. **The iPad companion has no mono face at all.** See §6.

## 1. Surfaces — five levels, all opaque

v6 had six named surfaces plus five machined gradients. The real count is five, and only three are structural.

| Token | Hex | Role |
|---|---|---|
| `canvas` | `#0D0F12` | root background |
| `well` | `#0A0B0D` | **recessed group** (channel strip, log screen, voice bar). Depth −1 |
| `card` | `#131518` | **flush item** (card, tile, list row). Depth +1 |
| `raised` | `#181B1F` | focused/hero console, popovers, sheets. Never ordinary cards |
| `control` | `#1E2126` | buttons, keycaps, inputs, chips — anything tappable inside a card |

`well`/`card` around `canvas` *is* the two-level depth model: down for groups, up for items, nothing between. Steps are ~4–5% luminance apart. If two adjacent surfaces don't need a visible seam, they are the same level — don't invent a sixth.

**Deleted:** `padBG`, `deckPanelBG`, `statusBG`, `tilesWrapBG` → `canvas`/`well`. `heroBG` gradient → `raised`. `bezel`, `keycap`, `keycapHover`, `tileFace`, `dome` → flat `control`/`card`. `FleetPanelGrid` dies with the engineering grid. `FleetCornerTicks` dies — a recently-changed card gets a `hairlineStrong` stroke.

## 2. Text ramp — keep v6's four, renamed

| Token | Hex | Role |
|---|---|---|
| `text` | `#E2E2DF` | titles, names, primary values |
| `textSecondary` | `#A0A09B` | metadata, secondary rows, icons |
| `textTertiary` | `#71716C` | captions, timestamps, quiet content |
| `textDisabled` | `#4A4A4D` | disabled |

Values unchanged. Warm-neutral is why the amber doesn't vibrate on it; already opaque; four steps matches the four roles the UI actually has.

**Deleted:** `LatsPalette.text/textDim/textFaint` (alpha whites), `tileIcon #CEC6B9` → `textSecondary`.

## 3. Hairlines — two, mostly forbidden

- `hairline` — white 8%. Stroke on a flush card; separator between sibling rows when gap < 8pt.
- `hairlineStrong` — white 14%. Focused/selected/recently-changed card stroke. The only "look at me" that isn't amber.

**Not allowed:** between well and canvas (spacing does the recess), between sections inside one card, under card heads. No dotted rules, no black seams.

**Deleted:** `dotted`, `seam`, `cardBR`, `heroBR`, `FleetDottedRule`, the keycap black stroke. `brk`/`brk2` and `hairline`/`hairline2` collapse into the two above.

## 4. Radii — 4 / 8 / 12, continuous

`radiusSmall` 4 (chips, badges) · `radiusCard` 8 (cards, tiles, controls) · `radiusWell` 12 (wells, panels, sheets). All `.continuous`; concentric rule outer = inner + padding. Resolves the 8/6 vs 10/12/5 disagreement.

## 5. The two hues

- `accent` `#E4B65C` — attention **and** selection
- `accentPressed` `#C29B4E` (× 0.85 brightness)
- `accentFill` — accent @ 14%, selected-row / active-toggle fill
- `error` `#EA6A64`
- `errorPressed` `#C85A55` (× 0.85)
- `errorFill` — error @ 14%

Disabled accent = accent @ 35%, but prefer `textDisabled` for disabled controls.

**Deleted:** green, teal, blue, violet, pink (both files), the entire `LatsTint` enum, `agentHues`/`agentHue(_:)`. Where a tint string arrives over the wire, drop the colour, keep the icon.

## 6. Type — four sizes, SF Pro, no tracking, no uppercase

| Token | Spec | Role |
|---|---|---|
| `title` | 17 semibold | console names, the decision question, sheet titles |
| `body` | 15 regular | primary rows, channel names, input text |
| `secondary` | 13 regular | metadata, descriptions |
| `caption` | 11 regular | timestamps, status words, former micro-labels (sentence case) |

**No `log` token.** kimi's draft carved out `12 regular monospaced` for "log/terminal content". Corrected: there is no terminal content. The activity log is prose (`outcome.summary`), so it renders in `secondary` like any other narrative row. Mono appears nowhere in the iPad app.

### Two faces, split by voice — not by data type

**Arach, 2026-07-30:** a distinction between the system face and a user-communication face is wanted.

The split is *who is speaking*, not *what shape the data is*:

| Face | Token prefix | Used for |
|---|---|---|
| **SF Pro** (system) | `title` / `body` / `secondary` / `caption` | all chrome — names, labels, metadata, buttons, status, counts |
| **Serif** (communication) | `said` / `saidSecondary` | utterances: the agent's decision question, voice transcript, agent messages |

- `said` — 17 regular serif. The decision question; anything an agent is asking you.
- `saidSecondary` — 15 regular serif. Voice transcript, agent message bodies.

This reinstates the serif kimi first flagged as "the one warm, non-technical gesture in v6" and then cut under "fewest possible". With the axis named it earns its place: the serif is not decoration, it marks *someone is talking to you* — which is the entire point of a surface whose signature state is an agent blocked on a human.

Chrome never uses it. Two faces, one job each.

Fifth/sixth sizes today: `FleetLabel`'s 10pt tracked caps → `caption` in `textTertiary`; stray 12pt chrome → `secondary`/`caption`; 26pt status numerals → `title`.

**Deleted:** `LatsFont.mono`/`ui`, `FleetV6.mono` as a chrome face, `FleetV6.serif` — the decision question becomes `title`. *"The serif was the design performing thoughtfulness; the OS doesn't do that."*

## 7. States without green

Running is default-healthy, so running looks like **nothing**.

- **Running** — no dot, no colour. Icon `textSecondary`, name `text`. Health is absence of signal.
- **Idle** — row demoted to `textTertiary`; 6pt hollow dot (1pt `textTertiary` stroke, no fill).
- **Needs you** — 6pt filled `accent` dot, soft amber glow (radius 4 @ 60%), plus an `accent` caption word where a reason fits ("reply?", "approval"). Never amber the whole row.
- **Error** — same construction in `error`, with `errorFill` behind the row only while unresolved.
- **Selected/focused** — structural, not chromatic: `raised` fill or `hairlineStrong` stroke. **Selection is not attention.**

## 8. Spacing — 8pt grid

`space2 · space4 · space8 · space12 · space16 · space24 · space32`

Screen margins 16 · card padding 16h/14v (the 14 is v6's own interior rhythm — keep) · well inner padding 12 · sibling card gap 8 · section gap in a card 12 · icon↔label 8 · between major regions 16.

`FleetV6.M` heights (topBar 26, channels 158, voiceBar 58, …) stay as layout constants where used — geometry, not theme. Don't port them into the enum.

## Migration map (no orphans)

- `LatsPalette.bgEdge/bg` → `canvas`; `surface`/`surface2` → `card`/`raised` by role
- `LatsPalette.hairline/2`, `FleetV6.brk/brk2` → `hairline`/`hairlineStrong`
- `wellBG` → `well`; `cardBG`, `tilesWrapBG` → `card`
- all gradients (`heroBG`, `padBG`, `deckPanelBG`, `statusBG`, `bezel`, `keycap(+Hover)`, `tileFace`, `dome`) → flat `canvas`/`raised`/`control`
- `fg`…`fg4` → `text`…`textDisabled`
- `LatsTint`, `agentHues`, green/teal/blue/violet/pink, `tileIcon` → deleted
- `FleetLabel`, chrome `mono`, `serif` → `title`/`body`/`secondary`/`caption`; log `mono` → `log`
- `FleetPanelGrid`, `FleetDottedRule`, `FleetCornerTicks` → deleted
- `FleetWell`/`FleetCard` survive as components, re-skinned: flat fills, hairline on cards only, wells defined by fill alone

## Open question: mono on the Mac command bar

**Flagged assumption:** this spec governs the iPad companion; the Mac's locked JetBrains Mono command bar is untouched.

kimi's view, verbatim:

> It holds. The companion reads as a companion through shared surfaces, the grey ramp, the amber, the spacing rhythm, and the channel-strip IA — none of which is a typeface. The Mac's mono command bar is a keyboard-platform power affordance; the iPad is glance-and-tap, and SF Pro is correct there. The two are never on screen at once, so forcing one face buys invisible consistency at the cost of making one platform worse.
>
> The thread worth keeping: log/terminal content is mono on both (SF Mono on iPad is fine — content, not chrome). Chrome speaks each OS's native voice; the data is what sounds the same.
>
> If Arach rules one typeface everywhere, the cost is iPad chrome going mono — the terminal-cosplay this spec exists to kill. I'd push back.
