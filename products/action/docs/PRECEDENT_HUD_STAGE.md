# HUD And Stage Precedent Review

## Feature

HUD, backdrop, viewport, and recording-state presentation for the guided capture
milestone.

## Keep

- `vif`: the product feeling that the stage is visible, deliberate, and clearly
  in a recording mode when capture starts.
- `vif`: viewport-first framing with backdrop dimming outside the captured
  region.
- `vif`: a control surface that feels like part of the product, not a raw debug
  console.
- `stage`: clearer separation between operator controls and stage primitives
  such as backdrop and viewport.

## Avoid

- `vif`: HUD and overlay behavior becoming tightly coupled to ad hoc runner
  logic.
- `vif`: letting the UI invent state that diverges from runtime truth.
- `stage`: keeping the stage too abstract or too tool-like to feel like a real
  product surface.

## Adapt

- Keep the richer TS-side operator HUD, but make it render the runtime session
  state directly.
- Treat backdrop and viewport as first-class stage concepts, but avoid binding
  them to a specific renderer too early.
- Use native overlays later for always-on capture-state presence, while the TS
  HUD remains the richer inspection and control surface.

## Decision

- For this milestone, the TS HUD will become stage-aware: it should visibly show
  backdrop, viewport, countdown, recording state, and artifacts.
- The native side remains responsible for capture truth and will later gain the
  thin always-on stage overlay.
- The product contract stays viewport-first: the stage shows what is captured,
  and the rest of the scene is visually subordinate.

## Reference Weight

Blend leaning `vif` for product feel and `stage` for boundaries.
