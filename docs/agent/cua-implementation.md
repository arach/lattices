# CUA Implementation Agent Guide

Use this guide when adding or debugging Lattices computer-use automation. It is
the implementation map for LAT-008 and should stay in sync with daemon, SDK, Pi,
and API docs.

## Source of truth

- Proposal and status: `docs/proposals/LAT-008-pi-lattices-computer-use.md`
- Daemon registry: `apps/mac/Sources/Core/Daemon/LatticesApi.swift`
- Core computer-use actions: `apps/mac/Sources/Core/Actions/ComputerUseController.swift`
- Capture, zoom, local OCR analysis, and visual verification:
  `apps/mac/Sources/Core/Capture/CaptureController.swift`
- Browser read/automation helpers:
  `apps/mac/Sources/Core/Actions/BrowserUseController.swift`
- Screenshot capture primitives:
  `apps/mac/Sources/Core/Desktop/WindowCapture.swift`
- Local OCR model wrapper: `apps/mac/Sources/Core/Desktop/OcrModel.swift`
- JavaScript SDK facade: `packages/npm/sdk/cua.mjs`
- SDK declarations: `packages/npm/sdk/cua.d.ts`
- CLI SDK re-export: `bin/cua.ts`
- Pi extension: `packages/pi-lattices/index.mjs`
- Pi smoke tests: `packages/pi-lattices/test/smoke.mjs`
- Public daemon docs: `docs/api.md`
- Pi docs: `docs/pi-lattices.md` and `packages/pi-lattices/README.md`

## Endpoint map

Phase 1 Pi MVP wraps existing daemon reads and safe mutations:
`daemon.status`, `api.schema`, `windows.list`, `windows.search`, `windows.get`,
`runs.list`, `runs.get`, `ocr.snapshot`, `ocr.search`, `computer.focusWindow`,
`window.place`, `capture.screenshotWindow`, `computer.prepare`,
`computer.launchApp`, `computer.click`, `computer.typeWindowText`,
`computer.typeText`, and `lattices_call`.

Phase 2 AX snapshots and element IDs:
`computer.windowState`, `computer.elementAction`, `computer.typeElement`, and
`computer.setValue`.

Phase 3 rich input:
`computer.pressKey`, `computer.hotkey`, `computer.doubleClick`,
`computer.rightClick`, `computer.scroll`, `computer.drag`, and the improved
`computer.click` count/button support.

Phase 4 capture, vision, zoom, and verification:
`capture.screenshotRegion`, `capture.zoomArtifact`, `vision.analyzeWindow`,
`vision.analyzeArtifact`, and `computer.verify`.

Phase 5 browser/page primitives:
`browser.getText`, `browser.queryDom`, and `browser.executeJavascript`.

Phase 6 package/docs parity:
the SDK, `bin/cua.ts`, Pi extension, package README, daemon docs, proposal, and
this guide must all expose the same supported surface.

## Runtime rules

- Preserve Lattices' treatment model: read-only calls observe, risky actions
  default to `treatment: "stage"`, and mutation requires explicit
  `treatment: "execute"` unless the endpoint documents a different safe mode.
- Keep mutating actions receipt-backed through runs or action receipts whenever
  practical. Include `source` in traceable calls.
- Prefer semantic targets (`snapshotId` + `elementId`, AX path, `wid`, `app`,
  `title`, `session`) before raw coordinates.
- Keep local macOS behavior native. Do not route Lattices through `cua-driver`.
- Vision endpoints currently use local OCR-backed analysis. Do not imply
  always-on cloud vision; any future provider must be explicit and configured.
- Browser DOM queries require `allowAutomation: true`. JavaScript execution also
  requires `treatment: "execute"`.
- Do not silently enable Safari/Chrome automation settings. Return actionable
  errors when permissions or browser settings are missing.
- Screen capture paths may require Screen Recording permission. AX paths may
  require Accessibility permission.

## Add a new CUA primitive

1. Add the Swift implementation in the narrow controller that owns the behavior:
   `ComputerUseController`, `CaptureController`, or `BrowserUseController`.
2. Register the daemon method in `LatticesApi.swift` with a clear description and
   params contract.
3. Add JavaScript SDK schema, client method, top-level export, and declaration in
   `packages/npm/sdk/cua.mjs` and `packages/npm/sdk/cua.d.ts`.
4. Keep `bin/cua.ts` exporting the SDK facade rather than adding a parallel list.
5. Add a typed Pi tool in `packages/pi-lattices/index.mjs`; update
   `packages/pi-lattices/test/smoke.mjs` so registration parity is checked.
6. Update `docs/api.md`, `docs/pi-lattices.md`,
   `packages/pi-lattices/README.md`, LAT-008, and this guide.
7. If the new doc should be first-class for agents, add its slug to
   `apps/site/scripts/agent-docs.mjs` and `docs/reference/dewey.config.ts`.

## Verification

Run the narrow checks for touched surfaces:

```bash
bun run check:app
bun run check:types
node packages/pi-lattices/test/smoke.mjs
bun run --cwd packages/pi-lattices smoke:no-daemon
git diff --check
```

For live behavior, restart the app and use staged calls first:

```bash
lattices app restart
lattices call api.schema '{}'
lattices call computer.launchApp '{"app":"Finder","treatment":"stage","capture":false}'
```

Only run browser DOM/Javascript live checks against a page where the user has
explicitly allowed browser automation.
