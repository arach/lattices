---
title: Mouse Gestures
description: Hold a mouse button, draw a shape or direction, release — runs matched actions like a window manager power-user shortcut system.
order: 4.2
---

# Mouse Gestures

## Concept

Mouse gestures are a user-level shortcut system for the macOS app. Hold a
configured mouse button, draw a direction or shape, then release to run the
matched action.

The app code owns the recognizer, action dispatcher, and JSON schema. Your
actual gesture mappings live in:

```bash
~/.lattices/mouse-shortcuts.json
```

That file is machine-local preference data. It is not project config, and it
should not be committed to this repository unless you are intentionally adding
an example fixture or changing the schema.

## Config Ownership

There are two layers:

- **Code defaults** in `MouseGestureConfig.swift` provide a minimal starter
  config when no user file exists.
- **User rules** in `~/.lattices/mouse-shortcuts.json` are the source of truth
  after the file has been created.

Do not add personal shortcuts by changing `MouseGestureConfig.swift`. Add them
to the user JSON file instead. The Settings UI can open that file from
**Settings -> Shortcuts -> Mouse Gestures -> Configure...**.

## Lightweight History

Lattices keeps local snapshots of your mouse shortcut config before risky
changes:

```bash
~/.lattices/mouse-shortcuts.history/
```

Snapshots are written before external edits are reloaded and before Settings
restores defaults or restores a previous snapshot. The newest 40 snapshots are
kept. Use **History** in Settings to open the folder, or **Undo Last** to
restore the latest snapshot.

## Button Names

The config accepts these common button names:

| Config value | Meaning |
|---|---|
| `middle` | Middle button / wheel click |
| `back` | Back side button, often mouse button 4 |
| `forward` | Forward side button, often mouse button 5 |
| `right` | Right mouse button |
| `buttonN` | Explicit numbered button fallback |

Normal clicks pass through when a configured button is only being watched for
drag or shape gestures. Once movement crosses the gesture threshold and matches
a real gesture, Lattices claims the interaction.

Browser frontmost apps are bypassed so native middle-click, Back, and Forward
button behavior stays intact. This avoids half-claimed side-button gestures
accidentally navigating while you are drawing a shape.

## Trigger Kinds

Rules match one of three trigger kinds:

| Kind | Required fields | Example |
|---|---|---|
| `click` | `button` | Middle click sends paste |
| `drag` | `button`, `direction` | Middle drag left switches Space |
| `shape` | `button`, `shape` | Back-button L shape activates iTerm |

Directions are `up`, `down`, `left`, and `right`.

Useful shapes include:

| Shape | Motion |
|---|---|
| `l-shape-down-right` | Down, then right |
| `l-shape-down-left` | Down, then left |
| `l-shape-up-right` | Up, then right |
| `l-shape-up-left` | Up, then left |
| `reverse-l-right-down` | Right, then down |
| `reverse-l-left-down` | Left, then down |
| `v-shape` | Down, then up |
| `reverse-v` | Up, then down |
| `circle` | A loose closed loop |

The circle recognizer is intentionally generous: it looks for broad circular
motion, a reasonably closed path, and enough turn coverage rather than a
geometrically perfect circle.

## Default: Screenshot Area Gesture

New default configs include a back-button circle gesture for the macOS
screenshot area picker (`Command` + `Shift` + `4`):

```json
{
  "id": "back-circle-screenshot-area",
  "enabled": true,
  "device": "any",
  "trigger": {
    "button": "back",
    "kind": "shape",
    "shape": "circle"
  },
  "action": {
    "type": "shortcut.send",
    "shortcut": {
      "key": "4",
      "keyCode": 21,
      "modifiers": ["command", "shift"]
    }
  },
  "visual": {
    "renderer": "matrix",
    "theme": "lattices"
  }
}
```

## Actions

Supported action types include:

| Type | Purpose |
|---|---|
| `space.previous` | Switch to the previous macOS Space |
| `space.next` | Switch to the next macOS Space |
| `screenmap.toggle` | Open the Screen Map overview |
| `dictation.start` | Start dictation |
| `shortcut.send` | Send a keyboard shortcut |
| `app.activate` | Activate an app by name |

## Example: Enter Gesture

This is a user-level rule, not a code default. Add it to
`~/.lattices/mouse-shortcuts.json` if you want the back button plus a quick
down-then-left shape to press Enter:

```json
{
  "id": "back-down-left-enter",
  "enabled": true,
  "device": "any",
  "trigger": {
    "button": "back",
    "kind": "shape",
    "shape": "l-shape-down-left"
  },
  "action": {
    "type": "shortcut.send",
    "shortcut": {
      "key": "enter",
      "keyCode": 36,
      "modifiers": []
    }
  }
}
```

## Visuals

Rules may include an optional `visual` block for feedback. Visuals are
decorative: they must never decide whether a gesture matches or whether an
action runs. If a visual asset is missing or slow, the gesture should still
execute through the native action path.

Shape gestures can opt into native matrix completion feedback with
`"visual": { "renderer": "matrix" }`. When enabled, Lattices smooths the
captured path, replays it briefly inside a small 3x3 rounded-cell matrix, then
snaps into a compact confirmation glyph and action label. This is feedback
only; the matched rule has already dispatched.

## Implementation

- `apps/mac/Sources/Core/Input/MouseGestureController.swift` owns the CGEvent
  tap, gesture session state, passthrough behavior, and action dispatch.
- `apps/mac/Sources/Core/Input/MouseGestureConfig.swift` defines the Codable
  schema and initial fallback defaults.
- `apps/mac/Sources/Core/Input/MouseShortcutStore.swift` loads the user-level
  JSON file and provides thread-safe snapshots to the event tap.
- `apps/mac/Sources/Core/Input/ShapeRecognizer.swift` converts raw gesture
  paths into direction and shape labels.

## Safety

The controller installs a session-wide CGEvent tap. To avoid blocking the
system input pipeline:

- The tap callback does only cheap work and dispatches heavier work async.
- A circuit breaker handles OS tap timeout events and pauses gestures when
  needed.
- Short, unmatched clicks are replayed or passed through so native app behavior
  remains intact.
- The emergency reset chord clears stuck input capture state.
