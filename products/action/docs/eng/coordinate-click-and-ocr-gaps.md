# Field report: MCP drive session gaps (coordinate click + observe OCR)

Date: 2026-10-01 — Devin session driving Chrome through `action` MCP tools.
The working recipe found: `drive_begin` with `pointerControl: true`, then
`act_execute` with the point on the **action** (`action.target.point`), and
`observe_ocr` with an explicit `imagePath`. Three gaps forced the discovery.

## 1. `resolve_target` drops coordinate geometry → click falls into Calculator demo

`resolve_target` with `{point: {x, y}}` returns a resolved target shaped like:

```json
{ "id": "target", "mode": "coordinate", "confidence": 1, "label": "Resolved Target" }
```

— no `point`, no `bounds`. Then in
`packages/runtime/src/interaction/index.ts` (~L150-193) the click dispatcher reads:

```ts
const point = action.target?.point
  ?? pointFromInput(action.input?.point)
  ?? centerOfBounds(target?.bounds);
if (point) { /* click-point */ }
```

A coordinate-resolved target carries none of those, so execution falls through to
`context.resolveCalculatorButton(...)` → `run-app-host.sh click-calculator-button
--button unknown` → `Could not find Calculator button unknown`. A caller who did
everything "right" (resolve → act) gets a demo-surface error.

**Fix:** the resolved coordinate target should retain `point` (or a 1px `bounds`),
and the dispatcher should read `target.point` alongside `action.target.point`. The
`click-calculator-button` fallback should be gated to a Calculator surface or
removed — a click with no resolvable point should error plainly.

## 2. `observe_snapshot` OCR path never replies

`observe_snapshot` (default `includeOcr: true`) fails with:

```
ActionHost did not write a reply file for command ocr-screenshot
```

`run-app-host.sh` polls the reply file for 10s after `open`-ing Action.app. The
screenshot itself lands fine (`includeOcr: false` succeeds), and
`observe_ocr` with `imagePath` on that same PNG succeeds — capture and Vision OCR
each work; only the combined host command times out.

**Fix:** repair the `ocr-screenshot` app-host command, or have the snapshot
pipeline invoke the same code path `observe_ocr(imagePath)` uses.

## 3. Chrome AX surface is window-chrome only (23 nodes)

`observe_ax` / `observe_snapshot` on Google Chrome return ~23 nodes — toolbar,
tab strip, no DOM. Expected without Chrome's `AXManualAccessibility`, but it
means `resolve_target` by `text`/`role` can never see web content, and nothing
in the tool description warns about it. The chrome-companion content script is
the natural DOM tier.

**Fix (doc-level is fine):** state the limitation on `resolve_target`/`observe_ax`,
or wire the companion's DOM observe as a resolution tier for browser targets.

## Verification recipe

```text
drive_begin { pointerControl: true }
resolve_target { point: {x, y} }            # should return a target carrying the point
act_execute { action: { kind: "click", target: { point: {x, y} } } }
observe_snapshot { includeOcr: true }       # should emit ocr-snapshot artifact
```

Observed environment: `native:doctor` green (AX + screen recording granted,
fresh signature), agent on :4319, macOS Chrome foreground window.
