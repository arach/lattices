# Slice 1 live acceptance — deep-link run

October 1, 2026 (Toronto). Worktree:
`/Users/arach/dev/lattices-editor-host-slice-1`, branch `feat/editor-host-slice-1`.
Installed/tested implementation: **5a2156a9** on top of the approved slice-1
bundle in `42406079`.

## Result

Editor opens through **`open -b dev.lattices.app.dev 'lattices://editor'`**.
The deep link is implemented at `Sources/AppShell/AppDelegate.swift:321-324`.
The signed dev app was rebuilt/reinstalled and relaunched; build passed.
The release app stayed stopped. Dev is left running as PID **71712**, with
**Lattices Editor** open, window ID **177014**, at 1240×852.

Screencapture has the necessary existing permission: all new images were taken
with `screencapture -x -l <Editor-window-id>`. No permissions were changed.
Targeted daemon pointer operations worked reliably inside the actual Editor
window, unlike the earlier auto-hiding menu attempt.

## Acceptance results

| Check | Status | Evidence |
|---|---|---|
| 1. Opens; required panels; Terminal hidden; hide Chat reflows | **Fail: initial panel visibility** | Opens and renders successfully. Terminal is hidden; Chat has the disabled “Agent coming in slice 3” composer. But Source and History are also hidden initially. Expanded layout exposes all four required panels; hiding Chat then reflows to Preview / History / Source |
| 2. Preview agrees with native membership | **Pass for all eight configured groups** | Screenshot rows/counts match the contemporaneous read-only `layers.members` response. No mismatch found. Unassigned also renders (3 windows), but the native group endpoint does not expose an Unassigned group for an independent comparison |
| 3. Row↔Source cross-selection | **Pass for live unique entries; duplicate subcase pending** | Clicking Ghostty `mini: lattices · spare` highlighted its exact app/title JSON object. Selecting text in the ChatGPT Source entry changed Preview selection to ChatGPT. No duplicate whole-project entries exist in the current config, so live ambiguity was not exercised; no fixture/config write was made |
| 4. Layout persists; narrow stacks; wide layout preserved | **Pass** | After hiding Chat, closed Editor with ⌘W and reopened through the explicit dev deep link: the three-panel grid persisted. Resized only Editor to 600px wide: panels stacked. Restored 1240px: the same three-column layout returned |
| 5. No blank page/white flash; console | **Pending transient-flash verification; stable rendering/log checks pass** | Initial, expanded, reopened and resized captures are dark, nonblank and populated. No bridge/WebKit errors appeared in the host diagnostic log. This webview does not enable `isInspectable`; no WebKit console was obtained. Static captures cannot rule out a transient first-frame white flash |
| 6. workspace.json mtime and hash identical | **Pass** | Before rebuild/launch and after interactions: mtime_ns `1790863638274089681`, SHA-256 `08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc`, size 3172 bytes |

### Confirmed acceptance defect

**Source and History & Results are hidden on initial open**, although the brief
calls for the composition with only Terminal hidden by default. Hudson source:

`/Users/arach/dev/hudson-worktrees/lattices-editor-slice-1/apps/lattices-editor/app.tsx:58`

The default `panelPreset` explicitly enables only `['chat', 'preview']`.
The **Expanded layout** button at line 64 enables Chat, Preview, History and
Source, so this is a default-layout mismatch, not missing panels or a native
bridge failure. No UI source or approved bundle bytes were changed during this
acceptance run. The first screenshot captures the mismatch.

No additional host defect was confirmed. The deep-link addition only opens the
Editor and logs that event; it invokes no layer operation or config writer.
There were no existing deep-link tests to extend easily; the route was verified
live both on first open and after closing/reopening the window.

## Native membership comparison

The native read was taken alongside the first Editor screenshot. Exact visible
window titles were compared in memory; the checked-in JSON retains counts only.

| Group | Native member count | Preview count | Result |
|---|---:|---:|---|
| Lattices | 2 | 2 | Match: Ghostty and ChatGPT |
| fab | 3 | 3 | Match: Ghostty, Chrome, fab Settings |
| Talkie | 2 | 2 | Match: Ghostty and Talkie |
| Scout | 0 | 0 | Match |
| usetalkie.com | 0 | 0 | Match |
| Hudson | 0 | 0 | Match |
| arc | 0 | 0 | Match |
| agentlist.io | 0 | 0 | Match |

See `deeplink-members-summary.json`, `editor-initial.png`,
`editor-wide-restored.png`, and `editor-preview-lower.png` below. The lower view
also shows Unassigned with 3 windows. No assignment/activation was issued.

## Startup restoration and safety

The authorized normal startup path includes `restoreParked`.
There is **no new “LayerStage: restored …” receipt** for this restart, and the
read-only staging ledger inspection found `parked: []`. No restoration movement
was observed or logged. This matches the silent empty-ledger return at
`Sources/Core/Workspace/LayerStage.swift:484`; it is not a logged “restored 0”
receipt.

No workspace edits, layer activation, layer staging, hiding, `keepRebinds`, or
placement commands were issued. Only Editor controls, selection, scrolling,
closing/reopening, and its explicitly authorized resizing were exercised.
The intended Editor layout/window-frame persistence was exercised; no Lattices
configuration was edited to generate a change event. No LaunchAgent or
permission changes, push, merge, or release-app relaunch occurred.

## External assign — Arach's step remains pending

There is **no menu-bar membership-assignment item in this revision**.
`Sources/AppShell/MenuBarController.swift:156-222` defines the context menu;
`FrontWindowPlacement.swift:346-367` defines **Move Front Window** as placement,
not assignment. The separate Hyperspace tile menu's **Add to Layer → <layer>**
(`Core/Overlays/Motion/WindowMotionMode.swift:7647-7650`) stages an intent for a
later commit; it is not the requested one-step menu-bar assignment.

**Verified one-step human action:** with an existing unassigned window already
focused and the intended layer already active, **press ⌘⌥T once**.
This invokes `HotkeyBootstrap.swift:57` → `LayerEditing.swift:181-198`.
Arach can then observe Source, Preview and History updating within about a
second without reload/flicker. Do this after the unchanged-config checkpoint;
it deliberately writes membership. I did not execute it.

## Screenshots

All paths are relative to this report, under `EditorSlice1LiveEvidence/`:

- [Initial open — Source/History hidden](EditorSlice1LiveEvidence/editor-initial.png)
- [Expanded composition](EditorSlice1LiveEvidence/editor-expanded.png)
- [Preview row → exact Source entry](EditorSlice1LiveEvidence/editor-row-selected.png)
- [Source selection → ChatGPT row](EditorSlice1LiveEvidence/editor-source-selected.png)
- [Hide Chat → three-panel reflow](EditorSlice1LiveEvidence/editor-chat-hidden.png)
- [Close/reopen → layout retained](EditorSlice1LiveEvidence/editor-reopened.png)
- [600px narrow stacked layout](EditorSlice1LiveEvidence/editor-narrow.png)
- [1240px wide layout restored](EditorSlice1LiveEvidence/editor-wide-restored.png)
- [Lower groups and Unassigned](EditorSlice1LiveEvidence/editor-preview-lower.png)
- [Editor left open for Arach](EditorSlice1LiveEvidence/editor-final.png)

## Build and other evidence

- Implementation commit: `5a2156a9` — deep-link route.
- `bin/lattices-dev build`: passed; production Swift build completed in 216.32s,
  embedded helper build passed, signed dev bundle installed successfully.
- Log: `/tmp/lattices-editor-slice-1/live/deeplink-build.log`.
- Explicit bundle selection was used for both deep-link opens; the release app
  was never targeted by the shared scheme.
- `EditorSlice1LiveEvidence/deeplink-host.log`: installed identity, two successful
  Editor deep-link messages, no matching bridge/WebKit errors.
- `deeplink-before.json` / `deeplink-after.json`: unchanged workspace evidence.
- Earlier attempt records and the native menu screenshot are retained for audit;
  this deep-link run supersedes their pending interactive statuses.
