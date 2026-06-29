# LAT-008: pi-lattices and Safe Computer Use Expansion

Status: Draft
Date: 2026-06-28
Audience: Lattices implementers, Pi package implementers, agent integrations

## Summary

Build `pi-lattices`: a Pi package/extension that exposes Lattices' daemon as
first-class Pi tools, then expand Lattices' native computer-use surface with the
best primitives observed in `@amaster.ai/pi-computer-use` / `cua-driver` while
preserving Lattices' product strengths: macOS-native control, typed daemon
methods, treatments, run receipts, artifacts, and traceability.

The target is not to wrap `cua-driver` inside Lattices. The target is to bring
its most useful low-level affordances into Lattices' safer action/runtime model.

## Context

Installed comparison baseline:

- Pi package: `@amaster.ai/pi-computer-use`
- Underlying driver: bundled `cua-driver`
- Current Lattices project: `/Users/art/dev/lattices`

Observed `pi-computer-use` strengths:

- Full per-window AX state snapshots with actionable element indices.
- Direct low-level inputs: click, double-click, right-click, type text, press key,
  hotkey, scroll, drag, set value.
- Window-local screenshot pixel coordinate model.
- Optional screenshot analysis by a vision model.
- Graceful tool registration/degradation in Pi.

Current Lattices strengths:

- Rich workspace orchestration: projects, sessions, windows, layers, spaces,
  process and terminal awareness.
- Local daemon API on `ws://127.0.0.1:9399` with `api.schema`.
- Run store under `~/Library/Application Support/Lattices/Runs/` with artifacts
  and trace events.
- Computer-use `treatment` semantics: `observe`, `stage`, `present`, `execute`.
- Existing safe endpoints: `computer.prepare`, `computer.focusWindow`,
  `computer.showCursor`, `computer.magicCursor`, `computer.launchApp`,
  `computer.typeWindowText`, `computer.click`, `computer.typeText`, plus
  screenshot/recording endpoints.

## Validation against current repo

The Phase 1 package can be implemented as a wrapper around existing daemon
methods; no Swift daemon endpoints are required for the MVP.

Confirmed in `docs/api.md` and
`apps/mac/Sources/Core/Daemon/LatticesApi.swift`:

- `api.schema`, `daemon.status`, `windows.list`, `windows.get`,
  `windows.search`, `runs.list`, `runs.get`, `ocr.snapshot`, and `ocr.search`
  are registered read endpoints.
- `window.place` is the canonical receipt-returning placement mutation;
  `window.tile` remains a compatibility wrapper.
- `capture.screenshotWindow` writes run artifacts.
- `computer.prepare`, `computer.focusWindow`, `computer.launchApp`,
  `computer.typeWindowText`, `computer.click`, and `computer.typeText` already
  use the Lattices run/treatment model.
- `computer.click` now exists and defaults to `stage`, so the older
  `LAT-006-followup-gaps` click gap is stale.
- `windows.search` is the typed window search endpoint for the MVP. The richer
  `lattices.search` endpoint also exists and remains reachable through the
  `lattices_call` escape hatch.
- `computer.windowState` is now present as the first Phase 2 window-state
  endpoint.
- `computer.elementAction` is present for snapshot element-id press/showMenu/focus
  actions.
- `computer.typeElement` and `computer.setValue` are present for snapshot
  element-id AXValue insertion.

MVP wrapper decision: `lattices_window_focus` maps to
`computer.focusWindow`, not raw `window.focus`, so focus/present calls can stay
run-/trace-aware and accept `treatment`.

Phase 1 implementation lives in `packages/pi-lattices/` with package docs in
`docs/pi-lattices.md`.

## Product principles

1. **Keep Lattices macOS-native.** Do not widen scope to cross-platform bundled
   drivers.
2. **Prefer read/plan before act.** New tools should fit `observe`/`stage` before
   `execute`.
3. **Keep actions receipt-backed.** Every mutation should be traceable through a
   run or action receipt where practical.
4. **Prefer semantic targets over coordinates.** Coordinates remain necessary,
   but AX element IDs and target resolution should be the happy path.
5. **Avoid destructive primitives by default.** No raw force-kill app tool unless
   it is strongly scoped and confirmation-gated.
6. **Make readiness machine-readable.** Agents should be able to discover missing
   Accessibility, Screen Recording, or app-specific capabilities before acting.

## Phase 1: `pi-lattices` MVP over existing daemon

Create a Pi package, likely under a package path such as
`packages/pi-lattices/` or a publishable package folder selected by the
maintainer. It should be installable by Pi as an npm/git/local package.

### Package goals

- Register Pi tools that call the Lattices daemon via the existing websocket
  protocol / `daemonCall` helper.
- Fail gracefully when the daemon is down with actionable guidance:
  `Start Lattices with: lattices app`.
- Preserve Lattices method names and safety semantics rather than inventing a
  parallel action model.
- Include a generic escape hatch, but expose high-value typed tools first.

### Initial Pi tools

Use a consistent prefix such as `lattices_`.

Read/discovery:

- `lattices_status` → `daemon.status`
- `lattices_api_schema` → `api.schema`
- `lattices_windows_list` → `windows.list`
- `lattices_windows_search` → `windows.search` / `lattices.search` as appropriate
- `lattices_window_get` → `windows.get`
- `lattices_runs_list` → `runs.list`
- `lattices_runs_get` → `runs.get`
- `lattices_ocr_snapshot` → `ocr.snapshot`
- `lattices_ocr_search` → `ocr.search`

Mutations / computer use:

- `lattices_window_focus` → `window.focus` or `computer.focusWindow`
- `lattices_window_place` → `window.place`
- `lattices_capture_window` → `capture.screenshotWindow`
- `lattices_computer_launch_app` → `computer.launchApp`
- `lattices_computer_click` → `computer.click`
- `lattices_computer_type_window_text` → `computer.typeWindowText`
- `lattices_computer_type_text` → `computer.typeText`

Escape hatch:

- `lattices_call` with `method`, `params`, optional `timeoutMs`.

### MVP acceptance criteria

- Package loads in Pi and registers tools on session start.
- `lattices_status` returns a daemon status when the app is running.
- When the daemon is not running, tools return a friendly non-crashing error.
- Tool schemas are strict enough for agent use and include short descriptions.
- At least one smoke test or documented manual check demonstrates a read call and
  a safe staged call.
- Documentation explains install via `pi install`, local dev usage, and daemon
  startup requirement.

## Phase 2: AX window state and element IDs

Add a Lattices-native endpoint to inspect a target window's AX tree and create
an actionable snapshot.

Candidate endpoint:

- `computer.windowState`

Candidate params:

```ts
{
  wid?: number
  app?: string
  title?: string
  pid?: number
  query?: string
  mode?: 'ax' | 'screenshot' | 'both' | 'ocr'
  capture?: boolean
  source?: string
}
```

Candidate return shape:

```ts
{
  ok: true,
  snapshotId: string,
  target: { wid, pid, app, title, frame },
  mode: 'ax' | 'screenshot' | 'both' | 'ocr',
  elements: [
    {
      id: 'e1',
      role: 'AXButton',
      title?: string,
      label?: string,
      value?: string,
      description?: string,
      frame?: { x, y, w, h },
      enabled?: boolean,
      selected?: boolean,
      focused?: boolean,
      actions?: string[],
      path?: string
    }
  ],
  treeMarkdown?: string,
  artifact?: RunArtifact,
  warnings?: string[]
}
```

Implementation notes:

- Element IDs only need to be stable within a snapshot at first.
- The server may maintain an in-memory snapshot cache scoped by window/run.
- Include enough path/role/title metadata to make logs debuggable after cache
  expiry.
- `mode: ax` should avoid Screen Recording when only Accessibility is needed.
- `mode: screenshot` should avoid AX when only visual inspection is needed.

### Element actions

Add semantic element-targeted mutations:

- `computer.elementAction`
- `computer.typeElement`
- `computer.setValue`

Candidate `computer.elementAction` params:

```ts
{
  snapshotId: string,
  elementId: string,
  action?: 'press' | 'showMenu' | 'open' | 'confirm' | 'cancel' | 'focus',
  treatment?: 'stage' | 'present' | 'execute',
  capture?: boolean,
  source?: string
}
```

Acceptance:

- Agents can inspect Calculator/Notes/Finder/Chrome window state and perform a
  button press by element ID without using coordinates.
- Stage mode records intent without mutating.
- Execute mode records before/after trace where practical.

## Phase 3: Rich input primitives

Add Lattices-native computer-use endpoints analogous to the useful `cua-driver`
primitives. Each endpoint must preserve Lattices' treatment/capture/run model.

Candidate endpoints:

- `computer.pressKey`
- `computer.hotkey`
- `computer.scroll`
- `computer.drag`
- `computer.doubleClick`
- `computer.rightClick` or improved `computer.click` with `count` and button

Design rules:

- Accept `wid|app|title` target resolution where practical.
- Prefer `elementId` or AX path when provided.
- Use coordinates only when semantic targets are unavailable.
- Default risky operations to `stage` unless caller explicitly passes
  `treatment: 'execute'`.
- Include `source` in traces.

Acceptance examples:

- Press Return in a selected text field without moving the pointer.
- Send Cmd+C/Cmd+V to a targeted app/window when safe.
- Scroll a target window or element.
- Drag a slider/handle using staged and execute modes.
- Double-click an openable item.

## Phase 4: Vision, zoom, and verification

Add APIs that let agents reason about screenshots and prove outcomes.

Candidate endpoints:

- `capture.screenshotRegion`
- `capture.zoomArtifact`
- `vision.analyzeWindow`
- `vision.analyzeArtifact`
- `computer.verify`

`vision.*` should be optional and explicit. It may use configured provider/model
settings, but should not imply always-on cloud vision.

Candidate `vision.analyzeWindow` params:

```ts
{
  wid?: number,
  app?: string,
  title?: string,
  instruction: string,
  runId?: string,
  source?: string
}
```

Candidate `computer.verify` modes:

- OCR contains/does-not-contain text.
- AX element value equals/contains expected value.
- Window/artifact changed or did not change.
- Vision prompt returns a structured judgment.

Acceptance:

- An agent can capture a window, ask a vision model a targeted question, and
  inspect the resulting run/artifact linkage.
- A type/click flow can include a post-action verification step using OCR or AX.

## Phase 5: Browser/page primitives

Consider browser-specific read and action endpoints once the core safe computer
use surface is in place.

Candidate endpoints:

- `browser.getText`
- `browser.queryDom`
- `browser.executeJavascript`

Guardrails:

- Browser mutation and enabling JavaScript automation require explicit user
  consent.
- Prefer read-only browser operations by default.
- Document supported browsers and required app settings.

## Phase 6: Package polish and docs

- Publish/package `pi-lattices` in a way Pi can install via npm/git/local path.
- Add docs to Lattices and package README.
- Add smoke test scripts and examples.
- Add `lattices mcp` only if it complements the Pi extension or shares the same
  implementation.

## Things not to copy

- Do not replace Lattices daemon/action runtime with `cua-driver`.
- Do not make raw coordinates the primary API.
- Do not add unscoped force-kill app tools.
- Do not silently enable browser automation settings.
- Do not bypass runs/artifacts/trace for mutating computer-use actions.

## Suggested implementation order

1. Build `pi-lattices` MVP around current daemon methods.
2. Add `computer.windowState` window-state endpoint. **Done.**
3. Add `computer.elementAction` and element-ID support in click/type/set value.
   **Done.**
4. Add keyboard/scroll/drag/double-click primitives.
5. Add vision/zoom/verify.
6. Add browser primitives.

## Validation commands

Run the narrowest checks for the touched area. Common commands from this repo:

```bash
bun run check:types
bun run check:app
bun run check
bun run test:cli
```

Manual checks will also be necessary for macOS Accessibility and Screen
Recording behaviors.

## Source references

- `docs/api.md` — current daemon and computer-use API.
- `apps/mac/Sources/Core/Daemon/LatticesApi.swift` — endpoint registry.
- `apps/mac/Sources/Core/Actions/ComputerUseController.swift` — existing
  computer-use implementation.
- `packages/npm/sdk/cua.mjs` and `packages/npm/sdk/cua.d.ts` — current SDK facade.
- `docs/proposals/LAT-005-action-runtime-product-spine.md` — action runtime
  product direction.
- `docs/proposals/LAT-006-runs-and-capture-in-lattices.md` — runs/capture model.
- `docs/proposals/LAT-006-followup-gaps.md` — older gap analysis; verify against
  current `docs/api.md` because some gaps have already been closed.
- Installed comparison docs:
  `/Users/art/.pi/agent/npm/node_modules/@amaster.ai/pi-computer-use/README.md`.
