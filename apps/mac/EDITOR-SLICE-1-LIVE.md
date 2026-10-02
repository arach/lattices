# Slice 1 live acceptance — dev running; UI automation blocked

Source under test: `42406079`, branch `feat/editor-host-slice-1`, worktree
`/Users/arach/dev/lattices-editor-host-slice-1`. Updated October 1, 2026
(Toronto); launch at October 2, 02:54:31 UTC.

## Current result

The authorized handover succeeded using `bin/lattices-dev launch`. The release
process exited; the installed dev app is running as PID **55511**, bundle ID
`dev.lattices.app.dev`, at
`/Users/arach/Applications/dev/Lattices/Lattices.app`. Its startup build trace
confirms revision `42406079`. The release app was not relaunched. No permissions
or login LaunchAgent were changed, and no implementation edits were made.

The menu-bar context menu was opened and its **Editor…** item captured. An
Editor window could not be reliably opened through the available automation,
so the interactive checks remain pending. This is **not** a verified Editor
rendering failure or a completed acceptance pass.

## Checks

| Check | Status | Observed evidence |
|---|---|---|
| 1. Editor opens; panels; Terminal hidden; hiding Chat reflows | **Pending** | Native menu opens and shows Editor…, but no Editor window was observed after attempted selection. Cannot verify selection delivery or panel behavior |
| 2. Preview matches native membership | **Pending** | Native `layers.members` read succeeded (summary below); no Editor projection available to compare. Mismatches not assessed |
| 3. Row↔Source selection; duplicate ambiguity | **Pending** | Editor interactions unavailable. Current workspace has 8 layers and **no duplicate whole-project entries within any layer**; no fixture was added |
| 4. Layout persists; narrow stacks without overwriting wide layout | **Pending** | No Editor window to resize/close/reopen |
| 5. No white flash/blank page; WebKit console clean | **Pending** | No Editor frame observed; no live WebKit console obtained. Application logs are not a substitute for the WebKit console |
| 6. workspace.json mtime and SHA-256 unchanged | **Pass** | Before launch and after attempted checks: mtime_ns `1790863638274089681`; SHA-256 `08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc`; size 3172 bytes |

### Automation blockers and relevant source

- System Events returned `osascript is not allowed assistive access (-1719)`.
  No Accessibility permission was granted or changed.
- Lattices itself already has Accessibility and Screen Recording permission,
  confirmed by startup logs. Its existing daemon capture/pointer APIs were used
  for menu inspection instead. They successfully opened the native context menu.
- Attempts to select Editor dismissed the menu but did not yield an observed
  Editor window. Menu auto-hide and pointer targeting could not be made reliable;
  this does not establish a defect in `EditorWindowController.show()`.
- The existing automation API defaults to a foreground window when none is
  supplied (`Core/Capture/CaptureController.swift:579-620`), and the pointer path
  focuses a resolved window (`Core/Actions/ComputerUseController.swift:1691`).
  Early attempts consequently focused an unrelated existing window; later
  menu-only attempts avoided target resolution. No layer actions, config edits,
  text edits, or window placement commands were issued.
- AX inspection of Lattices' cached hidden window failed with
  `Unable to resolve AX window 176917`; it was not an Editor window.
- The Editor menu wiring is `AppShell/MenuBarController.swift:163,229`;
  the window entry point is `Core/Editor/EditorWindow.swift:136`.
- No new product bug is confirmed. The next step is for Arach to open the actual
  Editor: **right-click the Lattices 3×3 menu-bar icon → Editor…**. That is the
  exact visible menu path, confirmed by the screenshot below. No permissions
  changes or additional app restart are needed to try it manually.

## restoreParked observation

The authorized normal startup calls `restoreParked` at
`AppShell/AppDelegate.swift:78`. There is **no new “LayerStage: restored …” log
entry** for this handover/startup, and a read-only inspection of
`~/.lattices/layer-stage.json` found `parked: []`.

No restoration movement was observed or logged. This is consistent with the
empty-ledger early return in `Core/Workspace/LayerStage.swift:484`, which emits
no zero-work log. It is not a logged “restored 0” receipt. No extra restoration,
activation, layer staging, hiding, placement, or `keepRebinds` call was issued.

## Native membership baseline

Read-only `layers.members` returned:

| Layer | Entries | Member windows |
|---|---:|---:|
| lattices | 4 | 2 |
| fab | 4 | 2 |
| talkie | 4 | 2 |
| scout | 4 | 0 |
| usetalkie | 2 | 0 |
| hudson | 2 | 0 |
| arc | 2 | 0 |
| agentlist | 2 | 0 |

Counts are a point-in-time baseline, not a Preview comparison. Window titles
were kept out of the checked-in evidence.

## External assign: exact available action, human only

There is **no menu-bar Assign item or layer-assignment submenu in this revision**.
This is now confirmed, not an unverified menu-path guess:
`MenuBarController.swift:156-222` defines the shown context menu;
`FrontWindowPlacement.swift:346-367` defines **Move Front Window** as physical
placement only (halves, quarters, etc.), **not** membership assignment.

The separate Hyperspace tile context menu does have **Add to Layer → <layer>**
(`Core/Overlays/Motion/WindowMotionMode.swift:7647-7650`), but it stages an intent
for a later commit, not the requested one-step menu-bar assignment. Do not use
its arrange/keep workflow as a substitute during this restricted test.

**One-step human assignment available here:** with an existing unassigned window
already focused and the desired layer already active, **press ⌘⌥T once**.
This invokes `HotkeyBootstrap.swift:57` → `LayerEditing.swift:181-198` and writes
its membership to the active layer without first switching layers. After the
Editor is open, Arach can do that once and observe Source, Preview and History
updating within about a second without reload/flicker. This intentional human
write belongs *after* the unchanged-config checkpoint. I did not execute it.

## Evidence and build

- Screenshot: [Native context menu showing Editor…](EditorSlice1LiveEvidence/menu-editor-item.png).
  No screenshot of an Editor window exists; none is fabricated or substituted.
- `EditorSlice1LiveEvidence/launch-before.json` and `launch-after.json`: matching
  workspace mtime/hash before launch and after checks.
- `EditorSlice1LiveEvidence/launch-observations.log`: build identity, existing
  permission status, and native menu click evidence.
- `EditorSlice1LiveEvidence/native-members-summary.json`: title-free native counts.
- Previous authorized `bin/lattices-dev build`: passed, installed revision
  `42406079`; `codesign --verify --strict` passed.
- Build log: `/tmp/lattices-editor-slice-1/live/dev-build.log`.
- Original pre-launch evidence remains in `EditorSlice1LiveEvidence/` for audit.

Dev is left running for Arach. No push or merge.
