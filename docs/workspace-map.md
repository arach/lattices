---
title: Workspace Map
description: Read-only terminal and JSON views of the current macOS workspace
order: 5.5
---

`lattices map` is a read-only view of the current desktop. It joins
`spaces.list` and `windows.list` from the localhost daemon, then either draws a
proportional terminal diagram or returns a versioned JSON snapshot for an
agent.

It does **not** open, focus, move, resize, or capture a macOS window. Its box
drawing exists only in the invoking terminal. This is separate from the
interactive **Studio / Screen Map** window and the **Hyper+3 HUD**.

## Terminal map

```bash
lattices map
```

Example:

```text
┌ Display 0 · Built-in Display · Space 83 ───────────────────────┐
│┌1 Ghostty - lattices──────────────────┐ ┌2 Safari - API docs─┐│
││                                      │ │                    ││
││                                      │ │                    ││
│└──────────────────────────────────────┘ └────────────────────┘│
└────────────────────────────────────────────────────────────────┘

  1  Ghostty · lattices  wid:4182  960×1038 @ 0,38
  2  Safari · API docs   wid:4210  768×1038 @ 960,38
```

The diagram represents each display's usable `visibleFrame`, not a pixel
capture. Window rectangles are clipped to that frame. Only on-screen windows
on the display's current Space appear. `windows.list` is ordered front to back;
the renderer paints back to front so a foreground window occludes the windows
behind it.

Terminal cells are not square, so the automatic height compensates for a
roughly 2:1 character aspect ratio. Geometry and overlap are proportional but
approximate. Labels inside the fixed-width canvas use a one-cell-safe ASCII
projection; the legend preserves cleaned Unicode app names and titles.

## Options

| Option | Effect |
|--------|--------|
| `--display <n>` | Include only the zero-based display index `n` |
| `--width <n>` | Set terminal width; clamped to 32–120 columns |
| `--height <n>` | Set terminal height; clamped to 8–40 rows |
| `--json` | Emit the versioned current-Space snapshot instead of a diagram |
| `-h`, `--help` | Print command help without contacting the daemon |

Without `--width`, the command uses the terminal width when available and 72
columns otherwise. Without `--height`, it derives the height from each
display's aspect ratio. Numeric options must be non-negative integers.

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
display snapshot. `--display` filters both terminal and JSON output. For every
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
| Screenshot artifact | `lattices capture window [wid]`; `capture.screenshotWindow` | Writes a run and PNG | No | No Lattices picker or overlay; macOS can show a permission prompt on first use | One-shot; the artifact persists in the run store, but no Lattices UI remains | Yes when pixels are actually required; otherwise prefer state APIs |
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
