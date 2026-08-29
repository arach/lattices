# Theming Action

> How to write a theme for Action's native app, and what the app will refuse to
> paint with. Written for an agent that has been asked to personalise the UI.

## The short version

Write a JSON file into `~/Library/Application Support/Action/Themes/`. The app
picks it up within a fraction of a second — no restart, no protocol call. Select
it in **Settings ▸ Appearance ▸ Palette**, or set it directly before launching the app (changing this default while Action is running requires a relaunch):

```bash
defaults write dev.lattices.Action Action.ThemeID "reading-room"
```

A theme is a **patch**, not a palette. Everything is optional, and what you do
not mention keeps the tuning it already had. The smallest useful theme is six
lines.

## The model

Action has four surfaces, and they are not variations of each other:

| Surface  | Where | Voice |
|----------|-------|-------|
| `chrome` | The launcher shell: rail, footer, cards, ledgers | Neutral. The frame around the work, not the work. |
| `field`  | Home | The brand's own: paper in light, graphite in dark. |
| `review` | The review screen | A cool neutral sheet, so the page never fights the thing being reviewed. |
| `hud`    | The capture HUD | A fixed dark instrument face. Deliberately the same in both appearances. |

Each of `chrome`, `field` and `review` is an `ActionSurface`: a ground, the
things that sit on it, the lines that divide it, the ink that goes on it, and
the two colours it speaks with.

```
canvas ─── the page
  band ─── a chrome band across an edge of it (rail, title bar, footer)
  panel ── a card laid on it          panelRaised ── the same card, hovered
  recess ─ a well cut into it         deep ───────── the block that stays dark
  edge · rule · grid · shadow ─────── the lines
  ink · inkSecondary · inkRow · inkMuted · inkMeta ── the ramp, darkest first
  onDeep · onDeepMeta ─────────────── what goes on `deep`
  accent · accentInk · accentSoft ─── runtime truth
  signal ──────────────────────────── the secondary voice, never competing
```

Two rules the palette encodes, and a theme should not break:

- **Coral means this Mac is being driven right now.** It is the same value in
  light and in dark on purpose. The colour that means "running" must not depend
  on the operator's appearance setting.
- **A recess sits *below* the canvas where a panel sits above it.** Panels are
  content on the surface; a recess is a window cut into it showing the machine's
  state. Inverting that inverts the hierarchy.

## Three levels of reach

Use the coarsest one that does the job. A file may use all three.

### 1. `seed` — regrow a whole surface

Give a surface a ground, an ink and an accent and the other eighteen slots are
computed:

```json
{
  "id": "dusk",
  "name": "Dusk",
  "extends": "action",
  "surfaces": {
    "field": {
      "seed": {
        "ground": { "light": "#EFEAE0", "dark": "#101415" },
        "ink":    { "light": "#1C2427", "dark": "#EFEAE0" },
        "accent": "#EF6A47",
        "signal": "#1FB9C6",
        "lift": 1.1
      }
    }
  }
}
```

Seed fields: `ground`, `ink`, `accent` (required); `signal`, `deep`, `lift`
(optional; `lift` defaults to 1 and scales how far apart the grounds sit).

The derivation works in **L\***, not in "mix N% toward white", because those are
not the same move on paper and on graphite. Seeded with Action's own ground and
ink it reproduces the shipped surface to within about three L\* on every ground and
every ink step. What it deliberately does *not* reproduce:

- `inkMuted` — Action's field tan is a decision, not a point on a ramp. Override
  it if you care about it. It is the single slot most worth overriding.
- `accentInk` — the derivation picks whichever of the ink and the ground the
  accent can actually carry. Action's own cream-on-coral is 2.8:1 and the
  derivation would pick the darker option instead.

### 2. `tokens` — patch named slots on a surface

```json
"surfaces": {
  "field": {
    "tokens": { "inkMuted": { "light": "#9C7452", "dark": "#7B8785" } }
  }
}
```

Any of the 21 slot names listed above. A name that is not a slot is reported as
an error rather than ignored.

### 3. `overrides` — patch one painted token

The last resort, for the one place a rule does not fit. Keys are the app-facing
token names (`fieldCanvas`, `runSelectionHover`, `hudCoral`, …) — the full list
is `ActionToken` in `native/engine/Sources/ActionTheme.swift`.

```json
"overrides": { "rowAlternate": { "light": "#00000008", "dark": "#FFFFFF0A" } }
```

## The rest of the file

```jsonc
{
  "id": "dusk",                 // required, unique; the value Action.ThemeID takes
  "name": "Dusk",               // shown in the picker
  "author": "…",
  "summary": "One sentence, shown under the picker.",
  "extends": "action",          // built-in theme to start from; defaults to "action"

  "status":  { "ok": "#2E8B57", "failed": "…", … },   // run outcomes + ledger washes
  "control": { "primaryTop": "…", "primaryBottom": "…" },
  "hud":     { "coral": "…", "coralHot": "…", "cyan": "…", "amber": "…", "polish": 1.0 },

  "metrics": {
    "cornerRadius": 8,          // cards and panels
    "cornerRadiusSmall": 6,     // chips, buttons, selection washes
    "hairline": 1,
    "density": 1.0,             // row heights and padding, 0.85 … 1.35
    "grain": 1.0,               // every texture alpha
    "shadowStrength": 1.0
  },

  "type": {
    "editorial": "Charter",     // "system" or a missing face falls back to New York
    "mono": "JetBrains Mono",   // a missing face falls back to the platform monospace
    "scale": 1.0                // 0.85 … 1.3, applied to the whole scale
  }
}
```

`extends` accepts built-in theme IDs only; file themes do not form inheritance chains.

`status` slots: `ok`, `running`, `failed`, `stopped`, `recording`, `paused`,
`rowAlternate`, `selection`, `selectionHover`, `actionChip`.

The HUD only accepts tints and a `polish` level. It does not accept its
machining, on purpose: a theme that could restyle the capture HUD could change
what "recording" looks like on a Mac somebody else is driving.

### Colour spelling

Two forms, both accepted anywhere a colour is:

```json
"accent": "#EF6A47"
"canvas": { "light": "#F3EBDD", "dark": "#14191A" }
```

`#RGB`, `#RRGGBB` and `#RRGGBBAA` all parse. A malformed value is an error that
names the key — it is never silently replaced with a default.

## What the app checks before it paints

Every theme is validated **in both appearances** before installation. This is
the half a human skips, because they are only looking at one mode.

**Contrast.** Twenty foreground/background pairs the app actually renders, each
against the ratio it needs — 4.5:1 for body text, 3.0:1 for status dots, chips
and large text. Alpha is composited onto the background first, so a muted ink
written as "ink at 55%" is scored as what is actually seen.

**Separation.** Five pairs of grounds that have to stay at least 1.2 L\* apart,
or the hierarchy they encode disappears — a card that is the same colour as the
page is not a card.

**Alarm distinction.** The accent and idle accent are compared with the failure
colour. Below 28 ΔE they are close enough that a 6pt dot or a 2pt rule in one
can be mistaken for the other, and you are told so. Only pairs your theme
actually moved are checked — an accent you inherited unchanged is the base
theme's decision, not yours. This check is advisory and never blocks
installation.

For contrast only, a result below three quarters of its target is an **error**;
other contrast failures are warnings. Separation and alarm findings are always
warnings.

- **Warnings** are shown in Settings ▸ Appearance and the theme still installs.
- **Errors** mean the theme is *not* installed. Action keeps painting with the
  built-in one and shows you why in the same place.

So the iteration loop is: write the file, look at Settings ▸ Appearance, fix what
it tells you, save again. The app reloads on every write.

## Worked examples

`themes/linea-dusk.json` — a complete imported palette. `themes/reading-room.json`
— metrics and type only, for a recording an audience watches from across a room.
Copy either into the themes folder to try it.

## Where things live

| | |
|---|---|
| `native/engine/Sources/ActionTheme.swift` | Surfaces, seeds, the derivation, the token list |
| `native/engine/Sources/ActionThemeBuiltin.swift` | The house theme, transcribed slot for slot |
| `native/engine/Sources/ActionThemeSpec.swift` | The file format, the merge, the validator |
| `native/engine/Sources/ActionThemeStore.swift` | Loading, watching, installing |
| `native/engine/Sources/StageHUDTheme.swift` | The façade views paint through |
| `themes/` | Worked examples |
