# Mouse Gestures

## Concept

Hold a mouse button → drag in a direction → release to execute an action.
The MX Master 3S back-side button (button 3) triggers grid layouts.

## Button Mapping

Defaults — remap by editing `~/.lattices/mouse-shortcuts.json`:

- **Button 3 (Back)** — grid layouts (Maximize / 2×2 / 3×3 / 4×4)

## Gesture Detection

1. Button held → start tracking mouse movement
2. After 30px of movement, commit to a direction (↑ ← → ↓)
3. Show HUD feedback badge: current direction + predicted action
4. Release → execute the action

If released before 30px threshold → no action (treated as a normal click).

## Actions

### Button 3 — Grid / Tile

| Direction | Action | Result |
|-----------|--------|--------|
| ↑ Up | Maximize | Frontmost window fills the screen |
| ← Left | 2×2 grid | Distribute frontmost 4 windows |
| → Right | 3×3 grid | Distribute frontmost 9 windows |
| ↓ Down | 4×4 grid | Distribute frontmost 16 windows |

Grid distributes the visible non-Lattices windows to fill the grid cells on
the screen the cursor is on.

## HUD Feedback

While dragging:
- Small floating badge near the cursor: direction arrow + action name
- Floats above all windows, fades out on release

## Safety: self-healing event tap

The controller installs a session-wide CGEvent tap. To avoid blocking the
system input pipeline:

- The tap callback never blocks — actions dispatch async to the main queue.
- A circuit breaker trips on (a) OS `tapDisabledByTimeout` events, or
  (b) any single action that exceeds 500ms.
- Cooldowns escalate inside a 10-minute rolling window: **30s → 2min →
  permanent** (until config reload or app restart).
- A center-screen badge surfaces "Mouse gestures paused — resuming in Ns"
  on trip and "Mouse gestures resumed" on auto-recover. All trips log to
  `~/.lattices/lattices.log`.

## Implementation

- `apps/mac/Sources/MouseGestureController.swift` — CGEvent tap, gesture
  state machine, breaker.
- Tile actions go through `WindowTiler.tileFrontmostViaAX(...)`.
- Grid actions enumerate visible windows via `DesktopModel.shared.allWindows()`
  and batch-move them with `WindowTiler.batchMoveAndRaiseWindows(...)`.

## Settings UI

**Settings → Shortcuts → Mouse Gestures**:

- Button 3 grid card showing the active mapping
- Hint to edit `~/.lattices/mouse-shortcuts.json` for remapping

## Edge Cases

- Multiple monitors: gesture executes on the screen the cursor starts on
- Button held + cursor leaves the screen: still tracks; action applies
  to the starting screen
- Short press (< 30px movement): ignored, treated as a normal click
- Slow action / OS tap timeout: breaker trips, gestures pause briefly,
  then auto-recover
