# LAT-001: Gesture Visual Customization and Renderer Hooks

## Status

Proposal for maintainers.

This is the first Lattices engineering proposal in the `LAT-00n` series, following the same proposal-numbering spirit as the `SCO-00n` documents used for Scout/OpenScout planning.

This document covers how to productize the recent mouse gesture and visual customization prototypes without letting decoration leak into the recognition or action-dispatch fast path.

## Summary

Lattices now has the bones of a gesture system that feels unusually alive for a macOS workspace tool: low-level mouse capture, shape recognition, shortcut matching, immediate native action dispatch, and a fallback overlay that can draw paths, markers, and result labels.

The next question is whether customization should become a supported product surface. The answer proposed here is yes, but with a hard boundary:

- gesture recognition and action dispatch remain native, synchronous, and fast
- custom rendering is declarative, best-effort, and optional
- user assets and external renderers never block or decide actions
- normal customization should not require recompiling the app

The first supported model should be a declarative `visual` block on mouse shortcut rules, backed by native theme presets and marker-to-animation mappings. Real Lottie playback can follow once the configuration model is stable. A plugin or XPC renderer can come later, after the native path has proven the contract.

## Current Gesture Pipeline

The gesture pipeline lives mainly in:

- `app/Sources/Core/Input/MouseGestureController.swift`
- `app/Sources/Core/Input/MouseGestureConfig.swift`
- `app/Sources/Core/Input/MouseShortcutStore.swift`
- `app/Sources/Core/Input/ShapeRecognizer.swift`

The current/prototyped flow is:

1. A CG event tap captures mouse button and movement events.
2. `MouseGestureController` starts and updates gesture sessions, tracking button state, phase, and path points.
3. Movement points are fed to `ShapeRecognizer`, which compresses raw motion into direction runs.
4. Recognized shapes such as `l-shape-down-right` become trigger facts.
5. `MouseShortcutStore` matches a `MouseShortcutTriggerEvent` against enabled `MouseShortcutRule` entries.
6. The matched rule dispatches its native action immediately.
7. `MouseGestureOverlay` and `MouseGestureOverlayView`, currently nested in `MouseGestureController.swift`, render the fallback/native gesture feedback.

The important split is already visible: input capture, recognition, rule matching, and action dispatch form the control path. Overlay drawing is feedback.

## What Was Prototyped

Recent prototype work explored both input semantics and visual expression.

Input and matching:

- shape triggers
- right, back, forward, and middle button handling
- MX back/forward aliases
- a back-button L shape that activates iTerm
- native action dispatch that stays immediate

Visual feedback:

- path drawing instead of a single direction arrow
- Bezier/graffiti trail rendering
- guide dots inspired by Android pattern lock
- satisfying result labels such as `iTerm FOCUSED`
- a `visual` block on shortcut rules
- a native stand-in for a custom animated character

The visual customization proof of concept added optional rule metadata:

```json
{
  "visual": {
    "renderer": "lottie",
    "asset": "~/.lattices/gesture-assets/cat.json",
    "character": "cat",
    "events": {
      "updated": "follow",
      "recognized:l-shape-down-right": "pounce",
      "completed.success": "celebrate",
      "completed.failure": "confused"
    }
  }
}
```

Today, `renderer: "lottie"` is a shim/POC name, not a real Lottie dependency. The native renderer draws a small reactive cat/avatar as a stand-in for an eventual Lottie asset.

That is a good prototype shape because it tests the user-facing contract without prematurely committing to a rendering engine.

## Architecture Principle

Recognition and action dispatch are the fast path. They must never wait on:

- custom rendering
- scripts
- Lottie playback
- XPC processes
- user-provided assets
- filesystem reads after gesture start
- network access

Visual customization is decorative. It can make gestures more legible, delightful, and personal, but it cannot become part of whether a gesture succeeds.

In practical terms:

- if a renderer fails, the action still runs
- if an asset is missing, the native fallback overlay appears
- if an external renderer is slow, it drops frames or misses the gesture
- if config is invalid, the rule can still match using native trigger/action fields
- action success/failure is reported from the action layer, not inferred from animation state

This boundary should be visible in the code. The gesture controller can emit visual events, but renderers should consume snapshots or markers asynchronously. They should not own recognition state.

## Proposed Customization Model

### 1. Declarative `visual` block first

Mouse shortcut rules should support a stable optional `visual` block:

```json
{
  "id": "back-l-iterm",
  "enabled": true,
  "device": "any",
  "trigger": {
    "button": "back",
    "kind": "shape",
    "shape": "l-shape-down-right"
  },
  "action": {
    "type": "app.activate",
    "app": "iTerm"
  },
  "visual": {
    "renderer": "native",
    "theme": "graffiti",
    "markers": {
      "updated": "follow",
      "recognized:l-shape-down-right": "commit",
      "completed.success": "success",
      "completed.failure": "error"
    }
  }
}
```

The `visual` block should be optional and ignored by older versions where possible. Its first stable fields should be:

| Field | Type | Purpose |
|---|---|---|
| `renderer` | string | Selects renderer family: `native`, later `lottie`, later `external` |
| `theme` | string? | Native preset name such as `minimal`, `graffiti`, `pattern`, `avatar` |
| `asset` | string? | Local asset reference for renderer families that need it |
| `character` | string? | Optional named character/avatar inside a renderer or asset pack |
| `markers` or `events` | object | Maps gesture markers to renderer actions |

The POC uses `events`; the product model should choose one name. `markers` is slightly clearer because the keys are not all raw system events. They are renderer-facing semantic markers derived from gesture state.

### 2. Theme presets

Before exposing arbitrary assets as the main path, ship native presets:

- `minimal`: simple path and endpoint feedback
- `graffiti`: Bezier trail with energetic completion burst
- `pattern`: guide dots and shape lock-in feedback
- `avatar`: native character-style feedback, similar to the POC cat
- `quiet`: subtle feedback for users who want confirmation without flourish

Presets give users customization without loading code or assets. They also give maintainers a reference for the renderer contract.

### 3. Marker mapping

Renderer-facing markers should be small, named, and phase-based:

| Marker | Meaning |
|---|---|
| `started` | Gesture session began |
| `updated` | Path changed |
| `recognized:<shape>` | Recognizer has a likely shape |
| `matched:<rule-id>` | Rule matched |
| `completed.success` | Action completed successfully |
| `completed.failure` | Action failed or no rule matched |
| `cancelled` | Gesture was cancelled |

Renderers can map these to animation names, effects, or state transitions:

```json
{
  "markers": {
    "started": "wake",
    "updated": "follow",
    "recognized:l-shape-down-right": "pounce",
    "completed.success": "celebrate",
    "completed.failure": "confused",
    "cancelled": "hide"
  }
}
```

The control path emits facts. The renderer interprets those facts.

### 4. Asset references

Asset references should be local file paths or app-bundled names:

```json
{
  "visual": {
    "renderer": "lottie",
    "asset": "~/.lattices/gesture-assets/cat.json",
    "markers": {
      "updated": "follow",
      "completed.success": "celebrate"
    }
  }
}
```

Rules:

- expand `~` explicitly
- resolve relative paths relative to `~/.lattices/`, not the current project
- do not fetch remote URLs
- validate extension and size before loading
- cache parsed assets outside the gesture hot path
- fall back to `native` if loading fails

### 5. Real Lottie player later

The current native shim should not pretend to be production Lottie. The roadmap should be:

1. stabilize the rule schema and marker model
2. ship native presets
3. add a real Lottie player behind the same renderer protocol
4. keep Lottie playback isolated from recognition and action dispatch

This avoids coupling the configuration surface to the first graphics library chosen.

### 6. Optional external renderer or XPC later

External renderers are powerful, but they are also where latency, crash, and security complexity enters. They should be a later feature, probably via XPC rather than arbitrary process execution.

The contract should look like a one-way visual event stream:

- Lattices sends gesture snapshots and markers.
- The renderer returns nothing that affects recognition or actions.
- The renderer may request drawing surfaces only through a narrow API.
- Timeouts and crashes are expected and non-fatal.

The open source nature of Lattices means users can always recompile experiments. Product customization should be easier and safer than that.

## Config Examples

### Back Button L to iTerm with Native Visual Markers

```json
{
  "id": "back-l-iterm",
  "enabled": true,
  "device": "any",
  "trigger": {
    "button": "back",
    "kind": "shape",
    "shape": "l-shape-down-right"
  },
  "action": {
    "type": "app.activate",
    "app": "iTerm"
  },
  "visual": {
    "renderer": "native",
    "theme": "pattern",
    "markers": {
      "started": "show-guides",
      "updated": "draw-path",
      "recognized:l-shape-down-right": "lock-shape",
      "completed.success": "success-label",
      "completed.failure": "miss-label"
    }
  }
}
```

### Back Button L to iTerm with Future Lottie Asset

```json
{
  "id": "back-l-iterm",
  "enabled": true,
  "device": "any",
  "trigger": {
    "button": "back",
    "kind": "shape",
    "shape": "l-shape-down-right"
  },
  "action": {
    "type": "app.activate",
    "app": "iTerm"
  },
  "visual": {
    "renderer": "lottie",
    "asset": "~/.lattices/gesture-assets/cat.json",
    "character": "cat",
    "markers": {
      "started": "wake",
      "updated": "follow",
      "recognized:l-shape-down-right": "pounce",
      "completed.success": "celebrate",
      "completed.failure": "confused",
      "cancelled": "hide"
    }
  }
}
```

### Quiet Native Preset

```json
{
  "id": "middle-l-palette",
  "enabled": true,
  "trigger": {
    "button": "middle",
    "kind": "shape",
    "shape": "l-shape-down-right"
  },
  "action": {
    "type": "palette.open"
  },
  "visual": {
    "renderer": "native",
    "theme": "quiet"
  }
}
```

## Latency Considerations

Gesture UX is latency-sensitive in two places:

- recognition should keep up with pointer movement
- action dispatch should happen as soon as the gesture commits

Renderer latency is allowed to be worse than action latency. The user should never feel that an animation is in charge of the system.

Implementation guidelines:

- use immutable gesture snapshots for renderer updates
- throttle rendering updates independently from event capture
- pre-load and validate assets when config changes, not when the gesture begins
- cap path point history passed to renderers
- drop visual frames under pressure
- keep completion labels tied to action receipts, not animation callbacks

Target behavior:

- action dispatch remains effectively immediate after match
- native visual feedback tracks the pointer smoothly
- custom renderer failure is invisible except for fallback visuals or debug logs

## Stability Considerations

The gesture system sits near global input, so failure modes must be boring.

Renderer failures should not:

- disable the event tap
- wedge gesture state
- prevent shortcut matching
- crash the app
- leave persistent overlay windows stuck on screen

Recommended boundaries:

- a `GestureVisualRenderer` protocol with small methods such as `start`, `update`, `mark`, `complete`, `cancel`
- a native fallback renderer that is always available
- renderer selection that can fail closed to `native`
- defensive validation of unknown marker names
- debug logging for invalid visuals, but no noisy user-facing alerts during gestures

## Security Considerations

Even though Lattices is open source, normal customization should not require recompilation. That means configuration and assets become part of the product surface and need constraints.

For MVP:

- no remote asset URLs
- no shell commands in `visual`
- no arbitrary scripts
- no executable plugins
- local assets only
- size limits for loaded assets
- clear fallback when assets are missing or invalid

For a future external renderer:

- prefer XPC over raw process execution
- use a narrow, documented message protocol
- treat renderer output as pixels or visual state only
- never accept action decisions from the renderer
- add a user-visible trust/install flow if third-party renderer bundles are supported

## Proposed Internal Shape

The implementation should keep the current architecture but name the boundary more explicitly.

Possible types:

```swift
struct GestureVisualConfig {
    let renderer: GestureVisualRendererID
    let theme: String?
    let asset: String?
    let character: String?
    let markers: [String: String]
}

struct GestureVisualSnapshot {
    let sessionID: UUID
    let phase: GesturePhase
    let button: MouseShortcutButton
    let points: [CGPoint]
    let recognizedShape: String?
    let matchedRuleID: String?
}

protocol GestureVisualRenderer {
    func start(_ snapshot: GestureVisualSnapshot, config: GestureVisualConfig)
    func update(_ snapshot: GestureVisualSnapshot)
    func mark(_ marker: String, snapshot: GestureVisualSnapshot)
    func complete(_ marker: String, snapshot: GestureVisualSnapshot)
    func cancel(_ snapshot: GestureVisualSnapshot)
}
```

The exact Swift names can differ. The important part is that renderers consume snapshots and markers; they do not mutate recognition state or decide actions.

## Phased Roadmap

### Phase 0: POC Cleanup

Goal: make the prototype understandable and safe to keep iterating.

- keep native avatar/Lottie shim clearly labeled as POC
- document current supported marker keys
- ensure missing or invalid visual config falls back to native overlay
- verify back/forward button aliases and shape matching remain independent from visuals

### Phase 1: MVP Native Customization

Goal: support real user customization without external dependencies.

- stabilize the `visual` schema
- support `renderer: "native"`
- ship a small set of native themes
- support marker mapping for native themes
- load visual config from normal shortcut config
- add diagnostics for invalid visuals
- keep existing native overlay as fallback

### Phase 2: Real Lottie Integration

Goal: make `renderer: "lottie"` honest.

- add a real Lottie player dependency or embedded playback implementation
- validate and cache Lottie assets outside the gesture hot path
- map markers to animation segments or named states
- enforce size and complexity limits
- provide at least one bundled example asset

### Phase 3: Renderer Hooks and XPC

Goal: enable deeper experiments without compromising the app.

- define a one-way renderer event protocol
- run external renderers out of process
- add crash and timeout handling
- add user trust/install UX for third-party renderers
- keep all action decisions inside Lattices

## Open Questions

- Should the field be named `events` to match the prototype, or `markers` to better describe the stable concept?
- Should visual config live only on individual rules, or should users be able to define reusable named visual profiles?
- How much of `MouseGestureOverlay` should become a renderer implementation versus remaining a fallback shell?
- Should marker names be fully free-form, or should unknown keys be rejected during config validation?
- Do we want app-level theme defaults, per-device defaults, or only per-rule visuals for MVP?
- Should `completed.failure` mean "no rule matched", "action failed", or both with more specific submarkers?
- Where should user assets live: `~/.lattices/gesture-assets/`, app support, or both?

## Acceptance Criteria

For the MVP:

- A shortcut rule can include a `visual` block without changing trigger or action behavior.
- A back-button `l-shape-down-right` rule can activate iTerm and show native marker-based feedback.
- Invalid visual config falls back to the native overlay and does not prevent the action.
- Missing assets do not crash the app or delay gesture completion.
- Recognition and action dispatch do not wait on renderer work.
- Native themes can render started, updated, recognized, success, failure, and cancelled states.
- The config format is documented with at least one complete example.
- Debug diagnostics make renderer fallback understandable to maintainers.

For later Lottie support:

- `renderer: "lottie"` uses a real Lottie player, not the native shim.
- Lottie assets are validated and cached before gesture start.
- Marker mappings can target named animations or segments.
- Lottie renderer failure falls back to native rendering without affecting actions.

## Recommendation

Productize visual customization, but productize it as a renderer contract rather than as a graphics feature.

The useful product surface is not "play a cat animation." It is:

- gestures have stable semantic markers
- users can bind visual feedback to those markers
- Lattices keeps input and action dispatch fast
- renderers are replaceable decoration

That gives maintainers room to ship the fun parts without letting them become load-bearing.
