---
title: Workspace Map
description: Read-only terminal and JSON views of the current macOS workspace
order: 5.5
---

`lattices map` is a read-only **drawing** of the current desktop. The structured
read is `desktop.snapshot` (one call: frontmost, layer, displays, windows,
sessions, permissions). Map prefers that payload, then falls back to joining
`spaces.list` and `windows.list` on older app builds. It either draws a
proportional terminal diagram or returns a versioned JSON projection.

It does **not** open, focus, move, resize, or capture a macOS window. Its box
drawing exists only in the invoking terminal. This is separate from the
interactive **Studio / Screen Map** window and the **Hyper+3 HUD**.

## Terminal map

```bash
lattices map
```

Example with two differently sized, vertically offset displays
(`lattices map --width 110 --height 14`):

```text
Desktop 7280×2395 @ 0,0 · 2 displays · 4 windows · 1 cell ≈ 92×184 pt

╔═ D0 · AW3425DWM · Space 1 ═════════╗
║                                    ╠═ D1 · U32J59x · Space 7 ════════════════╗
║ ┌[2]┬[1] ChatGPT - ChatGPT───────┐ ║                                         ║
║ │   │      │                     │ ║ ┌[3] Chrome────────┐                    ║
║ │   │      │                     │ ║ │                  │                    ║
║ │   │      │                     │ ║ │                  │    ┌[4]─┐          ║
║ └───┴──────┘─────────────────────┘ ║ │                  │    │    │          ║
║                                    ║ │                  │    │    │          ║
╚════════════════════════════════════╣ │                  │    │    │          ║
                                     ║ │                  │    │    │          ║
                                     ║ │                  │    └────┘          ║
                                     ║ └──────────────────┘                    ║
                                     ║                                         ║
                                     ╚═════════════════════════════════════════╝

Key · ╔═ display ═╗   ┌[1] frontmost window ─┐   ┌[n]──┘ others, numbered only
       lower n = nearer the front of its own display; n does not order across displays

Displays
  D0  Display 0 · AW3425DWM · Space 1  frame 3440×1440 @ 0,0       usable 3440×1410 @ 0,30
  D1  Display 1 · U32J59x · Space 7    frame 3840×2160 @ 3440,235  usable 3840×2130 @ 3440,265

Windows · front to back within each display
  1  D0  ChatGPT · ChatGPT      wid:114   2847×1410 @ 593,30
  2  D0  iTerm · lattices       wid:208   1235×1255 @ 0,30
  3  D1  Chrome · API docs      wid:3874  1920×2130 @ 3440,265
  4  D1  Simulator · iPhone 16  wid:146   447×950 @ 5783,913
```

The diagram uses each full display `frame` to build one global desktop viewport,
so displays above, below, left, right, or offset from the primary display retain
their real topology and relative dimensions. One uniform point-to-cell scale is
chosen for the entire canvas; displays are never independently normalized.
Windows use the display's usable `visibleFrame`, are clipped to that frame, and
remain positioned in the same global coordinate system. Only on-screen windows
on each display's current Space appear. `windows.list` is ordered front to back,
and the legend preserves that order: `[1]` is the frontmost window of its
display. Numbering runs continuously across displays, so `[4]` on D0 and `[5]`
on D1 have no z-relationship — depth is only meaningful within one display.

Terminal cells are not square, so the projection compensates for a roughly 2:1
character aspect ratio. The map summary reports the approximate point size of
one terminal cell. Geometry and overlap are proportional but approximate.

### The x-ray floor plan

The drawing has a deliberate reading order: **monitor bezel → labelled primary
window → numbered secondary shapes → legend.**

**The bezel** is a double-line outer frame with a blank gutter inside it, so a
window border is never adjacent to the monitor frame — `║ ┌` rather than `║┌`,
which reads as one thick border. Window painting also refuses outright any cell
already holding a double-line glyph, so the bezel cannot be merged into,
replaced, or masqueraded as, whatever the window geometry. On a display too
small to afford the gutter the inset falls back to one cell; the refusal still
holds, so windows never reach the bezel itself.

**Windows** are single-line rectangles. The map is an **x-ray**: a window never
fills or erases its interior, so a window that is completely covered on the real
desktop still appears as its own complete rectangle. Where two outlines cross
they merge into the correct box-drawing junction (`┼`, `┬`, `┤`) rather than one
erasing the other. This trades the visual "which window is in front" cue — which
the legend carries authoritatively — for the guarantee that no window silently
disappears. There is no `(occluded)` state.

So that a rectangle still reads as closed inside all that merging, each window's
**bottom-right endpoint is restamped as its own `┘` corner** after the outlines
merge. Two windows wanting the same cell produce the same glyph, so the result
is order-independent; where a corner lands mid-edge, closure deliberately wins
over line continuity.

**Labels.** Exactly one window per display — the frontmost drawable one — spells
out its app and title on the canvas. Every other window keeps its complete
geometry and its `[n]`, and its identity lives in the legend. Labelling every
overlapping window is what turns a busy desktop into noise.

Markers are placed front to back. A window's number hugs its own top-left
corner and walks down its rows before it slides right, so a number always reads
as belonging to the rectangle it sits inside. A marker may overwrite an outline;
identity wins over line continuity. Every legend row then resolves to exactly
one of four honest states:

| Legend note | Meaning |
|-------------|---------|
| *(none)* | `[n]` is on the canvas |
| `(small)` | The window had room for a bare `n` but not `[n]`. Numbers are never truncated — a bare marker also reserves a non-digit cell on each side so `10` and `12` cannot run together |
| `(too small to label)` | The outline is drawn but no numeral fits anywhere inside it |
| `(off-canvas)` | The window clipped away entirely and was not drawn |

Labels inside the fixed-width canvas use a one-cell-safe projection; the legend
preserves cleaned Unicode app names and titles and includes exact global
geometry.

The canvas still uses box-drawing characters, which are East Asian *Ambiguous*
width. Under a CJK locale, or a terminal configured to render ambiguous-width
characters as double width, the grid will shear. A pure-ASCII drawing mode is
the fix for that and is not implemented.

## Options

| Option | Effect |
|--------|--------|
| `--display <n>` | Include only the zero-based display index `n` |
| `--width <n>` | Set the maximum canvas width; clamped to 32–120 columns |
| `--height <n>` | Set the maximum canvas height; clamped to 8–40 rows |
| `--json` | Emit the versioned current-Space snapshot instead of a diagram |
| `-h`, `--help` | Print command help without contacting the daemon |

Without `--width`, the command uses the terminal width when available and 72
columns otherwise. Without `--height`, the canvas is capped at 24 rows. The
desktop is scaled uniformly to fit within both maxima, so one bound can remain
partly unused rather than distorting the topology. Numeric options must be
non-negative integers.

## JSON for agents

```bash
lattices map --json
lattices map --display 1 --json
```

The JSON form is a canonical projection of the same current-Space view; it is
not the unfiltered response from `windows.list`:

```json
{
  "version": 1,
  "coordinateSystem": {
    "origin": "top-left",
    "units": "points",
    "reference": "global-desktop"
  },
  "displays": [
    {
      "displayIndex": 0,
      "displayId": "37d8832a-2d66-02ca-b9f7-8f30a301b230",
      "name": "Built-in Liquid Retina XDR Display",
      "frame": { "x": 0, "y": 0, "w": 1728, "h": 1117 },
      "visibleFrame": { "x": 0, "y": 38, "w": 1728, "h": 1079 },
      "currentSpaceId": 83,
      "spaces": [
        { "id": 83, "index": 1, "display": 0, "isCurrent": true }
      ],
      "windows": [
        {
          "wid": 4182,
          "app": "Ghostty",
          "pid": 916,
          "title": "lattices",
          "frame": { "x": 0, "y": 38, "w": 960, "h": 1038 },
          "spaceIds": [83],
          "isOnScreen": true,
          "axVerified": true,
          "zIndex": 0
        }
      ]
    }
  ]
}
```

Each display nests only windows that are on-screen, belong to its current
Space, and intersect its usable frame. `zIndex: 0` is frontmost within that
display snapshot; it is per-display and zero-based, whereas the terminal
legend's `[n]` is continuous across displays and one-based. The two are not
interchangeable — join on `wid`, which is stable across both. `[n]` also
renumbers under `--display`, so a window the full map calls `[5]` becomes `[1]`
in `map --display 1`. `--display` filters both terminal and JSON output. For every
known window, including hidden and off-Space windows, call `windows.list`
directly instead. The versioned projection copies the documented display,
Space, and window fields explicitly rather than passing through arbitrary
future daemon fields; optional `latticesSession` and `layerTag` values remain
available when `windows.list` supplies them.

The two daemon reads happen close together but are not an atomic WindowServer
transaction. A window or Space change during the calls can produce a briefly
mixed snapshot; retry before a consequential mutation if the desktop is moving.

## Daemon fields and coordinates

`spaces.list` adds these fields to each display:

| Field | Meaning |
|-------|---------|
| `name` | Human-readable `NSScreen.localizedName` |
| `frame` | Full display bounds in global top-left coordinates |
| `visibleFrame` | Usable bounds after the menu bar, Dock, and system reservations |

The display geometry uses the same coordinate system as `windows.list` window
frames:

- origin: top-left of the primary display;
- units: macOS logical points, not capture pixels;
- positive `x`: right;
- positive `y`: down;
- displays left of the primary display have negative `x`;
- displays above the primary display have negative `y`;
- displays below or to the right have offsets beyond the primary bounds.

AppKit reports global screen rectangles from a bottom-left origin. Lattices
converts them with:

```text
apiY = primaryDisplayHeight - (appKitY + height)
```

For a 1117-point-high primary display, a 900-point display immediately above
it starts at `y: -900`; a 700-point display immediately below it starts at
`y: 1117`. Horizontal offsets are unchanged. Lattices matches SkyLight display
records to `NSScreen` by display UUID, with the existing index as a fallback.

## Surface and side-effect matrix

A miniature workspace diagram on the desktop—often near the lower-left—is a
HUD minimap, not terminal `lattices map` output.

| Primitive | CLI / daemon method | Read or mutate | Moves or focuses windows? | Visible desktop surface? | Lifetime and exact cleanup | Structured verification? |
|-----------|---------------------|----------------|---------------------------|--------------------------|----------------------------|--------------------------|
| Terminal workspace map | `lattices map`; `spaces.list` + `windows.list` | Read-only | No | No; terminal output only | Ends with the command; no desktop cleanup | **Yes, preferred**; use `--json` |
| Raw inventory | `lattices windows --json`; `windows.list` | Read-only | No | No | One-shot | **Yes, preferred** |
| Resolve or plan a target | `lattices call window.resolve ...`; `window.resolve` | Read-only | No | No | One-shot | **Yes, preferred** before mutations |
| Studio / interactive Screen Map | No CLI/RPC open method; **Hyper+L** opens Studio | Opening is UI-only; Apply and explicit actions can mutate | Not merely by opening; Apply/focus/tile actions can | **Yes**, a normal Lattices window; preview mode can add an overlay | Hyper+L is an opener, not a close toggle. With map keyboard focus use **Escape** or **q**; the window close button also closes it and ends preview | No structured surface lifecycle API; do not open for verification |
| HUD and HUD minimap | No CLI/RPC open method; **Hyper+3** toggles HUD | Opening is UI-only; chosen HUD actions can mutate | Selected actions can focus/tile | **Yes**, including the miniature map panels | Press **Hyper+3** while the HUD is active, or Escape from the base HUD. Tile/search submodes consume the first Escape, so another may be required. `M` cycles minimap hidden/docked/expanded. The Scattered and Full presets intentionally fade to ambient opacity instead of fully disappearing; while the HUD is active, use `X` (or `Option+X` from any HUD context) to select Classic, Glass, or Alive before dismissing when full teardown is required | No; agents should not open it for verification |
| Live tab-stack chrome | `tabStacks.list`; `tabStacks.create` / `layout` / `select` / `delete` | List is read-only; the others mutate stack or window state | Create/layout can move windows; select focuses one | **Yes**, an enclosure and reserved rail independent of the HUD | Persists after Hyper+3 dismissal. Call `tabStacks.delete` with its `id` to remove the stack without closing member windows | `tabStacks.list` is structured; never create a stack only to verify state |
| Screenshot artifact | `lattices capture window [wid]`; `lattices capture display [index]`; `capture.screenshotWindow` / `capture.screenshotDisplay` | Writes a run and PNG; display capture can also copy the PNG to the clipboard | No | Opens no picker or new Lattices surface. Display capture records the display as already composed, including visible Lattices overlays; macOS can show a permission prompt on first use | One-shot; the artifact persists in the run store, but no new Lattices UI remains | Yes when pixels are actually required; otherwise prefer state APIs |
| Recording artifact | `lattices capture record ...`; `capture.recordWindow` / `capture.recordRegion` | Writes a run and MOV | No | No visible Lattices capture UI; an offscreen probe runs in the background | Until `--duration-ms` expires or `lattices capture stop <run-id>` completes | Use only when temporal pixels are required |
| Place a window | `lattices place ...`; `window.place` / `actions.execute` | Mutating | **Yes** | No Lattices overview surface | One-shot; use the returned undo receipt / `actions.undo` when applicable | Verify afterward with `lattices map --json` or raw reads |

The Scattered and Full HUD presets intentionally leave a faint, non-interactive
ambient visual after dismissal. That is why Hyper+3 can appear to dismiss a
miniature map without removing every pixel. Live tab-stack chrome is a separate
persistent surface and must be removed with `tabStacks.delete`, not Hyper+3.
The current API cannot enumerate or force-dismiss Lattices-owned transient
HUD/Studio panels, so there is no honest structured proof that every such panel
has torn down. That lifecycle API is a follow-up, not something agents should
approximate with screenshots.

## Acting on the map

Every legend row carries the window's `wid`. That id feeds the movement
commands directly, without any visible Lattices surface:

```bash
lattices window move 4182 --display 1                    # keep normalized frame
lattices window move 4182 --display 1 --placement right  # snap into a slot
lattices window place 4182 top-left                      # slot on current display
lattices window move 4182 --display 0 --dry-run --json   # plan without moving
```

Both commands require an explicit wid — a malformed id is an error, never a
frontmost fallback — and return the daemon's execution receipt with before,
target, and after frames. Verify afterward with `lattices map --json`.

## Agent workflow and cleanup guarantees

1. Read `spaces.list`, `windows.list`, or `lattices map --json`.
2. Use `window.resolve` or an `actions.execute` dry run when target identity or
   placement matters.
3. Mutate only through the explicit daemon action.
4. Read structured state again and compare window ID, Space IDs, and frame.
5. Capture pixels only when the result is inherently visual.

Agents must not open Studio, the HUD/minimap, a capture/review UI, or another
visible Lattices surface when structured state is sufficient. `lattices map`
itself is always safe for this workflow because it cannot create macOS UI.

If an agent intentionally opens a visible Lattices surface, it must close that
same surface before finishing and verify the desktop through structured state
where possible. `windows.list` can prove that target windows did not move, but
it cannot currently prove HUD/Studio teardown. Report that gap instead of
leaving a surface open or using a screenshot as a substitute for lifecycle
state.
