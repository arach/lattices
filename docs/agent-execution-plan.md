# Agent Execution Plan

This document turns the architectural review into an implementation plan based on the current product priorities:

1. Predictability
2. Traceability
3. Reversibility later, but not as the first constraint

It also fixes the initial migration target:

- first-class execution path = daemon API
- preferred operator surface = agentic voice
- first use case = dictation or agent command -> daemon action -> reliable window/layer/layout outcome

This is intentionally daemon-first. If the daemon becomes the canonical execution boundary, voice, HUD, command palette, and workers can all become thinner clients.

## Product framing

There are three action families we need to support first.

### 1. Window-specific actions

These target a specific window and a destination.

Examples:

- "Chrome to the top right corner"
- "Terminal to the right third"
- "Move Slack to the bottom quarter"
- "Put Xcode in the upper third"

Core shape:

- target window
- destination

### 2. Layer-specific actions

These bring up an existing layer and arrange it coherently according to stored preferences.

Examples:

- "Bring up review"
- "Switch to mobile"
- "Open the web layer"

Expectation:

- honor existing layer and project preferences
- launch or focus what is needed
- tile the result coherently
- do not invent too much intelligence beyond declared preferences

### 3. Space-optimization actions

These take the current set of visible or selected windows and make the desktop "nice."

Examples:

- "Make this nice"
- "Organize these windows"
- "Clean up the layout"
- "Arrange this space"

Expectation:

- produce a good mosaic or grid
- be deterministic
- explain why the chosen arrangement happened

## Goals

### Must-have

- Every execution path is predictable.
- Every execution returns a trace explaining what happened.
- Every action is represented in one canonical schema.
- Voice and agents submit structured actions to the daemon.

### Nice-to-have later

- Undo
- Full transaction replay
- Layout previews before commit
- Smarter semantic layouts such as `review` or `focus`

### Non-goal for v1

- Building a fully autonomous planner that improvises layouts beyond declared rules

## Architecture decision

The daemon becomes the canonical mutation boundary.

That means:

- interpretation can happen anywhere
- planning and execution live behind the daemon
- all clients get the same semantics

In practice:

- local voice extracts actions, then calls daemon
- hands-off worker emits actions, then calls daemon
- HUD keys emit actions, then call daemon
- command palette emits actions, then calls daemon

This avoids multiple execution semantics in app code.

## Canonical execution model

We should introduce four core types.

### 1. `ActionRequest`

Represents what the operator asked for.

```json
{
  "id": "req_123",
  "source": "voice",
  "intent": "window.place",
  "targets": [{ "kind": "window_ref", "value": "frontmost" }],
  "args": {
    "placement": "top-right"
  },
  "rawUtterance": "put this in the top right corner"
}
```

### 2. `ExecutionPlan`

Represents the resolved plan before mutation.

```json
{
  "id": "plan_123",
  "requestId": "req_123",
  "steps": [
    {
      "kind": "resolveWindow",
      "result": { "wid": 38192, "app": "Google Chrome", "title": "Docs" }
    },
    {
      "kind": "placeWindow",
      "result": { "display": 0, "frame": { "x": 960, "y": 0, "w": 960, "h": 540 } }
    }
  ],
  "explanation": [
    "Resolved 'this' to the frontmost window",
    "Mapped 'top-right' to the top-right quarter of display 1"
  ]
}
```

### 3. `ExecutionReceipt`

Represents what actually happened.

```json
{
  "id": "exec_123",
  "requestId": "req_123",
  "status": "ok",
  "applied": [
    {
      "kind": "window.place",
      "wid": 38192,
      "before": { "x": 120, "y": 80, "w": 1280, "h": 900 },
      "after": { "x": 960, "y": 0, "w": 960, "h": 540 }
    }
  ],
  "trace": [
    "DesktopModel matched frontmost window",
    "Window moved by AX batch path"
  ]
}
```

### 4. `ExecutionTrace`

Represents the scrutable explanation layer.

This is the object the user should be able to inspect when they ask:

- why did you move that?
- why did you choose that layout?
- which rule applied?

This is separate from logging. It is product data.

## Initial action vocabulary

The first version should stay intentionally small.

### Window actions

- `window.place`
- `window.focus`
- `window.present`

`window.place` is the core mutation.

Arguments:

- `placement`
- optional `display`
- optional `strategy`

Targets:

- `wid`
- `session`
- `app_title`
- `frontmost`
- `selection`

### Layer actions

- `layer.activate`

Arguments:

- `mode`: `focus` or `launch`
- optional `force`

This should wrap current `layer.switch` / `tileLayer(...)` semantics, but return an execution receipt instead of silently doing best-effort work.

### Space actions

- `space.optimize`

Arguments:

- `scope`: `visible`, `selection`, `current_display`, `current_space`
- `strategy`: `mosaic`, `grid`, `balanced`

This wraps current `layout.distribute`, but with an explicit strategy and trace.

## Placement grammar

We need one shared placement grammar for all clients.

### v1 named placements

- `maximize`
- `center`
- `left`
- `right`
- `top`
- `bottom`
- `top-left`
- `top-right`
- `bottom-left`
- `bottom-right`
- `left-third`
- `center-third`
- `right-third`
- `top-third`
- `middle-third`
- `bottom-third`
- `left-quarter`
- `right-quarter`
- `top-quarter`
- `bottom-quarter`

Important note:

`top-third`, `middle-third`, and `bottom-third` should become real first-class placements, not inferred hacks. Right now the codebase has better support for vertical thirds than horizontal thirds. The grammar should fix that.

### v1 generic placement form

- `grid:CxR:C,R`

Examples:

- `grid:3x1:2,0`
- `grid:1x3:0,0`
- `grid:4x2:3,1`

### v1 display selector

Optional wrapper:

- `display:current:left`
- `display:2:grid:1x3:0,0`

If that wrapper feels too awkward for public API, keep it structured:

```json
{
  "placement": "grid:1x3:0,0",
  "display": "current"
}
```

## Planning rules

Planning must be deterministic.

### Rule 1. Resolve target before applying placement

No side effects should start until target resolution succeeds or a launch/fallback policy is chosen.

### Rule 2. Return the matching reason

Every resolved target should include why it matched:

- frontmost
- exact session tag
- exact `wid`
- app + title match
- rule-based layer member

### Rule 3. If ambiguous, fail clearly unless policy says otherwise

For example:

- "Chrome to the right" with 4 Chrome windows should fail or request disambiguation in agent mode unless a deterministic policy exists

Possible policy order:

1. exact title match
2. exact session match
3. frontmost matching app
4. z-order first visible matching app

But whichever order we pick must be explicit and returned in the trace.

### Rule 4. Layer activation plans should be compositional

`layer.activate` should produce a plan containing:

- windows already running
- sessions to launch
- companion apps to launch
- placements to apply
- fallbacks for untracked windows

This is already partly present in `WorkspaceManager.tileLayer(...)`; the goal is to formalize it as plan data.

### Rule 5. Space optimization must always declare its strategy

If the system chooses a mosaic, it must say why.

Examples:

- "Used 2x2 grid because 4 windows were in scope"
- "Used 3-column mosaic because 5 windows fit better in landscape"

## Traceability design

Traceability is a product feature, not an internal debugging detail.

Every mutation endpoint should return:

- `request`
- `resolvedTargets`
- `appliedRules`
- `computedFrames`
- `executionPath`
- `failures`

### Example trace fields

```json
{
  "resolvedTargets": [
    {
      "input": "Chrome",
      "resolution": "wid",
      "wid": 38192,
      "reason": "frontmost app match"
    }
  ],
  "appliedRules": [
    "placement top-right -> grid 2x2 cell 1,0",
    "display current"
  ],
  "executionPath": [
    "DesktopModel",
    "AX batch move"
  ]
}
```

## Daemon changes

We should not immediately remove existing endpoints. We should add a new execution layer and gradually migrate callers.

### New endpoints

### `actions.execute`

Primary mutation endpoint.

Input:

- one action or a batch of actions

Output:

- execution receipt with trace

### `actions.plan`

Dry-run planner.

Input:

- same as `actions.execute`

Output:

- execution plan with no side effects

This is critical for predictability and future previews.

### `actions.history`

Recent receipts.

Output:

- recent execution receipts for scrutability

This is also the future basis for undo.

### Existing endpoints to wrap first

These should internally route into the new planner/executor as early as possible:

- `window.tile`
- `window.present`
- `layout.distribute`
- `layer.switch`

Those existing RPC names can remain stable while their internals are replaced.

## Migration order

### Phase 1. Build the daemon execution core

Files likely involved:

- `app/Sources/LatticesApi.swift`
- new planner/executor files under `app/Sources/`
- `app/Sources/WindowTiler.swift`
- `app/Sources/WorkspaceManager.swift`

Deliverables:

- `ActionRequest`
- `ExecutionPlan`
- `ExecutionReceipt`
- shared placement parser
- `actions.plan`
- `actions.execute`

### Phase 2. Migrate existing daemon mutations

Replace internal implementations for:

- `window.tile`
- `layout.distribute`
- `layer.switch`

Deliverables:

- stable behavior through old API names
- receipts and traces returned in responses

### Phase 3. Make voice call the daemon directly

Files likely involved:

- `app/Sources/VoiceIntentResolver.swift`
- `app/Sources/IntentEngine.swift`
- `app/Sources/HandsOffSession.swift`

Deliverables:

- local voice emits canonical actions
- hands-off worker emits canonical actions
- no second interpretation pass for worker actions

### Phase 4. Migrate HUD and command palette

Files likely involved:

- `app/Sources/HUDController.swift`
- `app/Sources/PaletteCommand.swift`

Deliverables:

- all surfaces use the same planner/executor
- same traces available no matter how action was triggered

## Immediate implementation slice

The first practical slice should be:

1. Add a shared placement parser with first-class support for:
   - existing `TilePosition` names
   - `grid:CxR:C,R`
   - new `top-third`, `middle-third`, `bottom-third`
   - new quarter aliases
2. Add `actions.plan` and `actions.execute` for:
   - `window.place`
   - `space.optimize`
   - `layer.activate`
3. Reimplement `window.tile` as a wrapper around `window.place`
4. Return a structured receipt from daemon mutations

That gives immediate product value:

- voice can target the daemon directly
- placement semantics stop drifting
- "why did you do that?" has a real answer

## Example v1 utterance mappings

These should become golden examples for tests.

### Window placement

- "Put Chrome in the top right corner" -> `window.place(target=Chrome, placement=top-right)`
- "Move Terminal to the right third" -> `window.place(target=Terminal, placement=right-third)`
- "Put this in the upper third" -> `window.place(target=frontmost, placement=top-third)`
- "Bottom quarter for Slack" -> `window.place(target=Slack, placement=bottom-quarter)`

### Layer activation

- "Bring up review" -> `layer.activate(name=review, mode=launch)`
- "Switch to mobile" -> `layer.activate(name=mobile, mode=focus)`

### Space optimization

- "Make this nice" -> `space.optimize(scope=visible, strategy=mosaic)`
- "Organize these windows" -> `space.optimize(scope=selection_or_visible, strategy=balanced)`

## Definition of success

This initiative is successful when:

- the daemon can plan and execute all three action families
- voice can issue those actions without direct subsystem calls
- every execution returns a scrutable receipt
- placement vocabulary is shared across all clients
- layout outcomes stop depending on which interface triggered them

## Recommendation

Start with daemon execution for `window.place`.

Why:

- it is the smallest useful vertical slice
- it serves voice immediately
- it forces the placement grammar to become canonical
- it establishes the receipt/trace model early
- it unlocks layer and optimize-space actions without rework
