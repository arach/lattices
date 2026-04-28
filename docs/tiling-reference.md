# Tiling Reference

Complete reference for Lattices window tiling — positions, grids, execution paths, and voice interpretation.

## Position System

Every tile position is a cell in a **cols × rows** grid, expressed as fractional `(x, y, w, h)` of the screen's visible area (excluding menu bar and dock).

### Named Positions

All valid position strings that `TilePosition` accepts:

| Position string | Grid | Cell (col, row) | Description |
|---|---|---|---|
| `maximize` | 1×1 | full | Full screen (100% × 100%) |
| `center` | — | — | Centered floating (70% × 80%, offset 15%/10%) |
| **Halves (2×1, full height)** | | | |
| `left` | 2×1 | 0,0 | Left 50% |
| `right` | 2×1 | 1,0 | Right 50% |
| **Halves (1×2, full width)** | | | |
| `top` | 1×2 | 0,0 | Top 50% |
| `bottom` | 1×2 | 0,1 | Bottom 50% |
| **Quarters (2×2)** | | | |
| `top-left` | 2×2 | 0,0 | Top-left 25% |
| `top-right` | 2×2 | 1,0 | Top-right 25% |
| `bottom-left` | 2×2 | 0,1 | Bottom-left 25% |
| `bottom-right` | 2×2 | 1,1 | Bottom-right 25% |
| **Thirds (3×1, full height)** | | | |
| `left-third` | 3×1 | 0,0 | Left 33% column |
| `center-third` | 3×1 | 1,0 | Center 33% column |
| `right-third` | 3×1 | 2,0 | Right 33% column |
| **Sixths (3×2)** | | | |
| `top-left-third` | 3×2 | 0,0 | Top-left sixth |
| `top-center-third` | 3×2 | 1,0 | Top-center sixth |
| `top-right-third` | 3×2 | 2,0 | Top-right sixth |
| `bottom-left-third` | 3×2 | 0,1 | Bottom-left sixth |
| `bottom-center-third` | 3×2 | 1,1 | Bottom-center sixth |
| `bottom-right-third` | 3×2 | 2,1 | Bottom-right sixth |
| **Fourths (4×1, full height)** | | | |
| `first-fourth` | 4×1 | 0,0 | Leftmost 25% column |
| `second-fourth` | 4×1 | 1,0 | Second 25% column |
| `third-fourth` | 4×1 | 2,0 | Third 25% column |
| `last-fourth` | 4×1 | 3,0 | Rightmost 25% column |
| **Eighths (4×2)** | | | |
| `top-first-fourth` | 4×2 | 0,0 | Top row, 1st column |
| `top-second-fourth` | 4×2 | 1,0 | Top row, 2nd column |
| `top-third-fourth` | 4×2 | 2,0 | Top row, 3rd column |
| `top-last-fourth` | 4×2 | 3,0 | Top row, 4th column |
| `bottom-first-fourth` | 4×2 | 0,1 | Bottom row, 1st column |
| `bottom-second-fourth` | 4×2 | 1,1 | Bottom row, 2nd column |
| `bottom-third-fourth` | 4×2 | 2,1 | Bottom row, 3rd column |
| `bottom-last-fourth` | 4×2 | 3,1 | Bottom row, 4th column |
| **Horizontal thirds (1×3)** | | | |
| `top-third` | 1×3 | 0,0 | Top 33% row |
| `middle-third` | 1×3 | 0,1 | Middle 33% row |
| `bottom-third` | 1×3 | 0,2 | Bottom 33% row |
| **Edge quarters** | | | |
| `left-quarter` | 4×1 | 0,0 | Leftmost 25% column |
| `right-quarter` | 4×1 | 3,0 | Rightmost 25% column |
| `top-quarter` | 1×4 | 0,0 | Top 25% row |
| `bottom-quarter` | 1×4 | 0,3 | Bottom 25% row |

### Custom Grid Syntax

For arbitrary grids: `grid:CxR:C,R`

- `C` = total columns, `R` = total rows
- `C,R` = target cell (0-indexed position)
- Example: `grid:5x3:2,1` = center cell of a 5×3 grid

Parsed by `PlacementSpec` / `parseGridString()` into fractional `(x, y, w, h)`.

### Placement Contract

Placement strings are convenient at the boundary, but the daemon uses a
typed placement model internally:

- named tile positions
- arbitrary grid cells
- raw fractional rectangles

That is what keeps CLI, daemon, voice, and hands-off execution aligned.

## Drag Snap Zones

The menu bar app can also use placement specs as drag-to-snap targets.
When you drag a window, Lattices shows faint landing zones plus a live
preview of the resulting frame. Releasing over a zone tiles the dragged
window to that placement. Hold `Command` while dragging to reveal snap
mode, and release `Command` to drop back to a normal free drag without
ending the gesture.

The recommended agent-owned config lives in `~/.lattices/snap-zones.json`:

```json
{
  "enabled": true,
  "modifier": "command",
  "zoneOpacity": 0.08,
  "highlightOpacity": 0.18,
  "previewOpacity": 0.14,
  "rules": [
    {
      "id": "left-edge",
      "label": "Left",
      "placement": "left",
      "trigger": { "x": 0.0, "y": 0.18, "w": 0.12, "h": 0.64 },
      "priority": 10
    },
    {
      "id": "notes-rail",
      "label": "Notes",
      "placement": { "x": 0.68, "y": 0.0, "w": 0.32, "h": 1.0 },
      "trigger": { "x": 0.88, "y": 0.18, "w": 0.12, "h": 0.64 },
      "priority": 30
    }
  ]
}
```

Notes:

- `rules` is the preferred list key. `zones` is still accepted for backward compatibility.
- `modifier` accepts `command`, `option`, `control`, or `shift`.
- `placement` can be a named placement/preset string or raw fractions.
- `trigger` uses normalized `(x, y, w, h)` fractions of the screen's
  visible area, with `y = 0` at the top.
- `priority` breaks ties when trigger regions overlap.
- `trigger` can also be a named placement or preset string if you want
  the trigger region itself to reuse an existing tile definition.
- The older `~/.lattices/grid.json` `snapZones` section still works, but
  `~/.lattices/snap-zones.json` is the cleaner file for agents to edit.

## Execution Paths

The old split-brain tiling logic has been collapsed toward a shared path.
The canonical mutation is now:

```json
{ "method": "window.place", "params": { "placement": "left" } }
```

All higher-level surfaces should compile into the same placement model:

- **Daemon / CLI**: `window.place` is the canonical mutation
- **Compatibility**: `window.tile` maps to `window.place`
- **Voice / hands-off**: parse natural language, then emit a placement spec
- **HUD**: still exposes a smaller shortcut set, but should target the same placement executor

The important change is that placement resolution now happens through
`PlacementSpec`, not through separate ad hoc parsers per surface.

## Frame Calculation

All paths eventually call one of:

1. **`WindowTiler.tileFrame(for:on:)`** — takes a `TilePosition` + `NSScreen`, returns a `CGRect` in AX coordinates (origin = top-left of primary display)
2. **`WindowTiler.tileFrame(fractions:inDisplay:)`** — takes raw `(x, y, w, h)` fractions + display rect

The math:
```
visible = screen.visibleFrame  (excludes menu bar + dock)
primaryH = primary screen height
axTop = primaryH - visible.maxY  (flip from AppKit bottom-left to AX top-left)

frame.x = visible.x + visible.width × fx
frame.y = axTop + visible.height × fy
frame.w = visible.width × fw
frame.h = visible.height × fh
```

## Window Targeting

The `tile_window` intent resolves the target window in this priority:

1. **`session`** slot → `LatticesApi.window.place` / `window.tile` compatibility wrapper
2. **`wid`** slot → `DesktopModel.shared.windows[wid]` (direct window ID lookup)
3. **`app`** slot → first matching window by `localizedCaseInsensitiveContains`, excluding recently-tiled windows (prevents double-matching in batch commands like "Chrome left, Chrome right")
4. **No target** → tiles the frontmost window

### HandsOff-specific targeting

The system prompt instructs the LLM to always use `wid` from the desktop snapshot, never `app`. This avoids ambiguity when multiple windows of the same app exist. In speech, the LLM says the app name; in the JSON action, it uses the wid.

## Common Layouts (multi-action)

These are composed from multiple `tile_window` actions:

| Layout | Actions |
|---|---|
| Split screen | left + right |
| Stack | top + bottom |
| Thirds | left-third + center-third + right-third |
| Quadrants | top-left + top-right + bottom-left + bottom-right |
| Six-up (3×2) | All six `*-*-third` positions |
| Eight-up (4×2) | All eight `*-*-fourth` positions |
| Distribute | Single `distribute` intent (auto-grid) |

CLI shortcuts compile into the same distributor:

- `lattices tile family` → smart-grid the frontmost app's visible windows
- `lattices distribute iTerm2 right` → smart-grid visible iTerm windows inside the right half

## HandsOff Smart Distribution

When the LLM sends multiple `tile_window` actions targeting the **same position**, `HandsOffSession.distributeTileActions()` subdivides:

- 2+ windows → "left" becomes top-left, left, bottom-left
- 2+ windows → "right" becomes top-right, right, bottom-right
- 2+ windows → "maximize" fans out to quadrants then halves

## Guardrails

- **Typed placement validation**: invalid placement strings or objects are rejected at the daemon boundary.
- **Recently-tiled dedup**: `IntentEngine.recentlyTiledWids` prevents the same window from being matched twice within 2 seconds during batch operations.
- **Compatibility wrappers**: `window.tile` still works, but routes through the same placement machinery.

## Current Gaps

1. **Voice extraction still needs to catch up**: the canonical executor understands horizontal thirds and edge quarters, but the local voice resolver still needs broader phrase coverage.
2. **HUD coverage is narrower than the executor**: keyboard tiling exposes a small subset of the full placement vocabulary.
3. **Optimization and layer actions are still wrapper-level**: `space.optimize` and `layer.activate` are now stable action IDs, but they currently wrap existing distributor and layer-switching behavior rather than a full planner.
