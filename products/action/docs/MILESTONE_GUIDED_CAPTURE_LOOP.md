# Guided Capture Loop

## Purpose

This is the first meaningful milestone for `action`.

The goal is not to finish the whole product. The goal is to prove that `action`
can run a polished, inspectable, native-first capture session end to end.

If this milestone works, we will have validated the most important live-system
assumptions:

- a session-oriented runtime
- a useful operator HUD
- a visible stage with a controlled viewport
- real recording lifecycle control
- deterministic actions against a native app
- artifacts and logs that make the run inspectable afterward

## Mission

Build a native macOS guided capture session where a user can:

1. choose a backdrop and target app
2. see a HUD that reflects session state and logs
3. stage a window inside a viewport
4. trigger a recording countdown
5. record a deterministic Calculator demo
6. save video, screenshot, and trace artifacts
7. replay the last run

This milestone is intentionally live-phase heavy. It validates the runtime and
engine before investing deeply in final-video composition.

## Why This Is First

This milestone gives us the highest-value proof earliest.

- It makes the system feel real immediately.
- It tests the runtime where most failure risk lives.
- It creates the traces and artifacts the composition layer will later consume.
- It gives us a visible product loop instead of isolated backend pieces.

If this is weak, composition will not save the product. If this is solid,
composition can evolve safely later.

## Precedent Review Requirement

Before implementing each major part of this milestone, review how the same area
worked in earlier iterations such as `vif` and `stage`.

For each of these feature areas, write down:

- `Keep`
- `Avoid`
- `Adapt`
- `Decision`

Apply that review to:

- HUD
- stage and viewport
- countdown and recording state
- Calculator scenario flow
- replay and artifact presentation

The purpose is to preserve the strong product instincts from prior work without
re-importing the old architectural problems.

## Scope

### Included

- macOS-only session flow
- native HUD window
- backdrop and viewport framing
- recording countdown
- clear recording-state visuals
- Calculator launch and focus
- click, key press, and type support
- session logs
- screenshot capture
- raw video capture
- replay of the most recent run

### Deferred

- browser flows
- Notes scenario
- subtitle generation
- chapter cards
- voiceover and music timing
- Remotion final export
- multi-window stage layouts
- vision-only target selection

## Success Criteria

The milestone is successful when all of the following are true:

- A user can start a guided session from a single control surface.
- The HUD remains visible and useful during the full run.
- The system can visibly count into recording.
- The viewport clearly indicates what is being captured.
- The area outside the viewport dims during countdown and recording.
- Calculator can be launched, focused, and fit into the viewport.
- The runtime can execute a short deterministic demo using both clicks and keys.
- Every major state transition and action appears in the HUD log.
- The session saves at least one video, one screenshot, and one trace file.
- The most recent run can be replayed from the HUD.

## Primary Demo Scenario

Calculator is the first target because it is simple, native, and good at proving
basic interaction primitives.

### Scenario

1. Start a new session.
2. Select a backdrop preset.
3. Open Calculator.
4. Fit Calculator into the viewport.
5. Trigger a `3, 2, 1` countdown.
6. Start recording.
7. Execute a short expression using both keyboard and click input.
8. Capture a screenshot during or after the interaction.
9. Stop recording automatically or through the HUD.
10. Save artifacts and offer replay.

### Suggested Interaction Sequence

- type `12`
- click `+`
- type `30`
- press `=`

This is enough to prove:

- target window selection
- focus control
- key input
- pointer movement and click
- action logging
- artifact capture

## User Experience Requirements

### HUD

The HUD is a first-class product surface, not a debug panel.

It should show:

- current session state
- elapsed time or recording timer
- current target app
- control buttons
- recent log events
- recent artifacts

Controls for v1 of the HUD:

- `Start`
- `Pause`
- `Stop`
- `Replay Last Run`
- `Quit`

The HUD should feel deliberate and presentable:

- compact
- readable
- elegant
- stable in position
- visually distinct from the captured viewport

There may be two HUD layers over time:

- a minimal native HUD for always-on capture state and immediate controls
- a richer TS-side HUD for logs, diagnostics, artifacts, and operator workflows

For this milestone, the TS HUD is an acceptable first implementation surface as
long as runtime truth still lives below it.

### Stage, Backdrop, and Viewport

The stage is the operator's framing surface.

It should support:

- a chosen backdrop treatment
- one primary viewport
- clear distinction between on-stage content and surrounding space
- window fitting that does not feel accidental

The viewport is the authoritative capture region for the live demo.

### Recording State

Recording must be unmistakable.

The system should provide:

- visible countdown
- dimming outside the viewport
- explicit recording indicator
- obvious transition from staging to recording

## Architectural Implications

This milestone is mostly about three layers:

### 1. Native Engine

Owns:

- window enumeration
- window movement and sizing
- ScreenCaptureKit session control
- native overlays for countdown or viewport emphasis
- input synthesis
- app launch/focus integration

### 2. Runtime

Owns:

- session creation
- lifecycle transitions
- command dispatch
- action execution sequencing
- trace collection
- artifact registration
- replay metadata

### 3. HUD Frontend

Owns:

- user controls
- session-state presentation
- logs view
- artifact list
- replay trigger

The composer is not the main concern in this milestone. The live system is.

## Session Lifecycle For This Milestone

The generic runtime lifecycle should be specialized into an operator-facing flow:

- `created`
- `staging`
- `countdown`
- `recording`
- `paused`
- `completing`
- `completed`
- `failed`
- `cancelled`

Notes:

- `staging` means the target is being prepared and framed.
- `countdown` is a visible pre-recording phase.
- `recording` means capture is live.
- `paused` should preserve enough session state to resume or stop cleanly.

The shared protocol can continue using the broader lifecycle, but the product
surface should expose this narrower guided-capture vocabulary.

## Runtime Events

The run should emit structured events that are useful both for the HUD and for
later composition.

Minimum event categories:

- session state changed
- backdrop selected
- viewport updated
- app launched
- window focused
- countdown tick
- recording started
- recording paused
- recording stopped
- action planned
- action started
- action completed
- action failed
- screenshot captured
- video artifact finalized
- replay requested

Every event should have:

- timestamp
- session id
- type
- human-readable summary
- structured payload

## Artifacts

Minimum artifacts for this milestone:

- raw screen capture video
- screenshot
- trace log
- session metadata

Recommended session folder layout:

```text
artifacts/sessions/<session-id>/
  session.json
  trace.json
  capture.mov
  screenshot-final.png
```

## Package Responsibilities

### `packages/protocol`

- session states
- action and observation types
- HUD event payloads
- artifact metadata types

### `packages/runtime`

- session manager
- lifecycle rules
- trace storage
- artifact registration
- guided-session orchestration

### `packages/cli`

- local operator commands for development
- session start/stop/replay wiring

### `packages/composer-core`

- not primary for this milestone
- may define the future shape of render-manifest inputs

### `native/engine`

- native capture control
- window fitting
- overlays
- app launch/focus
- input synthesis

## Delivery Plan

### Phase 1: Session Skeleton

- finalize milestone-specific lifecycle states
- add runtime event stream for HUD consumption
- define artifact directory layout

### Phase 2: HUD Shell

- create HUD window
- add controls
- add status area
- add scrolling event log
- add artifact list and replay control

### Phase 3: Stage and Viewport

- create backdrop surface
- define viewport region
- fit Calculator into viewport
- add non-captured dimmed surroundings

### Phase 4: Recording Control

- implement countdown
- implement start/stop recording
- implement screenshot capture
- save artifacts per session

### Phase 5: Deterministic Calculator Demo

- open Calculator
- focus window
- run click and keyboard actions
- record action traces in real time

### Phase 6: Replay

- make last run discoverable
- open or preview the latest capture from the HUD

## Definition Of Done

This milestone is done when:

- the full Calculator scenario runs from a single operator flow
- the HUD stays informative and responsive throughout
- recording state is visually clear
- artifacts are saved to a predictable session folder
- replay of the latest run works
- the trace is useful enough to debug failures afterward

## Follow-On Milestones

If this milestone lands well, the next likely milestones are:

1. manual website capture with trace recording
2. Notes scenario with richer typing and selection behavior
3. trace-to-scenario compilation
4. composer-driven polish from captured sessions

That sequence preserves the architectural idea that live capture creates the raw
truth, and composition upgrades presentation later.
