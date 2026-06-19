# LAT-006: Runs and Capture in Lattices

## Status

Accepted direction; initial screenshot slice in progress.

## Summary

The Action/Mira experiment should stop being a separate product the user has to
remember. The useful runtime loop should become plain Lattices functionality:

```text
observe -> act -> capture -> trace -> artifact -> review
```

The user-facing concepts should be:

```text
Lattices = workspace control plane
Actions = executable workspace operations
Runs = executions with trace and artifacts
Capture = screenshots and recordings
Review = inspect output
Actors = optional on-screen presences
```

This retires Mira as a feature name or product brand. Actors, pets, and
on-screen presences remain useful Lattices primitives, but no specific actor
should become the identity of the capture/review system.

The desired user experience is one macOS app, one daemon surface, one
permission assistant, one command palette, and one place to find runs and
artifacts.

Internally, Lattices can still keep specialized helper processes. The important
distinction is that helpers are implementation details. The product the user
grants permissions to, launches, trusts, and remembers should be Lattices.

## Why This Belongs Here

Lattices and Action converged on the same operating model from opposite
directions:

- Lattices already knows about workspaces, projects, windows, Spaces, layers,
  overlays, command surfaces, and local daemon control.
- Action already knows about observing surfaces, resolving targets, running
  deterministic actions, recording what happened, and saving reviewable
  artifacts.

LAT-005 proposes the shared action loop:

```text
input -> canonical action -> plan -> execute -> verify -> receipt -> history
```

Action supplies the missing proof loop:

```text
run -> observe -> act -> capture -> trace -> artifact -> review
```

Together, they make one product: a local macOS workspace runtime that can both
control the desktop and prove what happened.

## Problem

Keeping Action/Mira as a separate product creates exactly the kind of operational
friction Lattices is supposed to remove:

- another repo to remember
- another app name in the user's head
- another daemon port
- another CLI
- another permission story
- another place where recordings, traces, and review artifacts live
- another set of product concepts that overlap with Lattices actions,
  overlays, diagnostics, and permissions

The permissions problem is especially important. Accessibility, Screen
Recording, Automation, and future capture-related capabilities are high-trust
macOS permissions. Asking the user to manage those separately for Lattices and
Action/Mira makes the system feel fragmented even when the architecture is
sound.

## Product Decision

Runs and capture should become a Lattices feature area, not a second app.

Recommended naming:

| Concept | Product Name |
| --- | --- |
| Individual execution | Run |
| Saved output | Artifact |
| Machine-readable event log | Trace |
| Human-facing result | Review |
| Visual desktop presence | Actor |

Examples of user-facing commands:

- `Record Current Window`
- `Capture Frontmost App`
- `Start Run`
- `Review Last Run`
- `Show Run Artifacts`
- `Rerun Scenario`

The user should not need to know whether a given operation used ScreenCaptureKit,
Accessibility, a browser adapter, a recording probe, or an embedded helper.
Those details belong in diagnostics and receipts.

## Goals

1. Make Lattices the single user-facing app for workspace control and
   capture/review flows.
2. Consolidate permission guidance into the existing Lattices Permissions
   Assistant.
3. Preserve Action's important native runtime lesson: AppKit-dependent work must
   run inside a real app lifecycle.
4. Add a first-class run/artifact model that extends LAT-005 receipts and
   history.
5. Route run/capture activity through the Lattices daemon instead of requiring users
   or agents to remember a second public control plane.
6. Keep actors as optional generic Lattices presences, not a required product identity.
7. Migrate the useful protocol/runtime ideas without importing every demo,
   composer, or release workflow at once.

## Non-Goals

- Do not ship two visible apps as the normal experience.
- Do not push ScreenCaptureKit recording into a headless-only lifecycle.
- Do not make Lattices a general cross-platform automation product.
- Do not absorb Action's composer/export stack before the run/capture/review loop
  is integrated.
- Do not remove the existing Action repo until Lattices can own the
  important runtime paths.
- Do not ask users to manage Action.app permissions as part of normal Lattices
  usage.

## Target User Experience

The desired experience is:

1. User launches Lattices.
2. Lattices shows one permission checklist.
3. User opens the palette and chooses `Record Current Window`.
4. Lattices starts a run.
5. Optional actors or overlays indicate recording or inspection state.
6. The run writes media, screenshots, trace events, and receipts into the
   Lattices run store.
7. User opens `Review Last Run` from the same app.
8. Agents can read the same run through daemon methods.

The user should not need to open a second project, remember the `action-dev`
CLI, or reason about `Action.app` unless they are intentionally working on the
old Action codebase.

## Permission Model

Permissions should be owned by Lattices wherever possible.

Lattices already has a real permission assistant for:

- Accessibility
- Screen Recording
- Automation
- Input Monitoring

The Permissions Assistant should extend its existing capability model with
capture/review-specific explanations instead of introducing a second prompt
path.

### TCC Identity

macOS privacy permissions are tied to process and bundle identity. That makes
the integration strategy important:

- Long-term recording should run through `Lattices.app` or a clearly bundled
  Lattices helper identity.
- The old `Action.app` should not be required for normal user-facing capture.
- If a helper needs separate TCC visibility, the Permissions Assistant must say
  exactly which binary appears in System Settings and why.
- Diagnostics should log bundle id, executable path, and permission state for
  the component that actually needs access.

### AppKit Lifecycle Boundary

Action's recording work found an important constraint: ScreenCaptureKit recording
is more reliable when the actual recording path runs inside a real AppKit app
lifecycle.

Preserve that constraint by moving the probe pattern, not by flattening it.

Recommended shape:

```text
Lattices.app
  normal mode
  --recording-probe mode

Lattices daemon
  accepts run/capture requests
  records plans, receipts, and artifacts
  launches probe mode for recording work when needed
```

This keeps the lifecycle lesson without requiring a separate visible
`Action.app`.

## Architecture

### Current Shape

```text
Lattices.app
  daemon: ws://127.0.0.1:9399
  permissions assistant
  window/session/layer/overlay control

Action.app
  agent: ws://127.0.0.1:4319
  capture, recording probe, review loop
  runtime/session/protocol packages
```

### Target Shape

```text
Lattices.app
  daemon: ws://127.0.0.1:9399
  action runtime
  permission assistant
  run/capture/review UI
  recording probe mode
  overlay actor renderer

Optional internal helpers
  capture helper
  browser adapter
  scenario/compiler tools
```

The public API surface should be Lattices. Internal helpers can exist, but they
should not become another product for the user to operate.

## Data Model

Add a run model that complements LAT-005 receipts.

### `RunSession`

```json
{
  "id": "run_123",
  "title": "Record current window",
  "source": "palette",
  "workspace": {
    "projectPath": "/Users/art/dev/lattices",
    "session": "lattices-abc123"
  },
  "state": "running",
  "startedAt": "2026-05-30T12:00:00Z",
  "completedAt": null,
  "surfaces": [
    {
      "kind": "window",
      "wid": 12345,
      "app": "Lattices"
    }
  ],
  "artifacts": [],
  "receipts": []
}
```

### `RunArtifact`

```json
{
  "id": "art_123",
  "runId": "run_123",
  "kind": "recording",
  "path": "~/Library/Application Support/Lattices/Runs/run_123/window.mov",
  "mimeType": "video/quicktime",
  "createdAt": "2026-05-30T12:01:00Z",
  "metadata": {
    "width": 1440,
    "height": 900,
    "durationMs": 12000
  }
}
```

### `TraceEvent`

```json
{
  "id": "trace_123",
  "runId": "run_123",
  "time": "2026-05-30T12:00:03Z",
  "kind": "capture.started",
  "summary": "Started recording current window",
  "data": {
    "wid": 12345,
    "probe": "Lattices.app --recording-probe"
  }
}
```

Run receipts should reference LAT-005 execution receipts when actions mutate
workspace state. For example, a run may include a `window.place` receipt before
recording begins.

## Daemon API

Keep `ws://127.0.0.1:9399` as the user and agent-facing API.

Initial additions:

| Method | Purpose |
| --- | --- |
| `runs.create` | Create a run record and artifact directory |
| `runs.start` | Start a run from a scenario or direct capture request |
| `runs.stop` | Stop a running capture or scenario |
| `runs.list` | List recent runs |
| `runs.get` | Inspect one run, including receipts and artifacts |
| `runs.artifacts` | List artifacts for a run |
| `capture.screenshotWindow` | Capture a window as a run artifact |
| `capture.screenshotRegion` | Capture a region as a run artifact |
| `capture.recordWindow` | Record a window through probe mode |
| `capture.recordRegion` | Record a region through probe mode |

Development-only bridge methods may exist while migrating:

| Method | Purpose |
| --- | --- |
| `action.bridge.status` | Check whether the old Action agent is running |
| `action.bridge.call` | Proxy a small allowlist of old agent methods |

Those bridge methods should be treated as scaffolding, not the destination.

## UI Integration

### Home

Add a compact run status area only when relevant:

- last run
- active recording
- missing permissions
- recent artifact

This should not become a marketing panel. It is operational state.

### Palette

Add commands over the same run API:

- `Record Current Window`
- `Screenshot Current Window`
- `Review Last Run`
- `Stop Run`
- `Open Run Artifacts`

### Permissions Assistant

Add a capture capability section that explains why capture/review uses:

- Screen Recording for screenshots and recordings
- Accessibility for target resolution and window interaction
- Automation for app-specific control paths
- Input Monitoring only when a feature truly requires it

The assistant should report which exact component is missing permission.

### Actors

Keep actors available as normal Lattices overlay actors.

Run/capture states can map onto LAT-004 actor states when a visible presence is
useful:

| Run State | Overlay State |
| --- | --- |
| idle | `idle` |
| observing | `active` |
| resolving | `thinking` |
| recording | `active` |
| waiting for permission | `warning` |
| failed | `failed` |
| completed | `success` |
| reviewing | `review` |

The actor should be optional and dismissible. The run/capture contract must not
depend on a decorative surface being visible.

## Code Migration

Move concepts before moving everything.

### Bring Into Lattices Early

- generic actor metadata and assets
- run/session lifecycle concepts
- artifact and trace event types
- capture request/response contracts
- screenshot capture path
- recording probe pattern
- review UI ideas

### Bring Later

- scenario compiler
- browser companion
- composer packages
- demo rendering scripts
- release site assets
- MCP adapter

### Rework Instead Of Copying Directly

- `Action.app` shell becomes Lattices run/capture mode
- old Action agent protocol becomes internal migration scaffolding
- old CLI commands become Lattices palette, CLI, or daemon commands
- old docs become migration references, not another documentation tree

## File Ownership

Suggested Lattices locations:

```text
apps/mac/Sources/Core/Runs/
  RunStore.swift
  RunModels.swift

apps/mac/Sources/Core/Capture/
  CaptureController.swift
  RecordingProbe.swift

apps/mac/Sources/Core/Overlays/Actors/
  actor metadata and bundled assets

docs/proposals/
  LAT-006-runs-and-capture-in-lattices.md

docs/runs.md
  user-facing capture/review docs once implemented
```

If TypeScript protocol packages remain useful, add them under a Lattices-owned
package namespace rather than keeping `action` as the product name.

## Migration Plan

### Phase 1: Product Decision And Bridge

- Add this proposal.
- Cross-link LAT-005 and LAT-006.
- Define `RunSession`, `RunArtifact`, and `TraceEvent`.
- Add a dev-only bridge to the old Action agent if useful for experiments.
- Do not present the bridge as the final user experience.

### Phase 2: One-Permission Screenshot Slice

Implement the first real capture feature entirely inside Lattices:

```text
Screenshot Current Window -> RunSession -> Artifact -> Review
```

This proves the most important integration point: the user grants Lattices
permission and receives a run artifact without opening Action.app.

### Phase 3: Recording Probe In Lattices

- Port the recording probe pattern.
- Launch `Lattices.app --recording-probe` for actual recording work.
- Preserve stop-file, finished-file, and debug-log behavior.
- Store outputs in the Lattices run directory.

### Phase 4: Review UI

- Add a lightweight run library.
- Show screenshots, recordings, trace events, and action receipts.
- Link each artifact back to the workspace/window/session context.

### Phase 5: Surface Adapters

- Bring over AX/browser/native surface adapter concepts.
- Let `actions.plan` and `runs.start` share target resolution confidence.
- Keep coordinate fallback visible in receipts.

### Phase 6: Scenarios And Composer

- Bring scenario compilation only after manual capture and review feel solid.
- Keep composition/export optional and downstream from the run store.

## Immediate Slice

The smallest meaningful integration is:

```text
Record a screenshot of the current window as a run inside Lattices.
```

Required pieces:

- `RunSession` model
- artifact directory under Lattices application support
- `capture.screenshotWindow`
- palette command
- permission receipt
- recent-run review surface
- optional actor state change

This avoids the two-app permission problem from the start and gives the product
a concrete user-facing capture feature before the heavier recording probe is
ported.

## Open Questions

### Should Actors Stay?

Recommendation: yes, as generic presences. Retire Mira as the product name, but
keep actors/pets available for agent, run, app, and task presence.

### Should The Old Action Agent Port Stay?

Recommendation: temporarily. It can accelerate migration, but the stable public
surface should be the Lattices daemon on `9399`.

### Should Lattices Ship A Separate Helper App?

Recommendation: avoid this unless needed. Prefer `Lattices.app` probe mode so
the user's permission story stays simple.

### Where Should Runs Live?

Recommendation:

```text
~/Library/Application Support/Lattices/Runs/
```

This keeps artifacts out of project repos unless the user explicitly exports
them.

### Should Recording Be First?

Recommendation: no. Start with screenshots and run artifacts. Then port
recording once the run store and review loop exist.

## Success Criteria

This proposal is successful when:

- the user sees runs and capture as part of Lattices, not as another app to remember
- the normal capture path asks for Lattices permissions, not Action.app
- a palette command can create a run artifact from the current window
- run artifacts are reviewable inside Lattices
- action receipts and run traces can reference each other
- actors can reflect run state without owning the run contract
- recording uses a real AppKit lifecycle without requiring a separate visible
  product
- the old Action repo can eventually become a migration source, not an active
  parallel product
