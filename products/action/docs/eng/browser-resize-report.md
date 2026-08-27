# Report: `browser_resize` — supported viewport resizing in Action Browser

Implementation report. Requested by `openscout-agent-2` (2026-08-20) so OpenScout
live UI verification can exercise responsive breakpoints. Adds one MCP tool; no
existing tool changes behaviour.

Plugin version **0.2.0 → 0.3.0**.

## What changed

New tool `browser_resize` sets an already-open Action Browser tab to an explicit
width and height.

```text
browser_open   { url: "http://localhost:3000" }
browser_resize { width: 1440, height: 900 }
browser_screenshot
browser_resize { width: 390, height: 844, mobile: true, matchMedia: ["(max-width: 767px)"] }
browser_screenshot
browser_resize { reset: true }
```

Schema: `width`, `height` (integers, 120–8192 CSS px, required unless `reset`),
`target` (`tab` | `window`), `tabId`, `deviceScaleFactor` (0.5–4, default 1),
`mobile`, `matchMedia` (string[]), `reset`. `additionalProperties: false`.

Two targets, deliberately not interchangeable:

| | What moves | Cost |
|---|---|---|
| `target: "tab"` (default) | CSS emulation for that one tab | Exact to the pixel, other tabs unaffected, fully reversible |
| `target: "window"` | The real Chrome window hosting the tab | Every tab in that window moves, the display is a hard ceiling, and the tab's emulated viewport is dropped first |

The reply reports the *measured* viewport, not the requested one, plus `exact` /
`widthDelta` / `heightDelta`, `widthClass`, `emulated`, and the `matchMedia`
answers. `browser_screenshot` now also reports the `viewport` it captured at, so
a breakpoint screenshot is self-describing.

Files: `plugins/action-browser/server/viewport.ts` (new, pure argument contract),
`viewport.test.ts` (new, 12 tests), `server/index.ts` (wiring),
`skills/action-browser/SKILL.md`, `docs/browser-profiles.md`, `AGENTS.md`.

## Two CDP findings that shaped the design

Both were found by probing Chrome directly, and both would have shipped as silent
wrong-size screenshots.

**1. A device-metrics override outlives the CDP session that set it, but only that
session can clear it.** Action Browser opens a fresh CDP session per tool call, so
the naive implementation is wrong in both directions: a resize looks like it will
evaporate before the next screenshot (it does not), and `reset` calling
`clearDeviceMetricsOverride` from a new session is *accepted and does nothing* —
Chrome stays stuck at the stale size forever.

- Sticky is made explicit rather than incidental: the override is held in memory,
  keyed by tab id, and re-applied on every session including the one
  `browser_open` uses, so the first layout after a navigation is already correct.
- `reset` re-sets the metrics to take ownership, *then* clears them. Adopting the
  size already on screen makes the round trip invisible. Touch emulation has the
  same ownership rule and is cleared the same way.

**2. `target: "window"` cannot measure the browser chrome inset through an
emulated viewport.** The inset is `outerWidth - innerWidth`, and emulation
rewrites `innerWidth`. With a 500px override on a 1440px window the inset came out
as 956px instead of 0, and a requested 900×600 window produced an 1840px viewport.
The window path now drops the tab's emulated viewport first — which it must do
anyway, since an emulated viewport would hide the new window size from the page.

## No lifecycle or profile leakage

- Override state is in-memory only, per tab. Nothing is written to the profile.
- Dropped on `browser_resize { reset: true }`, on tab close, on
  `browser_close { scope: "browser" }`, on profile switch, and pruned in
  `listTargets` for tabs that no longer exist.
- No new processes, ports, sockets, or claim files. `withBrowserSession` uses the
  existing debug port and closes in a `finally`.
- Verified after each run: no orphan Chrome, no stale session claims, test debug
  ports closed. Test profiles were removed.

## Verification

`bun test plugins/action-browser/server/` — 23 pass, 0 fail.
`bunx tsc --noEmit -p tsconfig.json` — clean.
`claude plugin validate` — plugin and marketplace manifests pass.

Live, driving the real MCP server over stdio against Chrome on an isolated profile
and debug port. PNG dimensions are `sips` output, not the tool's own claim.

| Step | Measured viewport | PNG | Breakpoint |
|---|---|---|---|
| `{ width: 1440, height: 900 }` | 1440 × 900, `exact: true` | 1440 × 900 | `(max-width: 767px)` false |
| `{ width: 390, height: 844, mobile: true }` | 390 × 844, `exact: true` | 390 × 844 | `(max-width: 767px)` **true**, `(pointer: coarse)` **true** |
| `browser_open` again on the same tab | 390 × 844 | 390 × 844 | override survived the navigation |
| `{ reset: true }` | 1440 × 913, `emulated: false` | 1440 × 913 | `(pointer: coarse)` back to false |
| `{ width: 900, height: 600, target: "window" }` | 900 × 600, `exact: true`, inset 0 × 87, bounds 900 × 687 | 900 × 600 | `(max-width: 1023px)` **true**, `emulated: false` |
| `{ reset: true, target: "window" }` | 1440 × 913 | — | window bounds back to 1440 × 1000 |

A probe page with `@media` rules at 768px and 1024px confirms the layout actually
switched (DESKTOP → MOBILE → TABLET), rather than the page merely being clipped.
Regression check on a real site: `browser_open` + `browser_screenshot` with no
resize is unchanged at 1440 × 913 with `emulated: false`, and `browser_snapshot`
still returns element geometry.

Screenshots and the probe page:
`~/Library/Application Support/Action/BrowserArtifacts/resize-verification-0.3.0/`

Nine error paths return actionable messages, e.g. `width must be between 120 and
8192 CSS pixels, not 100.`, `reset cannot be combined with width or height`,
`deviceScaleFactor and mobile only apply to target=tab`.

## Installing

The `action` marketplace on this Mac mini is a **local directory source** at
`/Users/art/dev/action`, so no push is required for this machine.

```bash
claude plugin marketplace update action
claude plugin update action-browser@action
```

Restart Claude Code afterwards — the plugin CLI states a restart is required, and
harnesses cache plugin metadata by version. Confirm with `/mcp` that
`action-browser` is connected and `browser_resize` is listed.

The installed copy is currently **0.1.0** (cached 2026-07-28), so this update also
picks up the 0.2.0 browser-identity work. Sessions that run the repo copy directly
via `plugins/action-browser/server/index.ts` get 0.3.0 on restart with no install
step.

Codex: `codex plugin update action-browser@action`. Kimi reads
`plugins/action-browser/kimi.plugin.json`, also at 0.3.0.

**Not committed.** The change sits in the working tree on `main`. If the install
resolves through git rather than a working-tree copy, it needs a commit first —
that call is Art's.
