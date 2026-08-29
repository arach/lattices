# Report: targeting LSUIElement note panels (Blink acceptance)

Implementation report for `docs/eng/act-ensure-surface-blink.md` (rewritten
brief, 2026-08-18). Action-owned API shape; no MCP surface changes.

## What changed

All app-scoped host commands now accept `--pid` and `--bundle-path` alongside
`--bundle-id`, and a bundle id shared by more than one running process is an
error naming both candidates instead of a silent `.first` pick.

New host command:

```bash
native/engine/scripts/run-app-host.sh list-app-windows \
  --bundle-path /Users/art/dev/blink/dist/Blink.app --raise --min-windows 1
```

- Lists every window the named process owns: window-server list by owner pid
  with **no layer or size filter**, merged with the AX window list (titles,
  roles, the raise handle). Floating panels, detached rails, and status items
  all count.
- `--raise` orders each AX window front (`AXMain` + `AXRaise`) without
  activating the app — an accessory target never needs to become frontmost.
- `--min-windows N` fails closed (exit 1) when the named instance has fewer
  windows. It never substitutes another instance.
- Response reports `pid`, `bundleId`, `bundlePath`, `activationPolicy`,
  `windowCount`, `raisedCount`, and per-window `{id, title, role, subrole,
  layer, frame, isOnScreen, source, raised}`.

Accessory apps are first-class in the activation path: `activate-app`,
`focus-window`, and `launch-app` only wait on `NSWorkspace.frontmostApplication`
for `activationPolicy == .regular`; accessory / LSUIElement targets get their
windows AX-raised and return immediately.

`inspect-app-ui`, `screenshot-app-window`, and `focus-window` take the same
`--pid` / `--bundle-path` targeting. Screenshot-by-pid selects the largest
on-screen window with no layer filter (detached chrome can report as "active";
the panel is the surface worth capturing).

### Changed files

- `native/engine/Sources/ActionHostMain.swift` — pid/path/bundle-id resolution
  with ambiguity errors, `list-app-windows`, activation gating, option parser
  accepts bare flags (`--raise`), threading into focus/inspect/screenshot.
- `native/engine/CoreSources/ActionNativeAutomation.swift` — ambiguity-safe
  `runningApplication(bundleId:)`, `runningApplication(pid:/bundlePath:)`,
  `raiseAllWindows(pid:)`, pid overloads for raise/inspect/activate.
- `native/engine/CoreSources/ActionCaptureSupport.swift` — pid-based window
  selection (no layer filter, largest on-screen) and screenshot.
- `native/engine/CoreSources/ActionAgentRuntime.swift` — screenshot method
  accepts a `pid` param.

## Acceptance evidence (run 2026-08-18, both Blinks running)

- Production `/Applications/Blink.app` pid 51313 and sandbox
  `dist/Blink.app` pid 54805 (`BLINK_HOME=/tmp/blink-acceptance-home`) both up.
- `list-app-windows --bundle-path …/dist/Blink.app --raise --min-windows 1` →
  exit 0, `pid 54805`, `activationPolicy "accessory"`, 3 windows: the layer-3
  note panel titled "Sandbox note panel for Action acceptance" (420×340,
  `raised: true`), its detached title rail (261×26, `raised: true`), one
  off-screen layer-0 window. Production was never touched.
- `screenshot-app-window --pid 54805` captured the note panel content.
- `list-app-windows --bundle-id dev.arach.blink` with both running → exit 1:
  "2 running applications share bundle identifier dev.arach.blink; target one
  with --pid or --bundle-path: pid=… path=…; pid=… path=…".
- `focus-window --bundle-path …/dist/Blink.app` → "focused" in 0.4s (was a
  3s frontmost timeout).
- Fail closed: against a 0-window instance, `--min-windows 1` → exit 1,
  "Expected at least 1 window(s) for dev.arach.blink, found 0".

## Blink-side finding

`blink present` into a cold instance's `BLINK_HOME` writes the note file but
does **not** open a panel: panels open via session restore
(`blink.openNotes` defaults), the UI, or wiki-links; the file watcher only
reconciles panels that are already open. The acceptance run seeded
`blink.openNotes` to make the sandbox panel appear. Action reports the
0-window state honestly (that is the fail-closed path), but outcome 6's
deterministic verify loop needs a Blink-side "open the panel" verb — either
`present` opening a panel in the running instance or an explicit open command.

## Caveat for agent harnesses

Run host commands through `native/engine/scripts/run-app-host.sh` (which
launches the app bundle). Executing
`native/dist/Action.app/Contents/MacOS/Action` directly from a sandboxed agent
shell runs without the app's Accessibility/Screen Recording TCC grants: the CG
window list still works, but titles, AX raise, and screenshots silently
degrade.
