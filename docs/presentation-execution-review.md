# Presentation And Execution Review

This note reviews the current Lattices presentation layer, the tiling and intent-to-outcome pipeline behind it, and a direction for tightening execution logic. It also pulls in relevant ideas from Hyprland and Wayland, using primary sources only.

## Why this document exists

Lattices already has strong operator-facing surfaces:

- HUD and keyboard-driven interaction
- local voice mode
- hands-off voice mode
- command palette
- desktop inventory and search

What is still under-shaped is the execution core behind those surfaces. Today the UX is ahead of the action model.

The root issue is not "tiling quality" in isolation. The deeper issue is that Lattices has multiple control surfaces, multiple intent grammars, and multiple direct execution paths that do not converge on a single canonical planner/executor.

## Review scope

This review is based on:

- `app/Sources/WindowTiler.swift`
- `app/Sources/WorkspaceManager.swift`
- `app/Sources/IntentEngine.swift`
- `app/Sources/VoiceIntentResolver.swift`
- `app/Sources/LatticesApi.swift`
- `app/Sources/PaletteCommand.swift`
- `app/Sources/HUDController.swift`
- `app/Sources/DesktopModel.swift`
- `app/Sources/HandsOffSession.swift`
- `docs/voice-command-protocol.md`

## Current Architecture

### 1. Presentation surfaces are rich, but execution is fragmented

Lattices currently has at least five operator surfaces:

| Surface | Main files | How it resolves intent | How it executes |
|---|---|---|---|
| Command palette | `PaletteCommand.swift`, `CommandPaletteView.swift` | No semantic resolution | Calls `SessionManager`, `WindowTiler`, `WorkspaceManager` directly |
| HUD | `HUDController.swift` | Hardcoded key routing | Calls `WindowTiler` and `HandsOffSession` directly |
| Local voice | `VoiceCommandWindow.swift`, `VoiceIntentResolver.swift`, `IntentEngine.swift` | NL embedding + heuristics + slot extraction | Mix of `LatticesApi` dispatch and direct `WindowTiler` calls |
| Hands-off voice | `HandsOffSession.swift` | External worker returns action list | Replays actions through `PhraseMatcher` / `IntentEngine` |
| Daemon / API | `LatticesApi.swift`, `DaemonServer.swift` | Structured request only | Calls subsystems directly |

The result is a split brain:

- presentation is centralized in the app
- execution is not centralized in one action engine

### 2. Tiling itself is reasonably capable

`WindowTiler.swift` already has solid building blocks:

- named positions from halves up through sixths and eighths
- generic `grid:CxR:C,R` support
- frame derivation against `visibleFrame`
- fast path via `DesktopModel`
- AX fallback
- AppleScript fallback
- batch moves and raises
- space discovery and limited space movement

That is a good substrate. The problem is not the absence of tiling primitives. The problem is that these primitives are reached through different decision systems.

### 3. Layer tiling is the closest thing to an orchestrator

`WorkspaceManager.tileLayer(...)` is the most complete execution pipeline in the app today. It already does:

1. inventory refresh
2. classification of running vs missing windows
3. batched moves for known windows
4. fallbacks for untracked windows
5. launch queue for missing projects/apps
6. delayed post-launch tiling

This is useful, but it is still a per-feature orchestrator, not the shared execution model for the whole product.

### 4. Intent conversion currently exists in multiple incompatible forms

There are several distinct ways to convert a user goal into motion:

- HUD key map in `HUDController`
- local voice extraction in `VoiceIntentResolver`
- intent handlers in `IntentEngine`
- direct daemon calls in `LatticesApi`
- hands-off worker action generation in `HandsOffSession`

These systems overlap, but they are not the same system.

## Root-Cause Findings

### 1. There is no canonical action schema

The core missing layer is a first-class action model. Right now Lattices mostly jumps from:

- UI event -> subsystem method

instead of:

- UI event -> canonical action -> planner -> validated execution -> result

That is why each surface grows its own grammar and shortcuts.

### 2. Intent resolution and execution are coupled too early

`IntentEngine` mixes:

- slot validation
- target resolution
- direct side effects

That makes it harder to:

- preview what will happen
- batch actions coherently
- deduplicate targets
- rollback or retry
- explain why a request failed before side effects begin

### 3. Presentation layers still own execution semantics

Examples:

- command palette actions directly call `WindowTiler` / `SessionManager`
- HUD tile mode computes its own ad hoc grid and applies it immediately
- local voice can go through `LatticesApi` or bypass it
- hands-off voice replays actions one by one rather than committing a single execution plan

This means the product does not yet have one source of truth for "what operation means" or "what order side effects should occur in."

### 4. The system is not transactional

Wayland's most useful idea here is not Linux-specific rendering. It is commit discipline.

Lattices currently performs many operations incrementally:

- poll desktop
- start moving known windows
- navigate to missing windows
- launch apps
- tile launched apps later

That produces useful behavior, but not an explicit transaction model. The user intent is "arrange my workspace", but implementation today is "execute a staggered set of best-effort side effects."

### 5. Window identity is still mostly heuristic

The current system relies on:

- `[lattices:session-name]` title tags for terminal windows
- `app + title substring` matching for non-terminal windows
- a `DesktopModel` cache plus CG/AX fallbacks

This is workable, but it is not yet elevated into a durable target-resolution layer with confidence, ambiguity handling, or plan-time diagnostics.

### 6. The product has multiple position grammars

At minimum there are separate position systems in:

- `TilePosition`
- `parseGridString(...)`
- `VoiceIntentResolver.resolvePosition(...)`
- HUD key routing
- hands-off worker output
- daemon `window.tile`

The existence of `TilePosition` suggests there should be one canonical placement language. In practice there are several.

## What Hyprland Gets Right

### 1. One mutation surface: dispatchers

Hyprland exposes a consistent mutation model: `hyprctl dispatch ...` calls compositor dispatchers rather than inventing a new command path for each UI. That is the right mental model for Lattices too.

For Lattices, the equivalent should be:

- one canonical action registry
- many presentation surfaces
- one executor

### 2. Separate control from live observation

Hyprland separates:

- control/info requests via `hyprctl` / request socket
- live events via `socket2`

That split is useful for Lattices. The app already has an `EventBus`, but execution still often assumes fresh polling instead of treating live state and mutations as distinct first-class channels.

### 3. Rules are first-class, not hidden glue

Hyprland's window rules are useful not because Lattices should copy them literally, but because they formalize policy:

- what should open where
- when rules are evaluated
- which rules are static vs dynamic

Lattices currently has pieces of this spread across:

- layer project specs
- companion `windows` entries
- session naming
- title matching
- ad hoc fallback behavior

These want to become an explicit rule engine.

### 4. Layout engines are explicit and addressable

Hyprland treats layout strategy as a named concept:

- `master`
- `dwindle`
- per-layout config
- layout-specific dispatchers / layout messages

Lattices currently has positions, grids, layer tiling, and distribute logic, but not named layout engines with their own semantics. That is why many arrangements still feel like clever commands rather than stable workspace behaviors.

## What Wayland Gets Right

### 1. Clear object roles

Wayland's `wl_surface` becomes meaningful through roles such as toplevel and popup. That separation matters.

Lattices needs the same distinction between:

- raw windows
- lattices session windows
- companion app windows
- HUD utility windows
- layout targets
- execution results

Right now these concepts are present, but not formalized strongly enough in the execution model.

### 2. Requests and events are different things

Wayland's protocol model is built around objects with requests and events. Lattices should mirror that more explicitly:

- requests mutate state
- events report state changes
- snapshots are derived, not the mutation API

Today those concerns blur together in some places.

### 3. Pending state vs applied state

This is the biggest transferable idea.

Wayland's surface lifecycle makes state changes pending until commit. Lattices should adopt the same pattern for workspace arrangement:

- resolve targets
- compute plan
- validate plan
- commit plan
- publish result

Without this, "organize my windows" will always be less predictable than it should be.

### 4. Configure / acknowledge / commit

Wayland's configure-and-ack flow is a good model for coordination between planner and executor:

- planner proposes a layout/result
- executor acknowledges what can be applied
- final commit produces the visible outcome

For Lattices, this suggests explicit execution receipts, not just side effects plus logging.

## Proposed Direction For Lattices

### 1. Introduce a canonical action model

Every surface should emit the same internal action envelope:

```json
{
  "intent": "window.tile",
  "targets": [{ "kind": "wid", "value": 1234 }],
  "args": { "position": "left" },
  "source": "voice-local"
}
```

Not all actions need to originate from voice. The important part is that command palette, HUD, daemon, and worker output all normalize into the same model.

### 2. Split the pipeline into four layers

### A. Interpretation

Converts user input into canonical actions.

Examples:

- keyboard chord -> action
- transcript -> action
- daemon JSON -> action

### B. Planning

Resolves targets and composes a layout plan.

Examples:

- which exact window does "Chrome" mean
- which screen should `left-third` land on
- whether a missing project should be launched
- whether multiple actions should be merged into one transaction

### C. Execution

Applies the plan through one executor.

Examples:

- batch move these windows
- focus this session
- launch these apps
- wait for these windows to appear
- commit final arrangement

### D. Presentation

Shows:

- preview
- progress
- result
- failure

The key point is that presentation should no longer define semantics.

### 3. Create a real arrangement transaction

Lattices should have a type along these lines:

- `ArrangementIntent`
- `ArrangementPlan`
- `ArrangementTransaction`
- `ArrangementResult`

An arrangement transaction should carry:

- requested actions
- resolved targets
- preconditions
- fallback strategy
- steps
- partial failures
- final applied state

That gives the app a place for:

- preview before commit
- retries
- rollback where possible
- voice confirmation
- better diagnostics than raw log lines

### 4. Unify the placement grammar

There should be exactly one placement language.

That language should cover:

- named positions
- grid cells
- screen/display selection
- optional grouping semantics
- optional relative semantics like "stack" or "master"

Everything else should compile into it, including:

- HUD keys
- voice phrases
- daemon requests
- future scripting

`VoiceIntentResolver` should not own a separate smaller placement universe.

### 5. Promote rules to a first-class subsystem

Lattices should formalize:

- static rules: applied on launch or first attach
- dynamic rules: re-evaluated when window properties or workspace state changes

Examples:

- project session window belongs on display 2 left half
- browser matching title X belongs beside project Y
- voice/HUD utility panels are never layout targets
- session windows for a layer open silently until plan commit

This is the clearest Hyprland-inspired gap in the current design.

### 6. Treat layout strategy as a pluggable engine

Instead of "tile to coordinates" being the only real abstraction, Lattices should support named layout engines, for example:

- `stack`
- `master`
- `grid`
- `bsp`
- `focus-ring`
- `review`

Each layout engine can expose:

- configuration
- planning logic
- compact mutation messages

That is the Hyprland lesson from `master`, `dwindle`, and `layoutmsg`: layout should be semantic, not just positional.

### 7. Make the daemon the canonical external executor boundary

The daemon already has enough shape to become the stable mutation boundary, but it should move from "RPC bag of commands" toward:

- state snapshot endpoints
- event stream
- action submission
- transaction status / receipts

The app can still call internals directly, but conceptually it should use the same execution core the daemon exposes.

## What This Means For Existing Features

### HUD

The HUD should remain fast and tactile, but its keys should emit canonical actions or layout messages, not direct tiler calls with private semantics.

### Local voice

Local voice should only do:

- transcript normalization
- action extraction

It should not decide execution policy inline.

### Hands-off voice

The worker should emit canonical actions only. Swift should not need to reinterpret those actions through a second matcher.

### Command palette

Palette commands should become thin wrappers over canonical actions, which makes them previewable and scriptable for free.

### Layers

`WorkspaceManager.tileLayer(...)` should evolve into a planner/executor user, not remain a special-case orchestration island.

## Concrete Recommendation

If I had to reduce this to one architectural move, it would be:

**Build a single action planner/executor and force every surface to go through it.**

That one move solves the deepest problems:

- duplicate intent logic
- duplicate position grammars
- direct UI-owned side effects
- lack of previews and execution receipts
- hard-to-reason-about batch behavior

## Suggested Implementation Order

1. Define canonical action and target schemas.
2. Extract a placement grammar module shared by voice, HUD, daemon, and layer logic.
3. Introduce `ArrangementPlan` plus an executor that can batch, defer, and report.
4. Migrate `window.tile`, `layout.distribute`, and layer switching onto that executor first.
5. Make local voice and hands-off worker emit canonical actions only.
6. Add preview/result receipts to HUD and voice surfaces.
7. Add first-class rules and named layout engines after the core path is stable.

## Primary References

- [Hyprland: Using hyprctl](https://wiki.hypr.land/Configuring/Using-hyprctl/)
- [Hyprland: IPC](https://wiki.hypr.land/0.54.0/IPC/)
- [Hyprland: Window Rules](https://wiki.hypr.land/0.51.0/Configuring/Window-Rules/)
- [Hyprland: Dwindle Layout](https://wiki.hypr.land/Configuring/Dwindle-Layout/)
- [Hyprland: Master Layout](https://wiki.hypr.land/Configuring/Master-Layout/)
- [Wayland project overview](https://wayland.freedesktop.org/index.html)
- [Wayland Book: Interfaces, requests, and events](https://wayland-book.com/protocol-design/interfaces-reqs-events.html)
- [Wayland Book: Surface lifecycle](https://wayland-book.com/surfaces-in-depth/lifecycle.html)
- [Wayland Book: XDG shell basics](https://wayland-book.com/xdg-shell-basics.html)
- [Wayland Book: Configuration & lifecycle](https://wayland-book.com/xdg-shell-in-depth/configuration.html)
