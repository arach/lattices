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

### Custom Grid Syntax

For arbitrary grids: `grid:CxR:C,R`

- `C` = total columns, `R` = total rows (1-indexed size)
- `C,R` = target cell (0-indexed position)
- Example: `grid:5x3:2,1` = center cell of a 5×3 grid

Parsed by `parseGridString()` → returns fractional `(x, y, w, h)`.

### Positions That DON'T Exist

These are common voice interpretations that have **no matching position string**:

| What the user says | What they probably mean | Closest valid position(s) |
|---|---|---|
| "top third" | Top 1/3 of screen height | `top` (top 50%) or `grid:1x3:0,0` (true top third) |
| "bottom third" | Bottom 1/3 of screen height | `bottom` (bottom 50%) or `grid:1x3:0,2` |
| "middle third" | Middle 1/3 of screen height | `grid:1x3:0,1` |
| "top quarter" | Top 1/4 of screen height | `grid:1x4:0,0` |
| "left quarter" | Left 1/4 column | `first-fourth` |

**Key confusion**: "thirds" in the position system means **vertical columns** (3×1), not horizontal rows. There is no full-width horizontal third. When someone says "top third", they want a 1×3 row — use `grid:1x3:0,0`.

## Execution Paths

There are three independent paths that resolve a voice command into a tiled window. They have **different position resolution logic**, which is a source of bugs.

### Path 1: Local Voice (VoiceIntentResolver → IntentEngine)

```
Speech → Whisper → VoiceIntentResolver.match() → IntentMatch → IntentEngine.execute()
```

**Position resolution** (`VoiceIntentResolver.resolvePosition()`):
- Hardcoded keyword map — only resolves these positions:
  - `top-left`, `top-right`, `bottom-left`, `bottom-right`
  - `left`, `right`, `maximize`, `center`, `top`, `bottom`
- Does NOT resolve: thirds, sixths, fourths, eighths, or grid syntax
- Matches by substring containment, longest match first

**Slot flow**: `resolvePosition()` → string like `"left"` → `IntentEngine.tile_window` handler → `TilePosition(rawValue:)` → `tileGrid()` → frame

### Path 2: HandsOff Voice (XAI/Grok → worker → Swift)

```
Speech → Whisper → worker (handsoff-worker.ts) → XAI Grok inference → JSON actions → Swift HandsOffSession.executeActions()
```

**Position resolution**: The LLM picks the position string from the system prompt's intent catalog. It can generate ANY string — there is no validation in the worker. The string is passed to Swift where:
1. `IntentEngine.tile_window` handler tries `TilePosition(rawValue: posStr)`
2. If that fails, tries `parseGridString(posStr)`
3. If both fail, throws `IntentError.invalidSlot`

**Failure mode**: LLM generates `"top-third"` → `TilePosition(rawValue: "top-third")` returns nil → `parseGridString("top-third")` returns nil → error thrown → window doesn't move, but user heard "Tiling Chrome to the top third."

### Path 3: CLI / Daemon API

```
lattices call window.tile '{"session":"x","position":"left"}'
```

Routes through `LatticesApi` → same `IntentEngine.tile_window` handler as above.

### Path 4: HUD Keyboard Tiling

```
HUD open → T (tile mode) → H/J/K/L/F/Y/U/B/N keys
```

**Hardcoded key map** (HUDController.handleKey):
- H = left, L = right, K = top, J = bottom
- F = maximize
- Y = top-left, U = top-right, B = bottom-left, N = bottom-right

Only 9 positions. No thirds/fourths/grid from keyboard.

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

1. **`session`** slot → `LatticesApi.window.tile` (finds terminal by lattices session tag)
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

## HandsOff Smart Distribution

When the LLM sends multiple `tile_window` actions targeting the **same position**, `HandsOffSession.distributeTileActions()` subdivides:

- 2+ windows → "left" becomes top-left, left, bottom-left
- 2+ windows → "right" becomes top-right, right, bottom-right
- 2+ windows → "maximize" fans out to quadrants then halves

## Guardrails

- **Max 6 actions** per HandsOff turn (excluding `distribute`). Enforced in `HandsOffSession.executeActions()`.
- **Recently-tiled dedup**: `IntentEngine.recentlyTiledWids` prevents the same window from being matched twice within 2 seconds during batch operations.
- **Unknown position**: If a position string doesn't match `TilePosition` or `parseGridString`, the intent throws `IntentError.invalidSlot` — the action is skipped but other actions in the batch still execute.

## Known Gaps

1. **No horizontal thirds**: "top third" / "bottom third" / "middle third" (1×3 rows) don't exist as named positions. Must use `grid:1x3:0,0` syntax, which voice can't easily produce.

2. **VoiceIntentResolver only knows 10 positions**: The local voice path (`resolvePosition()`) has a hardcoded map that only covers halves, quarters, maximize, and center. It cannot produce thirds, sixths, fourths, or eighths.

3. **HandsOff LLM can hallucinate positions**: The system prompt lists all valid positions, but the LLM can still generate invalid strings like `"top-third"`. There's no fuzzy matching or correction on the Swift side — it just fails.

4. **Three position resolution systems**: VoiceIntentResolver has its own keyword map, the worker's fast-path (`tryFastMatch`) has its own regex, and the LLM reads from the system prompt. These can disagree.
