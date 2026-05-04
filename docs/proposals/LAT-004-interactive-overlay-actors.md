# LAT-004: Generative Overlay UI

## Status

Approved.

This document proposes a general generative overlay UI system for Lattices. The goal is not to build a mascot-specific feature. The goal is to let agents and local systems generate structured interface requests that Lattices renders as small, stateful, movable, clickable, native desktop surfaces.

## Summary

Lattices now has the beginning of a shared screen overlay canvas and an agent-facing overlay API. That is enough for passive visuals: labels, highlights, toasts, and simple pet-style sprites.

The next step is interaction.

Agents and local systems need a way to surface attention requests without opening a full app window. Examples include:

- an agent asking for feedback
- a permission request that needs approval
- a build, merge, or review result
- a useful link to a PR, thread, workspace, or file
- a reminder that a background process is waiting
- a lightweight status surface that can be moved out of the way

The proposed primitive is an **overlay actor**: a small persistent or transient object on the desktop that can move, animate, change state, show attached information, expose click targets, accept drag/drop, and emit interaction events back to the daemon.

The broader product frame is **Generative Overlay UI**:

- callers generate intent and schema
- Lattices owns rendering, style, hit-testing, permissions, safety, and interaction behavior
- the desktop receives native contextual UI instead of arbitrary injected web content

Ranger or any pet-like asset can be one renderer for this system. A logo, status chip, icon, or minimal badge should be equally valid renderers.

## Why Now

The shared overlay canvas gives Lattices a stable place to draw. The agent overlay API proves that outside processes can publish useful visual state.

The early pet experiments also exposed the missing pieces:

- WebSocket-driven position updates are too chunky for motion.
- Text needs crisp typography and carefully controlled translucent backing.
- Overlays must be easy to dismiss and should not linger accidentally.
- Some surfaces need real hit-testing, while the rest of the canvas must remain click-through.
- Agents need events when the user clicks, dismisses, drags, or chooses an action.

Those are general generative UI needs, not pet-specific needs.

## Goals

- Provide a reusable model for small interactive overlay actors.
- Keep the canvas click-through except where an actor or attached surface explicitly opts into input.
- Let the app own animation timing, easing, and sprite state.
- Let agents express intent instead of manually streaming frames or coordinates.
- Render agent-generated UI from safe structured schemas instead of arbitrary HTML.
- Support crisp, minimal information presentation with optional translucent text/card backing.
- Support hover, click, drag, dismiss, drop, menu, and action-button interactions.
- Emit daemon events for user interactions.
- Keep all attention surfaces dismissible, snoozable, or moveable.
- Make sound possible but controlled by app settings and priority.

## Non-Goals

This is not a replacement for the HUD, command palette, settings window, Screen Map, or menu bar app.

This is not a general webview or arbitrary HTML surface.

This is not a notification center clone. The system can present attention requests, but it should stay compact, contextual, and action-oriented.

This does not make every overlay interactive. Passive layers such as snap zones, gesture trails, and focus highlights should remain passive unless they have a clear reason to capture input.

## Conceptual Model

### Actor

An actor is the small visible object.

Examples:

- sprite asset
- app/service logo
- status chip
- progress puck
- minimal icon

An actor has:

- stable id
- renderer type
- asset id
- state
- position
- size or scale
- opacity
- optional pinned position
- input policy
- optional attached surface

### Surface

A surface is information attached to an actor.

Examples:

- one-line message
- compact card
- action prompt
- link preview
- progress status
- permission request

The surface should support:

- title
- body
- severity/priority
- links
- buttons
- dismiss/snooze affordance
- optional timeout

Surfaces should be visually precise: crisp text, restrained translucent backing, thin edges when needed, no heavy blurry panel chrome.

### Effect

An effect is visual or audio feedback that supports state.

Examples:

- hover lift/brightness
- pulse for waiting state
- success flash
- failure shake
- path trail during movement
- soft sound cue for attention

Effects should be optional and bounded. They should never become the core interaction contract.

## Actor State

The system should define common states while allowing renderer-specific mapping.

Initial common states:

- `idle`
- `active`
- `moving`
- `waiting`
- `thinking`
- `success`
- `warning`
- `failed`
- `review`
- `muted`

Renderers can map these states to their own animation names. For example, a sprite renderer might map:

- `movingRight` -> `run_right`
- `movingLeft` -> `run_left`
- `waiting` -> `waiting`
- `failed` -> `failed`

The API should not require callers to know sprite rows or frame sizes.

## Interaction Model

Actors should support explicit input capabilities:

- `hoverable`
- `clickable`
- `draggable`
- `droppable`
- `dismissible`
- `menuEnabled`

The default should be conservative:

- the canvas remains click-through
- only actor bounds and attached surface/button bounds capture input
- input capture should never cover the whole screen unless a modal feature explicitly owns that surface

Expected interactions:

- hover: brighten, lift, preview, or emit event
- click: primary action, open compact surface, or emit event
- double-click: optional secondary action
- drag: move actor and optionally pin final position
- drop: emit dropped item payload if supported
- Escape: dismiss the active surface
- click-away: dismiss transient surfaces when appropriate
- context menu: mute, snooze, hide, settings, inspect source

Dismissal should normally dismiss the current message/surface, not delete the actor.

## Motion

Motion should be renderer-owned, not API-spammed.

Callers should be able to say:

```json
{
  "id": "scout-ranger",
  "position": { "x": 640, "y": 320 },
  "durationMs": 700,
  "easing": "spring"
}
```

The app should:

- keep current position
- interpolate toward target position
- draw at display cadence
- update directional state during movement
- settle into the target state when complete

Initial easing modes:

- `linear`
- `easeInOut`
- `spring`

Path support can come later:

```json
{
  "id": "scout-ranger",
  "path": [
    { "x": 320, "y": 180 },
    { "x": 540, "y": 230 },
    { "x": 760, "y": 190 }
  ],
  "durationMs": 1400,
  "easing": "spring"
}
```

## API Sketch

### Create Or Update Actor

```json
{
  "method": "overlay.actor.publish",
  "params": {
    "id": "scout-ranger",
    "renderer": "sprite",
    "asset": "scout-ranger",
    "state": "idle",
    "position": {
      "anchor": "bottomRight",
      "x": -40,
      "y": -40
    },
    "draggable": true,
    "clickable": true,
    "dismissible": true
  }
}
```

### Set State

```json
{
  "method": "overlay.actor.setState",
  "params": {
    "id": "scout-ranger",
    "state": "waiting",
    "message": {
      "title": "Agent needs feedback",
      "body": "Review the proposed merge?",
      "priority": "decision",
      "actions": [
        { "id": "approve", "label": "Approve", "style": "primary" },
        { "id": "open", "label": "Open PR", "url": "https://github.com/arach/lattices/pull/31" },
        { "id": "dismiss", "label": "Dismiss" }
      ]
    },
    "sound": "attention-soft"
  }
}
```

### Move Actor

```json
{
  "method": "overlay.actor.moveTo",
  "params": {
    "id": "scout-ranger",
    "position": { "x": 640, "y": 320 },
    "durationMs": 700,
    "easing": "spring"
  }
}
```

### Clear Actor Or Surface

```json
{
  "method": "overlay.actor.clear",
  "params": {
    "id": "scout-ranger",
    "surfaceOnly": true
  }
}
```

### Subscribe To Events

The daemon should emit events such as:

- `overlay.actor.hovered`
- `overlay.actor.clicked`
- `overlay.actor.doubleClicked`
- `overlay.actor.dragStarted`
- `overlay.actor.moved`
- `overlay.actor.dropped`
- `overlay.actor.dismissed`
- `overlay.actor.actionSelected`
- `overlay.actor.snoozed`

Example event:

```json
{
  "event": "overlay.actor.actionSelected",
  "data": {
    "actorId": "scout-ranger",
    "surfaceId": "ask-123",
    "actionId": "approve"
  }
}
```

## Visual Rules

The visual system should stay quiet and exact.

- Prefer actor plus attached text over large panels.
- Use translucent backing only when it improves readability.
- Keep text crisp: system fonts, no excessive blur, no heavy shadows.
- Use thin strokes and hairlines when edges are needed.
- Avoid decorative opacity stacks that make the surface feel fuzzy.
- Avoid sticky surfaces unless the request truly needs a decision.
- Make hover/click affordances legible without shouting.

For text next to an actor, the baseline style should be:

- white text with high alpha
- subtle black text halo or small shadow
- optional dark wash at low alpha
- thin light edge if needed
- no large rounded card unless actions require it

## Sound

Sound should be event-driven and user-controlled.

Initial cue types:

- `none`
- `attention-soft`
- `success-soft`
- `warning-soft`
- `failure-soft`

Rules:

- sound should default to quiet or disabled depending app settings
- priority should gate whether sound is allowed
- repeated sounds should be rate-limited
- dragging/hovering should not spam sounds
- all sounds should be suppressible globally and per actor/source

## Architecture

Proposed components:

### `OverlayActorStore`

Owns actor state:

- actors by id
- current position
- target position
- current state
- attached surface
- interaction policy
- pin/mute/snooze metadata

### `OverlayActorAnimator`

Owns time-based interpolation:

- active motion records
- easing functions
- display-link or timer updates
- direction/state transitions during movement

### `OverlayActorRenderer`

Draws actors and surfaces into the shared overlay canvas.

Renderer variants can include:

- sprite renderer
- logo renderer
- chip renderer
- progress renderer

### `OverlayActorHitTester`

Tracks interactive regions:

- actor bounds
- attached card bounds
- action button bounds
- drag handles if needed

This component decides whether the overlay window should accept input at a given point.

### `OverlayActorInteractionController`

Handles:

- hover state
- click/double-click
- drag/drop
- dismissal
- context menu
- event emission

### `OverlayActorApi`

Adds daemon methods and schemas:

- `overlay.actor.publish`
- `overlay.actor.setState`
- `overlay.actor.moveTo`
- `overlay.actor.clear`
- `overlay.actor.list`

## Relationship To `ScreenOverlayCanvas`

`ScreenOverlayCanvasController` should remain the rendering substrate.

Interactive actors may require the overlay window to stop ignoring mouse events in a very controlled way. The preferred approach is:

- keep the panel non-activating
- override hit-testing so only registered actor/surface regions return a view
- return `nil` for all other points so normal desktop clicks pass through
- avoid making the app active for simple hover/click where possible

The shared canvas can continue supporting passive layers alongside interactive actors.

## Relationship To Existing Overlay API

The current `overlay.publish` API is still useful for simple passive layers:

- `toast`
- `label`
- `highlight`
- simple `pet`

The actor API should be added next to it rather than replacing it immediately.

Over time, `kind: "pet"` can become a compatibility wrapper around `overlay.actor.publish` for sprite actors.

## Implementation Plan

### Phase 1: Actor State And Rendering

- Add actor model types.
- Add actor payload to the screen overlay renderer.
- Support sprite assets, state mapping, and attached text wash.
- Add `overlay.actor.publish`.
- Keep interaction disabled except dismiss-on-click-away.

### Phase 2: Smooth Motion

- Add current/target position state.
- Add display-cadence animation timer.
- Add `overlay.actor.moveTo`.
- Map direction to movement animation state where assets support it.

### Phase 3: Hit-Testing And Drag

- Make the overlay window selectively interactive.
- Hit-test only actor and attached surface bounds.
- Support hover state.
- Support dragging to move/pin.
- Emit `overlay.actor.moved`.

### Phase 4: Action Surfaces

- Add compact action cards.
- Support links and action buttons.
- Emit `overlay.actor.actionSelected`.
- Add dismiss and snooze behaviors.

### Phase 5: Sound And Settings

- Add sound cue names.
- Add global overlay sound setting.
- Add rate limits.
- Add mute/snooze per source or actor.

## Open Questions

- Should actors be global across Spaces, per Space, or configurable per actor?
- Should pinned actor positions be saved per display, per Space, or globally?
- What is the right default anchor for a persistent actor?
- Should action cards use AppKit drawing or a small SwiftUI-hosted island?
- How much interaction can a non-activating panel handle without surprising focus behavior?
- Should daemon events be broadcast to all clients or routed back to the caller that created the actor?
- How should drops be represented when users drag files, URLs, or text onto an actor?

## First Useful Slice

The first useful implementation should be small:

1. Add `overlay.actor.publish` for a sprite actor with state and attached message.
2. Add smooth `overlay.actor.moveTo` with app-owned easing.
3. Add selective hit-testing for hover and drag.
4. Emit `overlay.actor.moved` and `overlay.actor.clicked`.
5. Keep action cards and sound for the next slice.

That would make the system immediately feel different from passive overlays while keeping the surface area manageable.
