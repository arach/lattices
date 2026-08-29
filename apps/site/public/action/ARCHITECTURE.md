# Architecture

`action` is a ground-up rewrite for agentic macOS demo automation.

It exists because `vif` and `stage` both produced valuable learnings, but neither is the right long-term core:

- `vif` proved there is real value in combining capture, browser/app automation, overlays, audio, and export.
- `stage` proved the architecture should be cleaner, more session-oriented, and more explicit about primitives.
- Both also showed a failure mode: if the scene format, CLI behavior, and runtime lifecycle get tangled together, the tool becomes hard to reason about and easy to break.

The central architectural decision for `action` is:

**The runtime is the product. The scene format is a compiled input, not the architecture.**

Another useful way to say the same thing:

**`action` is an action runtime that can observe, act, reflect, and record.**

## Goals

- Provide a deterministic, session-based runtime for observing apps and browsers, resolving targets, executing actions, reflecting on what happened, and recording structured traces.
- Support agent-authored demo and promo workflows without relying on hidden heuristics or magical state.
- Separate live automation from final composition so polished output can improve without destabilizing the runtime.
- Lean fully into macOS-native fidelity instead of designing for fake cross-platform flexibility.

## Non-Goals

- Not a generic automation framework for every operating system
- Not an Electron-first runtime
- Not a GUI editor in v0
- Not a vision-only “click whatever looks right” system
- Not a scene DSL that owns business logic and runtime state
- Not a VM/container-first automation stack for host UI, browser, or capture
  work

## Core Layers

`action` should be implemented as a small number of strict layers.

### 1. Native Engine

Swift-based macOS engine responsible for:

- ScreenCaptureKit capture
- Accessibility inspection
- Input synthesis
- Window enumeration and positioning
- Overlay windows when needed during live capture
- Audio session and telemetry primitives

The engine should be treated as a capability provider, not the place where product workflows live.

The native layer should be split into separate processes:

- `Action.app`: normal AppKit lifecycle, WebKit, menus, settings, permissions UX
- `ActionAgent`: headless local service exposing WebSocket and local IPC surfaces
- `ActionCLI`: thin operational client that talks to the agent, not directly to UI

This separation is not optional. UI lifecycle and agent lifecycle have different
constraints, and combining them leads to brittle behavior.

### Remote Workers

Remote VMs and containers can still be useful for auxiliary work such as
isolated command execution, rendering, browser-free tests, or heavyweight model
jobs. They should not own the core Action browser, Accessibility, AppKit, or
ScreenCaptureKit paths because those capabilities depend on the user's macOS
host, permissions, windows, and dedicated local Chrome profiles.

### 2. Runtime

The runtime is the heart of the system. It owns:

- session creation and teardown
- lifecycle transitions
- current surfaces and active targets
- observations and resolution logic
- action execution
- reflection and inspection workflows
- traces and artifacts

All mutable run state belongs to a concrete session. Avoid hidden globals and avoid lifecycle behavior that relies on shell cleanup or broad process-kill patterns.

### 3. Compiler

The compiler converts author intent into an executable timeline.

It should:

- validate scene/input structure
- normalize high-level user intent into explicit runtime actions
- attach fallbacks and preconditions
- separate narrative cues from execution steps
- produce an inspectable timeline before execution

The compiler should eventually support more than one input source:

- hand-authored scenario intent
- recorded runtime traces converted into scenario drafts

This matters because one of the most valuable workflows is likely to be:

1. a user demonstrates a flow manually
2. the runtime captures media plus trace
3. `action` derives a reusable scenario from that run
4. the system reruns or polishes it later

### 4. Composer

Composition is a separate phase from capture and execution.

The composer should:

- transform raw captures and runtime traces into a render manifest
- infer or apply zooms, cursor polish, subtitles, callouts, chapter cards, and audio timing
- delegate actual rendering to a backend such as Remotion

This separation is essential. Styling, transitions, and branding should be able to evolve independently from action execution.

The composer should not own live app control, session lifecycle, or target
resolution. It is post-capture orchestration, not the runtime.

### 5. Frontends

Frontends must stay thin.

- CLI: operational control and local authoring workflows
- MCP: agent-facing execution surface
- TS HUD: richer operator console for logs, diagnostics, artifacts, scenario control, and reflection output
- native HUD: minimal always-on capture companion tied closely to runtime truth and immediate controls

They should call the same runtime interfaces, not implement separate behavior.

The HUD split should be deliberate:

- the native HUD should stay minimal and capture-adjacent
- the TS HUD can carry more product richness and operator affordances
- neither HUD should become the owner of runtime truth
- if a HUD is on screen during a live session, it should expose explicit controls instead of acting like passive decoration

## Core Primitives

`action` should keep its vocabulary small and stable.

### Session

One automation run with:

- stable id
- explicit lifecycle
- owned resources
- trace output
- artifact list

Suggested lifecycle:

- `created`
- `preflight`
- `ready`
- `running`
- `paused`
- `completing`
- `completed`
- `failed`
- `cancelled`

### Surface

A place where the runtime can observe or act.

Examples:

- desktop
- app window
- browser tab
- bounded region

### Observation

A typed fact gathered from the engine or browser adapter.

Examples:

- window bounds
- DOM node snapshot
- AX element
- cursor position
- recording state
- audio level

### Reflection

A structured interpretation of current state or recent action.

Examples:

- UI critique from a model provider
- QA finding attached to a screenshot
- target suggestion derived from vision plus AX context
- operator-facing summary of what changed after an action

Reflection is not the same thing as raw observation.

- observations are facts gathered from the system
- reflections are interpretations produced from those facts

The runtime should own reflection sessions, prompts, findings, and artifacts, but
provider-specific model clients should stay outside the native engine. See
[LIVE_INSPECTION_RUNTIME.md](docs/LIVE_INSPECTION_RUNTIME.md).

### Target

A stable reference to something actionable.

Target resolution should support:

- semantic ids
- AX/DOM-based resolution
- bounded text/role matching
- calibrated anchors
- coordinates as last resort

### Action

A deterministic atomic operation.

Examples:

- click
- type
- press key
- focus window
- open app
- start recording
- stop recording
- show cue
- wait for condition

### Cue

A narrative or editorial element that matters to the viewer.

Examples:

- label
- chapter marker
- subtitle
- callout
- caption

### Effect

A render-time presentation element, not necessarily a live overlay.

Examples:

- auto zoom
- smart reframe
- cursor emphasis
- background dimming
- click pulse
- transition

### Artifact

Anything the run produces.

Examples:

- screenshot
- raw capture
- trace log
- focus metadata
- subtitle file
- final rendered video

## Target Resolution

Target picking is a v0 feature, not a nice-to-have.

The system must not normalize blind coordinate clicking as the default interaction model.

Recommended resolution order:

1. semantic target
2. exact accessibility or DOM match
3. bounded fuzzy text/role match
4. calibrated anchor
5. coordinate fallback

Recommended API shape:

- `observe()`
- `target.resolve(query, context)`
- `act(action, target)`

And the resolver must be conservative:

- return confidence
- return ambiguity explicitly
- avoid guessing when multiple candidates are plausible
- allow human or agent inspection before acting

## Execution Model

There are two major phases.

### Live Phase

The runtime:

- prepares the environment
- resolves targets
- executes actions
- captures raw media
- records metadata and trace events

### Compose Phase

The composer:

- consumes raw media and trace data
- computes polish such as zooms and cursor motion
- aligns narration, subtitles, music, and chapter cues
- renders exports via a backend

This split is a hard requirement. It keeps the runtime reliable and the output quality flexible.

## Scene Model

Scenes should describe intent, not be forced to contain all operational detail.

Good scenes should express:

- goal
- context
- surfaces
- targets
- sequence
- narration
- style
- export preferences

The compiler should lower those into an executable timeline with explicit dependencies and fallbacks.

## Render Backend Boundary

`action` should define its own render manifest and allow multiple composition backends.

Near-term plan:

- `composer-core`: manifest schema and transformation logic
- `composer-remotion`: first production backend

This allows `action` to borrow high-quality composition capabilities from tools like Remotion without turning React video rendering into the core product architecture.

## Operational Design Rules

- No daemon mystery states
- No hidden global runtime state
- No broad shell cleanup as the main lifecycle mechanism
- No UI-only source of truth
- No premature cross-platform abstraction
- No scene format that bypasses runtime primitives

## Proposed Package Boundaries

- `packages/protocol`
- `packages/runtime`
- `packages/compiler`
- `packages/composer-core`
- `packages/composer-remotion`
- `packages/cli`
- `packages/mcp`
- `native/engine`

## v0 Definition of Done

`action` v0 should feel solid before it feels broad.

That means:

- explicit session lifecycle
- reliable target resolution
- deterministic action execution
- raw capture plus trace metadata
- polished but backend-driven composition
- clean CLI and MCP surfaces

If v0 cannot reliably observe, resolve, act, record, and compose a basic feature demo on macOS, it is not done.
