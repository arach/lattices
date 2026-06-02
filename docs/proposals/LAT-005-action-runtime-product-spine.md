# LAT-005: Action Runtime and Product Spine

## Status

Proposed.

## Summary

Lattices already has the pieces of a programmable workspace: a CLI,
native macOS app, daemon API, command palette, HUD, voice, hands-off mode,
screen search, overlays, session layers, tab groups, and a companion deck
contract.

What is missing is the product and execution spine that makes those pieces
feel like one system.

This proposal introduces an **Action Runtime** as the shared path for
planning, executing, explaining, and later undoing workspace mutations.
Every control surface should become a client of this runtime:

- CLI
- daemon RPC
- command palette
- hotkeys and HUD
- local voice
- hands-off voice
- companion deck
- future automations

The goal is not to add another large feature surface. The goal is to make
existing surfaces converge on the same action model:

```text
input -> canonical action -> plan -> execute -> verify -> receipt -> history
```

## Collaboration Notes

This proposal was drafted from three Codex subagent review lanes:

- **Product/UX review**: shipped capabilities, missing product cohesion,
  and user-facing priorities.
- **Architecture/API review**: action runtime, endpoint shape, module
  boundaries, and migration risks.
- **Verification/release review**: test coverage, CI gaps, packaging,
  docs truth, and operational readiness.

No Scout coordination was used.

## Current Strengths

Lattices does not need a new north star. The current product already has a
strong one: make the Mac workspace observable and controllable.

Important shipped strengths:

- Persistent tmux workspaces with config, sync, restart, tab groups, and
  session naming shared by CLI and app.
- A native macOS app with project discovery, menu bar control, command
  palette, settings, onboarding, permission guidance, and hotkeys.
- Window inventory, session title tags, Spaces support, tiling, drag snap,
  screen map, OCR/search, and fallback paths through CG, AX, and AppleScript.
- A daemon with typed read and mutation endpoints, `api.schema`, and a
  Node client for agents and scripts.
- Emerging canonical mutations: `window.place`, `layer.activate`, and
  `space.optimize`.
- Overlay primitives for transient visual feedback and persistent actors.
- Voice and hands-off flows that can interpret natural language into
  workspace actions.
- A companion deck contract and local bridge that can expose Lattices to
  iPhone/iPad surfaces.
- Useful security instincts: explicit permissions, local-first daemon,
  opt-in OCR, scoped companion pairing, and capability checks.

The product is broad enough for a serious beta. The next step is cohesion.

## Problem

The UX is ahead of the execution model.

Lattices has many capable surfaces, but they do not yet all share one
meaning for "do this workspace action." The result is a product that can
feel powerful but uneven:

- The command palette, HUD, voice, daemon, companion, and CLI can reach
  similar outcomes through different code paths.
- `window.place`, `layer.activate`, and `space.optimize` exist, but the
  deeper runtime behind them is still thin.
- Receipts often say the action was accepted or queued, but not always
  what changed, what frame was computed, whether the move verified, or why
  a target was chosen.
- Targeting is strong for explicit `wid` and lattices session tags, but
  generic app/title matching still needs confidence, ambiguity handling,
  previews, and user-facing explanation.
- Layers and groups exist, but saved workspace recipes, editable rules,
  semantic layout strategies, drift recovery, and undo-ready history are
  not yet first-class product objects.
- The docs describe a canonical model, but the implementation is not yet
  fully centralized around it.
- Test and release workflows do not yet verify the full product contract.

In short: Lattices has enough surfaces. It needs one action spine.

## Goals

1. Make the daemon-backed action runtime the canonical mutation boundary.
2. Let all major surfaces compile into the same canonical action request.
3. Support dry-run planning before side effects.
4. Return structured receipts with target resolution, computed frames,
   applied mutations, failures, and trace entries.
5. Record action history as the substrate for explanations, debugging, and
   limited undo.
6. Add a shared target resolver with confidence and ambiguity policy.
7. Keep existing endpoint names working as compatibility wrappers.
8. Make product surfaces easier to explain: launcher, inventory, layout,
   assistant, and companion should all feel like views over the same system.
9. Add verification and release gates that keep docs, API behavior, package
   contents, and shipped app claims truthful.

## Non-Goals

- Do not build a fully autonomous desktop planner in the first version.
- Do not promise full undo for every side effect. Start with window geometry.
- Do not rewrite `WindowTiler` in one pass.
- Do not remove existing daemon endpoints or CLI commands.
- Do not replace command palette, HUD, voice, or companion UX. Make them
  thinner clients of the shared runtime.
- Do not make OCR, AI, or companion control mandatory.

## Product Model

The product should be presented as a programmable workspace control plane,
not as a fully autonomous desktop agent.

The user-facing loop should be:

1. **Ask or act**
   - A user presses a hotkey, chooses a palette command, speaks, uses the
     companion, or calls the daemon.
2. **Plan**
   - Lattices resolves targets, computes placements, finds missing projects
     or windows, and explains ambiguity before mutation where possible.
3. **Execute**
   - The runtime applies moves, launches sessions, focuses windows, or
     activates layers through one executor.
4. **Receipt**
   - The surface shows what happened, why it happened, and any failures.
5. **History**
   - The action is inspectable and, when safe, undoable.

### Product Surfaces

The existing surfaces should have clearer roles:

| Surface | Role |
| --- | --- |
| Home | Status, health, active workspaces, suggested next action |
| Palette | Fast command launcher over canonical actions |
| Search / Inventory | Find windows, sessions, projects, text, and targets |
| Layout / Screen Map | Visual planning and editing for windows, layers, and recipes |
| HUD / Hotkeys | Fast tactile control for common actions |
| Voice / Hands-off | Natural-language action extraction and confirmation |
| Assistant | Planner, explainer, and recovery helper |
| Companion | Remote control surface over the same action contract |
| CLI / Daemon | Scriptable and agent-facing transports |

This keeps the app broad without making every surface invent its own rules.

## Proposed Action Runtime

Add a new runtime under:

```text
apps/mac/Sources/Core/Actions/Execution/
```

Initial modules:

| Module | Responsibility |
| --- | --- |
| `ActionRegistry` | Canonical verbs, params, aliases, phrase hints, labels, and source support |
| `ActionPlanner` | Resolve targets and compute plans without side effects |
| `ActionExecutor` | Commit plans, verify outcomes, record receipts |
| `ActionHistoryStore` | Recent receipts, undo tokens, diagnostics, and inspection |
| `WindowTargetResolver` | Resolve `wid`, session, app/title, frontmost, selection, and query targets |
| `WindowPresenter` | Own move, resize, raise, activate, mark-interaction, and verification flow |
| `LayerActivationPlanner` | Extract planning from `WorkspaceManager.tileLayer` |
| `SpaceOptimizationPlanner` | Plan balanced/mosaic/grid arrangements before applying them |

`PlacementSpec` should remain the shared placement grammar. It is already
the right seed: named tiles, grids, and fractional placements all compile
into one typed model.

### Core Types

#### `ActionRequest`

```json
{
  "requestId": "req_123",
  "source": "voice",
  "actions": [
    {
      "id": "act_123",
      "type": "window.place",
      "target": { "kind": "frontmost" },
      "args": {
        "placement": { "kind": "tile", "value": "top-right" },
        "display": "current"
      },
      "policy": {
        "ambiguity": "fail",
        "verify": true
      }
    }
  ]
}
```

#### `ActionPlan`

```json
{
  "planId": "plan_123",
  "requestId": "req_123",
  "status": "ready",
  "resolvedTargets": [
    {
      "input": { "kind": "frontmost" },
      "resolution": "wid",
      "wid": 38192,
      "app": "Google Chrome",
      "title": "Docs",
      "confidence": 1.0,
      "reason": "frontmost window"
    }
  ],
  "computedFrames": [
    {
      "wid": 38192,
      "placement": { "kind": "tile", "value": "top-right" },
      "frame": { "x": 960, "y": 25, "w": 960, "h": 527 }
    }
  ],
  "steps": [
    { "kind": "placeWindow", "wid": 38192 }
  ],
  "trace": [
    {
      "phase": "target.resolve",
      "code": "frontmost",
      "message": "Resolved target to the frontmost window"
    }
  ]
}
```

#### `ExecutionReceipt`

```json
{
  "receiptId": "exec_123",
  "requestId": "req_123",
  "planId": "plan_123",
  "status": "ok",
  "applied": [
    {
      "kind": "window.place",
      "wid": 38192,
      "before": { "x": 120, "y": 80, "w": 1280, "h": 900 },
      "after": { "x": 960, "y": 25, "w": 960, "h": 527 },
      "verified": true
    }
  ],
  "failures": [],
  "trace": [
    {
      "phase": "execute.placeWindow",
      "code": "ax.move.verified",
      "message": "Moved and verified the target frame"
    }
  ],
  "undoToken": "undo_123"
}
```

Trace entries should be structured objects, not only strings. They are
product data: users and agents should be able to ask why an action happened.

### Status Semantics

`actions.execute` should support four statuses:

| Status | Meaning |
| --- | --- |
| `ok` | All planned mutations applied and verified |
| `partial` | Some mutations applied, some failed or are pending |
| `failed` | No meaningful mutation applied |
| `accepted` | Long-running work was queued, such as launching missing projects |

Window placement can usually return `ok` or `failed` quickly. Layer
activation may need `accepted` or `partial` because project launches and
post-launch tiling are asynchronous.

## Proposed Daemon Endpoints

Add these endpoints while keeping existing names stable.

### `actions.catalog`

Returns canonical actions, params, target kinds, compatibility aliases,
surface labels, and phrase hints.

Uses:

- command palette generation
- voice/hands-off prompt assembly
- companion manifest alignment
- docs generation and API truth checks

### `actions.plan`

Dry-run action planning. No side effects.

Responsibilities:

- resolve targets
- compute frames
- expand layer and space actions into steps
- detect ambiguity
- report missing permissions
- return warnings and trace entries

### `actions.execute`

Primary mutation endpoint.

Responsibilities:

- accept one action or a batch
- optionally run `actions.plan` first
- apply side effects through the executor
- verify when feasible
- record an execution receipt
- return `ok`, `partial`, `failed`, or `accepted`

Important options:

```json
{
  "dryRun": false,
  "atomic": false,
  "verify": true,
  "timeoutMs": 1500,
  "source": "daemon"
}
```

### `actions.history`

Returns recent receipts filtered by:

- action type
- source
- window id
- session
- project
- status

This powers diagnostics, user explanation, and undo.

### `actions.undo`

Define the contract now, ship narrowly later.

Initial undo scope:

- restore window frames for `window.place`
- restore window frames for `space.optimize`

Deferred undo scope:

- launches
- kills
- app opens
- session mutation
- Space movement
- layer membership changes

## Compatibility Wrappers

Existing endpoints should stay, but route internally through the runtime.

| Existing endpoint | Runtime mapping |
| --- | --- |
| `window.place` | `actions.execute(type=window.place)` |
| `window.tile` | Compatibility wrapper for `window.place` |
| `window.focus` | `actions.execute(type=window.focus)` |
| `window.present` | `actions.execute(type=window.present)` |
| `space.optimize` | `actions.execute(type=space.optimize)` |
| `layout.distribute` | Compatibility wrapper for `space.optimize` |
| `layer.activate` | `actions.execute(type=layer.activate)` |
| `layer.switch` | Compatibility wrapper for `layer.activate` |
| `intents.execute` | Translator from old intent names to canonical action types |
| `deck.perform` | Companion action wrapper around runtime receipts |

CLI commands should prefer the daemon/runtime path when available and keep
direct AppleScript or local fallbacks only for daemon-unavailable scenarios.

## Target Resolution

Target resolution is the largest user-facing trust issue.

Create `WindowTargetResolver` as the single resolver for:

- `wid`
- lattices session name
- app name
- app plus title substring
- frontmost window
- current selection
- query result
- layer member
- project/session relation

Every resolution should return:

- resolved target
- confidence
- reason
- ambiguity candidates when applicable
- permissions or data sources used

Default policies:

| Source | Ambiguous app target policy |
| --- | --- |
| daemon/script/agent | fail with candidates |
| CLI interactive | choose top candidate only with clear output, or ask later |
| voice | prefer frontmost matching app, otherwise fail with prompt |
| HUD/hotkey | prefer current/frontmost context |
| companion | prefer explicit selected item |

The receipt must always say which policy was used.

## Layers, Rules, and Recipes

Layers and groups should become editable workspace recipes rather than only
config records or runtime snapshots.

First-class concepts:

- **Layer**: named workspace context with projects, apps, windows, rules, and
  preferred layout.
- **Rule**: target matching plus intended placement or display.
- **Recipe**: saved arrangement that can be planned, applied, reconciled, and
  inspected.
- **Drift**: current workspace differs from the recipe.
- **Reconcile**: plan and apply the smallest useful recovery.

This extends existing workspace layers and session layers rather than
replacing them.

Initial rule examples:

```json
{
  "target": { "kind": "session", "name": "frontend-a1b2c3" },
  "placement": { "kind": "tile", "value": "left" },
  "display": 0
}
```

```json
{
  "target": { "kind": "appTitle", "app": "Google Chrome", "title": "localhost" },
  "placement": { "kind": "tile", "value": "right" },
  "policy": { "ambiguity": "fail" }
}
```

`layer.activate` should produce a plan containing:

- running windows
- missing projects
- apps to launch
- windows to move
- placements to compute
- fallbacks
- post-launch pending steps
- failures

## Surface Migration

### CLI

Move these commands to the runtime path first:

- `lattices place`
- `lattices tile`
- `lattices distribute`
- `lattices layer`

Keep direct local tiling only as a fallback when the daemon is unavailable.

### Command Palette

Palette rows should become bindings of:

```text
ActionID + TargetRef + Args
```

Palette remains a fast launcher, but stops owning execution semantics.

### HUD and Hotkeys

HUD can keep its tactile cockpit behavior. The change is that key routing
should emit runtime actions instead of privately computing layouts.

HUD may still provide source-specific policy:

- target frontmost window
- use current display
- prefer low-latency execution

But placement, target resolution, receipt, and history should be shared.

### Voice and Hands-off

Voice should do interpretation, not execution policy.

Local voice:

- transcript cleanup
- intent/action extraction
- slot extraction
- confidence and confirmation UX

Runtime:

- target resolution
- planning
- execution
- receipt
- history

Hands-off worker output should be canonical actions, not a second grammar
that Swift reinterprets through another matcher.

### Companion Deck

`deck.perform` should include action receipts in its `ActionOutcome`.

The companion bridge should authorize action families, not blanket mutation
access. Example capability families:

- `actions.read`
- `actions.window`
- `actions.layer`
- `actions.session`
- `actions.input`

### Assistant

The assistant should become the planner/explainer surface:

- "What will happen if I do this?"
- "Why did that move?"
- "What failed?"
- "Can you restore the previous layout?"

It should call `actions.plan`, `actions.execute`, and `actions.history`
instead of inventing its own execution semantics.

## Migration Plan

### Phase 1: Action Runtime Skeleton

Deliverables:

- `ActionID`
- `ActionSource`
- `TargetRef`
- `ActionRequest`
- `ActionPlan`
- `ExecutionReceipt`
- `ActionTraceEntry`
- `ActionRegistry`
- `ActionHistoryStore`
- `actions.catalog`
- `actions.plan`
- `actions.execute`

Scope:

- support `window.place`
- support explicit `wid`, `session`, and `frontmost`
- support `PlacementSpec`
- record receipts
- verify window frame when feasible

This is the first vertical slice.

### Phase 2: Target Resolver and Wrappers

Deliverables:

- `WindowTargetResolver`
- ambiguity candidate shape
- confidence/reason fields
- `window.place` wrapper over `actions.execute`
- `window.tile` compatibility wrapper
- `IntentEngine.tile_window` using the same path for all target kinds

Scope:

- `wid`
- session
- app/title
- frontmost
- query-selected result

### Phase 3: Space Optimization

Deliverables:

- `SpaceOptimizationPlanner`
- real strategy names
- `space.optimize` wrapper over `actions.execute`
- `layout.distribute` compatibility wrapper
- structured receipts with affected windows and computed frames

Decision:

- Either make `mosaic` a distinct strategy or stop exposing it as distinct
  while it uses the same smart-grid implementation as `balanced`.

### Phase 4: Layer Activation Planning

Deliverables:

- `LayerActivationPlanner`
- `layer.activate` wrapper over `actions.execute`
- pending steps for launches
- post-launch receipts or follow-up events
- drift/reconcile language for layer recipes

Scope:

- existing config layers
- session layers
- project launch/focus/retile behavior
- placement rules where already available

### Phase 5: Surface Convergence

Deliverables:

- CLI uses runtime by default.
- Palette emits action requests.
- HUD/hotkeys emit action requests.
- Local voice emits action requests.
- Hands-off worker emits action requests.
- Companion includes runtime receipts.
- Assistant reads `actions.history`.

The visible UX should remain familiar while the internals converge.

### Phase 6: Undo-ready History

Deliverables:

- `actions.history`
- limited `actions.undo`
- window geometry restore for placement and optimization
- UI affordance in HUD, palette, voice, companion, and assistant

Do not expand undo beyond geometry until receipts are reliable.

## Verification and Release Readiness

The action runtime should ship with a verification track, not as a pure
architecture refactor.

### Current Coverage Gaps

- Root checks typecheck TypeScript and build the Swift app, but do not run
  Swift tests by default.
- Daemon E2E tests require a live local daemon and real desktop state.
- Voice phrase evals are useful but manually gated.
- Hands-off evals are useful but should be made clearer about pass/fail
  semantics.
- Swift tests are mostly live Stage Manager/window experiments, not
  deterministic CI units.
- `DeckKit` model tests exist but are not part of the root `check`.
- There is no headless fake desktop/window backend for CI.
- Docs can drift from API truth, including method counts and command lists.

### Proposed Test Tiers

#### Tier 1: Deterministic PR Checks

Run on every PR:

- TypeScript typecheck.
- Swift app build.
- `DeckKit` Swift tests.
- Placement parser tests.
- target resolver tests with fake windows.
- daemon schema contract tests.
- CLI command/help snapshot tests.
- docs agent artifact generation.
- site build.

#### Tier 2: Local Daemon Smoke

Run on release candidates or manual macOS runners:

- launch app
- confirm daemon health
- call `api.schema`
- call read endpoints
- execute dry-run plans
- run voice simulate evals
- verify package-installed CLI can talk to daemon

#### Tier 3: Live Desktop Acceptance

Document and run manually or on a controlled Mac:

- actual window placement
- Screen Recording and Accessibility fallback paths
- Stage Manager behavior
- Spaces movement
- OCR scan/search
- companion bridge pairing
- app update and relaunch

### CI and Release Hardening

Add a normal PR CI workflow:

```text
bun install --frozen-lockfile
bun run check:types
swift build --package-path apps/mac
swift test --package-path swift
bun run site:build
bun run docs:agent
```

Add package smoke:

- `npm pack`
- install into a temporary prefix
- run `lattices help`
- assert package files are present
- validate runtime requirement wording

Add docs truth checks:

- daemon method list generated from `api.schema` or source registry
- CLI command list generated or checked against `lattices help`
- install/runtime requirements checked against package reality
- canonical action list checked against `ActionRegistry`

Strengthen release candidate checks:

- root `check`
- Swift package tests
- package smoke
- site build
- docs artifacts
- unsigned DMG build
- iOS simulator build
- optional daemon smoke on a prepared Mac

Strengthen release publish checks:

- version/tag consistency
- package contents
- DMG mount/install smoke
- notarization and staple validation
- post-launch daemon health
- rollback/update notes

## Documentation Plan

After the runtime lands, update docs around one vocabulary:

- "dozens of RPC methods" unless a generated count is used.
- `window.place`, `layer.activate`, and `space.optimize` as stable
  compatibility-level actions.
- `actions.plan`, `actions.execute`, and `actions.history` as the canonical
  action runtime.
- OCR is local, opt-in, and retention-limited.
- Companion control is capability-scoped.
- Undo is initially geometry-only.

Docs to update:

- `docs/api.md`
- `docs/agents.md`
- `docs/tiling-reference.md`
- `docs/voice.md`
- `docs/layers.md`
- `README.md`
- agent docs artifacts generated by `apps/site/scripts/agent-docs.mjs`

## Risks and Decisions

### Verification Timing

Question: should `actions.execute` wait for verification?

Recommendation:

- wait for quick window operations
- return `accepted` for long-running launch/layer operations
- emit or record follow-up receipts for delayed steps

### Ambiguous Targets

Question: what should "Chrome right" mean with four Chrome windows?

Recommendation:

- daemon/agent default: fail with candidates
- voice default: use frontmost matching app only when clear
- HUD default: use current/frontmost context
- always record policy in the receipt

### Undo Scope

Question: how much undo should ship?

Recommendation:

- start with window geometry only
- defer launches, kills, session mutations, app opens, and Space moves

### Planner Location

Question: should planning live in TypeScript or Swift?

Recommendation:

- language interpretation can live in TypeScript
- desktop-state planning belongs in Swift, because Swift owns AX, CG,
  SkyLight, permissions, and current window state

### Backward Compatibility

Question: should old endpoints disappear?

Recommendation:

- no
- keep old endpoint names as wrappers
- make the internal runtime and receipt shape better without breaking agents

### Companion Security

Question: how much can the companion invoke?

Recommendation:

- authorize by action family
- do not grant broad mutation access by default
- make receipts visible to the companion so remote actions stay inspectable

## Success Criteria

This proposal is successful when:

- `actions.plan` can describe what will happen for `window.place`.
- `actions.execute(window.place)` returns a verified receipt for a real move.
- `window.place` and `window.tile` route through the runtime.
- voice, CLI, and one native UI surface use the same runtime path for
  placement.
- `actions.history` can answer "what just happened?"
- ambiguous app targets return useful candidates instead of silent guesses in
  agent/script mode.
- `space.optimize` and `layer.activate` receipts include affected windows,
  computed or intended frames, pending launches, and failures.
- docs no longer imply separate execution semantics per surface.
- CI has deterministic contract tests for placement, schema, and docs truth.

## Immediate Slice

Start with one vertical slice:

```text
actions.execute(window.place)
```

This forces the right abstractions without requiring the whole product to
move at once:

- target resolution
- placement parsing
- planning
- execution
- verification
- receipt
- history
- compatibility wrapper
- one or two migrated surfaces

Once this feels solid, migrate `space.optimize` and `layer.activate`.

That is the smallest path that ties the product together nicely without
turning the proposal into a rewrite.
