# LAT-008: pi-lattices and Safe Computer Use Expansion

Status: Implemented through Phase 6
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

Implementation status: the daemon, SDK, Pi extension, and docs now cover the
full planned LAT-008 surface. External npm publication remains a release
operation; the package is installable from local/git paths and is ready for
publish packaging.

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

The package and daemon implementation now cover Phase 1 through Phase 6. Phase
1 was implemented as a wrapper around existing daemon methods; later phases add
native Swift endpoints while keeping Lattices' treatment/run/artifact model.

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
- `computer.pressKey`, `computer.hotkey`, `computer.doubleClick`,
  `computer.rightClick`, `computer.scroll`, and `computer.drag` are present for
  rich input.
- `capture.screenshotRegion` and `capture.zoomArtifact` are present for
  region capture and derived zoom artifacts.
- `vision.analyzeWindow` and `vision.analyzeArtifact` are present as explicit
  local OCR-backed analysis endpoints.
- `computer.verify` is present for AX, OCR, text containment, and artifact-change
  verification.
- `browser.getText`, `browser.queryDom`, and `browser.executeJavascript` are
  present with explicit browser automation gates.
- `packages/npm/sdk/cua.mjs`, `packages/npm/sdk/cua.d.ts`, `bin/cua.ts`, and
  `packages/pi-lattices/index.mjs` expose the same supported CUA surface.

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

Implemented in `packages/pi-lattices/`. It is installable by Pi as a local/git
package and structured for npm publication.

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
- `lattices_computer_press_key` → `computer.pressKey`
- `lattices_computer_hotkey` → `computer.hotkey`
- `lattices_computer_double_click` → `computer.doubleClick`
- `lattices_computer_right_click` → `computer.rightClick`
- `lattices_computer_scroll` → `computer.scroll`
- `lattices_computer_drag` → `computer.drag`
- `lattices_computer_type_window_text` → `computer.typeWindowText`
- `lattices_computer_type_text` → `computer.typeText`
- `lattices_capture_region` → `capture.screenshotRegion`
- `lattices_capture_zoom_artifact` → `capture.zoomArtifact`
- `lattices_vision_analyze_window` → `vision.analyzeWindow`
- `lattices_vision_analyze_artifact` → `vision.analyzeArtifact`
- `lattices_computer_verify` → `computer.verify`
- `lattices_browser_get_text` → `browser.getText`
- `lattices_browser_query_dom` → `browser.queryDom`
- `lattices_browser_execute_javascript` → `browser.executeJavascript`

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

Implemented. Lattices can inspect a target window's AX tree and create an
actionable snapshot.

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

Implemented. The Lattices-native computer-use endpoints analogous to the useful
`cua-driver` primitives preserve the treatment/capture/run model.

Candidate endpoints:

- `computer.pressKey` (implemented)
- `computer.hotkey` (implemented)
- `computer.scroll` (implemented)
- `computer.drag` (implemented)
- `computer.doubleClick` (implemented)
- `computer.rightClick` and improved `computer.click` with `count` and button (implemented)

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

Implemented. Agents can reason about screenshots and prove outcomes through
run-backed capture artifacts, local OCR analysis, and verification helpers.

Candidate endpoints:

- `capture.screenshotRegion` (implemented)
- `capture.zoomArtifact` (implemented)
- `vision.analyzeWindow` (implemented with local OCR-backed analysis)
- `vision.analyzeArtifact` (implemented with local OCR-backed analysis)
- `computer.verify` (implemented)

`vision.*` is optional and explicit. The current implementation uses local
Vision OCR and returns `provider: "local-ocr"`; it does not imply always-on
cloud vision.

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

Implemented. Browser-specific read and page endpoints are available once the
core safe computer-use surface is in place.

Candidate endpoints:

- `browser.getText` (implemented)
- `browser.queryDom` (implemented; requires `allowAutomation: true`)
- `browser.executeJavascript` (implemented; requires `allowAutomation: true` and
  `treatment: "execute"`)

Guardrails:

- Browser mutation and enabling JavaScript automation require explicit user
  consent.
- Prefer read-only browser operations by default.
- Document supported browsers and required app settings.

## Phase 6: Package polish and docs

- Package `pi-lattices` is structured for Pi install via local/git path and npm
  publication. Actual npm publishing is a release operation outside this code
  change.
- Lattices docs, package README, SDK facade, TypeScript declarations, and Pi
  smoke tests are updated.
- `lattices mcp` was not added; the Pi extension and daemon API remain the
  supported package surface.

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
4. Add keyboard/scroll/drag/double-click primitives. **Done.**
5. Add vision/zoom/verify. **Done.**
6. Add browser primitives. **Done.**
7. Keep SDK, Pi, API docs, package README, and
   `docs/agent/cua-implementation.md` in parity for future changes. **Done.**

## Validation commands

Run the narrowest checks for the touched area. Common commands from this repo:

```bash
bun run check:types
bun run check:app
node packages/pi-lattices/test/smoke.mjs
bun run --cwd packages/pi-lattices smoke:no-daemon
git diff --check
```

Manual checks will also be necessary for macOS Accessibility and Screen
Recording behaviors.

## Source references

- `docs/api.md` — current daemon and computer-use API.
- `apps/mac/Sources/Core/Daemon/LatticesApi.swift` — endpoint registry.
- `apps/mac/Sources/Core/Actions/ComputerUseController.swift` — existing
  computer-use implementation.
- `apps/mac/Sources/Core/Capture/CaptureController.swift` — screenshot region,
  zoom artifact, local OCR analysis, and visual verification implementation.
- `apps/mac/Sources/Core/Actions/BrowserUseController.swift` — browser read,
  DOM query, and explicit JavaScript execution implementation.
- `docs/agent/cua-implementation.md` — future-agent implementation checklist.
- `packages/npm/sdk/cua.mjs` and `packages/npm/sdk/cua.d.ts` — current SDK facade.
- `docs/proposals/LAT-005-action-runtime-product-spine.md` — action runtime
  product direction.
- `docs/proposals/LAT-006-runs-and-capture-in-lattices.md` — runs/capture model.
- `docs/proposals/LAT-006-followup-gaps.md` — older gap analysis; verify against
  current `docs/api.md` because some gaps have already been closed.
- Installed comparison docs:
  `/Users/art/.pi/agent/npm/node_modules/@amaster.ai/pi-computer-use/README.md`.
