# Blink configuration — agent-first

Blink's behavior and theme live in one human/agent-editable JSON file:

```
~/Library/Application Support/Blink/config.json
```

**Any process may edit this file.** Blink watches it and hot-applies changes to
every open panel within a second — no restart, no IPC, no permission dance.
That's the agent surface: read the file, write the file, done.

Rules:
- Every field is optional. Missing fields use the defaults below. `{}` is a valid config.
- Invalid JSON never breaks the app: Blink keeps the last good config and logs
  `[BLINK] config invalid — keeping last good`.
- Write atomically (write temp + rename, or your editor's normal save) — Blink
  watches the directory, so atomic replaces are picked up fine.
- The settings window is a *view* over this file; edits there round-trip through it.

## Schema

```jsonc
{
  "appearance": "auto",         // app-wide light/dark: "auto" (follow macOS) | "light" | "dark"
                                // "auto" tracks the system live; menubar → Appearance overrides it
  "behavior": {
    "restoreSession": true,     // reopen last session's panels at launch
    "defaultMode": "read",      // "read" | "edit" — mode for notes with no remembered mode
    "launchAtLogin": false      // register Blink as a login item (SMAppService)
  },
  "hotkeys": {
    // Chord strings: modifiers joined by "+", ending in one key.
    // Modifiers: hyper (⌃⌥⇧⌘), cmd, ctrl, alt, shift.
    // Keys: a–z, 0–9, punctuation (. , / ; ' [ ] \ - = `), space, return,
    // tab, escape, delete. An invalid chord is logged and the previous
    // binding kept — a bad edit never leaves the app unreachable.
    "newNote": "hyper+n",       // global — create a note from anywhere
    "blink": "hyper+b",         // global — show all notes / hide all
    "grid": "hyper+c",          // global — grid/constellation overlay ("c" — hyper+g collides with Lattices)
    "toggleMode": "cmd+shift+p",// per-panel — flip read/edit
    "focus": "cmd+.",           // per-panel — quiet everything else
    "toggleChrome": "cmd+shift+t" // per-panel — pin the chrome rail after hover leaves
  },
  "panel": {
    "sheet": "glass",           // sheet template: "glass" | "card" | "dotted" | "bracket" | "marginalia"
                                // per-note override: a `sheet:` frontmatter key in the note file
    "material": "hud",          // glass material: "hud" | "underWindow" | "popover" | "sidebar" | "menu"
    "cornerRadius": 12,
    "tintRead": 0.28,           // 0–1 black tint over the glass in read mode (contrast floor)
    "tintEdit": 0.38,           // 0–1 tint in edit mode (focused writing surface)
    "shadow": true,             // window drop shadow
    "defaultWidth": 420,        // size for panels opening for the first time
    "defaultHeight": 340,
    "background": null,         // optional CSS color; null keeps the glass sheet transparent
    "mark": null,               // optional identity mark from $BLINK_HOME/attachments
    "chrome": "rail"            // where the ✕ and mode toggle live:
                                // "rail"   — a detached strip above the note, off the page.
                                //            Shown on hover (or pinned with hotkeys.toggleChrome);
                                //            the strip stays reachable across the seam. Idle notes
                                //            stay bare. Edit mode does not force it.
                                // "inside" — the original hover-earned chrome floating over
                                //            the note's own top corners.
  },
  "focus": {
    "dim": 0.30                 // 0–1 strength of the focus-mode veil over everything else
  },
  "drape": {                    // a backdrop parked BEHIND every note — a calm stage under the set
    "enabled": false,           // off by default; true parks a full-screen blur+dim behind the notes
    "dim": 0.45,                // 0–1 black tint over the blurred backdrop
    "opacity": 1.0,             // 0–1 overall presence; lower = a lighter veil the desktop shows through
    "material": "hud"           // blur material: "hud" | "underWindow" | "popover" | "sidebar" | "menu"
  },
  "motion": {                   // Arrival: every show/hide is choreographed
    "entrance": "shimmer",      // "shimmer" | "drop" | "draw" | "none" — how a note lands
    "durationMs": 260,          // base duration for one panel's entrance
    "staggerMs": 40,            // per-panel delay in group reveals (session restore, the blink)
    "enabled": true             // master switch — false = instant show/hide (today's behavior)
  },
  "physics": {                  // panel physics: how a note behaves under the hand
    "flingEnabled": true,       // throw a panel by its top band — it glides on and bounces off screen edges
    "flingFriction": 3.2,       // exponential glide friction (1/s); higher = heavier, stops sooner
                                // (total glide distance ≈ release speed / flingFriction)
    "flingMinVelocity": 900,    // release speed (pt/s) that starts a glide; below it the panel just stays
    "bounceDamping": 0.6,       // 0–1 velocity kept after an edge bounce
    "shakeEnabled": true        // shake side-to-side during a drag to fold the panel into its band (shade);
                                // shake again — or double-click the band — to restore
  },
  "editor": {                   // typography & colors, applied to editor AND reader
    "fontFamily": null,         // null → system font stack; any CSS font-family string
    "monoFamily": null,         // null → ui-monospace stack
    "titleFamily": null,        // null → body stack; headings/titles only
    "fontSize": 13,             // px
    "lineHeight": 1.75,
    "paddingX": 20,             // px
    "paddingY": 16,
    "textColor": null,          // any CSS color; null → rgba(255,255,255,0.85)
    "textStrongColor": null,    // headings/bold; default rgba(255,255,255,0.96)
    "textMutedColor": null,     // markers/list bullets; default rgba(255,255,255,0.45)
    "dimColor": null,           // Markdown syntax markers
    "borderColor": null,        // rules, quote borders, sheet frame
    "accentColor": null,        // links; default rgba(158,203,255,0.9)
    "accentDimColor": null,      // source-mode link targets
    "codeBackground": null,     // default rgba(255,255,255,0.07)
    "codeTextColor": null,       // inline + block code ink
    "caretColor": null,         // default white
    "selectionColor": null,     // default rgba(255,255,255,0.18)
    "h1Size": null,             // px, reader scale; default 20 (editor derives slightly smaller)
    "h2Size": null,             // default 17
    "h3Size": null              // default 15
  }
}
```

## How it applies

- `panel.*` and `focus.*` are native (NSVisualEffectView material, tint layers,
  window shadow, overlay dim) — applied immediately to all open panels.
- `hotkeys.*` hot-apply too: global chords re-register with Carbon on change;
  panel chords are read live on each keypress.
- `behavior.launchAtLogin` syncs the macOS login item on change.
- `motion.*` choreographs every show/hide (see **Motion (Arrival)** below);
  applied live, so the next note you open — or the next Hyper+B — uses the new
  feel. `enabled: false` restores the instant behavior exactly.
- `physics.*` is read at each gesture, so edits apply to the very next drag —
  see **Panel physics** below. macOS **Reduce Motion** disables the fling and
  shake gestures regardless of these values.
- `editor.*` maps to the web bundle's CSS custom properties
  (`--blink-font-size`, `--blink-text`, …) and is pushed over the bridge via
  `window.blink.setTheme`. The full variable table lives in
  `web/editor/README.md`.

## Examples

Cozy serif reading, warmer accent, softer glass:

```json
{
  "editor": {
    "fontFamily": "Charter, Georgia, serif",
    "fontSize": 14,
    "lineHeight": 1.8,
    "accentColor": "rgba(255,196,150,0.9)"
  },
  "panel": { "tintRead": 0.12, "cornerRadius": 16 }
}
```

Maximum-contrast writing mode:

```json
{
  "panel": { "tintEdit": 0.6 },
  "focus": { "dim": 0.45 }
}
```

Reusable treatment with a restrained identity mark (a neutral house style —
substitute your own colors, faces, and mark):

```json
{
  "styles": {
    "terminal": {
      "background": "#070908",
      "text": "#f2f4ef",
      "textStrong": "#f2f4ef",
      "textMuted": "#aab1a7",
      "dim": "#777e75",
      "border": "rgba(239,244,237,.09)",
      "accent": "#a6ef87",
      "accentDim": "rgba(166,239,135,.58)",
      "font": "\"JetBrains Mono\", ui-monospace, Menlo, monospace",
      "mono": "\"JetBrains Mono\", ui-monospace, Menlo, monospace",
      "titleFont": "\"JetBrains Mono\", ui-monospace, Menlo, monospace",
      "codeBackground": "#111411",
      "codeText": "#f2f4ef",
      "caret": "#a6ef87",
      "selection": "rgba(166,239,135,.1)",
      "radius": 6,
      "mark": "marks/terminal.svg"
    }
  }
}
```

`panel.mark`, `styles.<name>.mark`, and a workspace brand's `mark` are relative
paths under `$BLINK_HOME/attachments` (or the default Blink attachments
directory). The mark appears at 20px in a 24pt top-left chrome cell and yields
that position to the close control on hover. Marked themes receive a compact
content gutter so the identity never overlaps the first heading or editor
source. Keeping it in the treatment instead of the markdown body preserves the
note as portable, presentation-free Markdown. Absolute paths and paths escaping
the attachments directory are ignored — `blink workspace brand … --install-mark`
copies an asset into bounds for you.

Treatments are partial overlays. In addition to the original
`sheet`/`accent`/`font`/`fontSize`/`lineHeight`/`tint*`/`radius` fields, they
accept `background`, `text`, `textStrong`, `textMuted`, `accentDim`, `mono`,
`titleFont`, `dim`, `border`, `codeBackground`, `codeText`, `caret`, and
`selection`. These map to the same editor and sheet variables as their global
config counterparts, but apply only to notes that reference that named style.

## Workspaces

A **workspace** is a named group of notes plus the brand they render under. The
definition lives here; membership lives in each note's `blink.workspace`
frontmatter key, so note markdown never carries a color, face, or asset path.

```json
{
  "workspaces": {
    "acme-docs": {
      "title": "Acme Documentation",
      "style": "terminal",
      "brand": {
        "accent": "#7aa2f7",
        "background": "#0b0d0c",
        "radius": 6,
        "mark": "marks/acme-docs.svg"
      }
    }
  }
}
```

`style` names an entry in `styles` to use as a base; `brand` is a treatment
overlaid on top of it, so several workspaces can share one house style and tint
it differently. Both are optional — a workspace with neither is unbranded, and
its notes render with Blink's defaults.

A note's look resolves least-specific first, so **later wins**:

```
config defaults ← workspaces[blink.workspace].brand ← styles[blink.style] ← loose blink: keys
```

Unknown workspace and style names contribute nothing rather than failing, so a
note whose workspace was forgotten still opens — just unbranded. Agents should
drive this through `blink workspace` (see `docs/workspaces.md`) rather than
hand-editing, because the CLI writes only the `workspaces` key and leaves every
other config key byte-for-byte intact.

## Motion (Arrival)

Notes don't appear — they land. Every show/hide is choreographed, with the
character set by `motion.*` so a theme ships a matching feel. All of it no-ops
cleanly when `motion.enabled` is `false`, and macOS **Reduce Motion**
(System Settings → Accessibility → Display) is always honored as `"none"`.

Entrances (`motion.entrance`):

- **shimmer** — content fades up from nothing while a soft highlight sweep
  crosses the sheet left→right.
- **drop** — the panel drifts down ~8pt into place with a slight overshoot
  settle as the content fades in.
- **draw** — on flat sheets (`dotted`/`bracket`/`marginalia`) the frame draws
  itself on, then the text fades in behind it. On `glass`/`card` (no frame to
  draw) it falls back to **shimmer**.
- **none** — instant (today's behavior).

Where the choreography shows up:

- **Opening a note** (new note, popover, focusing) plays one entrance.
- **Session restore** staggers the reopened panels `staggerMs` apart,
  left-to-right by on-screen position, so the desk assembles.
- **The blink** (Hyper+B): the reveal staggers panels in from their screen-edge
  direction; the hide is one synchronized exhale (all panels fade + drift
  outward together, then vanish). The state flips instantly regardless — the
  motion is garnish, and rapid toggles never leave a panel half-faded. Pending
  saves and the open-notes list are untouched.
- **Focus mode** recedes the non-key panels a hair (a subtle depth cue), so the
  note you're writing stands proud. Transform-only — window positions never
  move.

## Panel physics

Notes aren't just placed — they can be thrown. `physics.*` governs the two
gestures on a panel's top band (the invisible 24pt drag strip along its top
edge):

- **Fling.** Drag a panel and release it with speed: it glides on with
  momentum, decays exponentially (`flingFriction`), and bounces off the edges
  of the screen it's mostly on, keeping `bounceDamping` of its speed per hit.
  Below `flingMinVelocity` a release is just a drop. Any new grab, close, or
  programmatic placement kills a glide mid-flight.
- **Shake-to-shade.** Shake the panel side-to-side mid-drag (~3 reversals in
  0.6s, ≥40pt each, little vertical travel) and it folds up into its top band,
  windowshade-style. Shake again — or double-click the band — and it unfolds
  back to its full frame. Resizing is pinned while shaded so nothing fights
  the fold.

Geometry is persisted only when a panel is at rest — never mid-glide — and
always as the UNSHADED frame, so a note that was shaded when Blink quit still
relaunches full-size. The shaded state itself is session-only.

## What does NOT live here

- Notes themselves: `~/Library/Application Support/Blink/Notes/*.md` (frontmattered
  markdown). Agents may write their own frontmatter keys into a note — Blink preserves
  unknown keys verbatim through every save, and merges on-disk metadata (tags, pinned,
  foreign keys) before each content save, so editing a note's frontmatter while it's
  open in a panel is safe.
- Per-machine workspace state (open panels, per-note modes, window frames):
  UserDefaults today, with a planned migration to `.blink/workspace.json`.
