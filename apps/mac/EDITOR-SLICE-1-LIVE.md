# Pass 2 geometry and side-nav corrections — 2026-10-02

Native implementation: `a9faf49d`. Approved Hudson bundle:
`cdce3a22029fa5cff522f8b3587a621d12b412cf`. All six SHA-256 values in
`Resources/Editor/provenance.json` match the source dist, repository copy and
installed dev app. The release app was not targeted.

## Results

- **Pass:** Swift tests: 417 tests, 13 skipped, 0 failures, with
  `OVERVIEW_RENDER_DIR=/tmp/lattices-editor-slice-1/pass2-renders`.
  Includes pure layout planning, geometry provenance, ambiguous rule mapping,
  eligibility exclusions and corrected native scope names/counts.
- **Pass:** release Swift build (265.01s), dev packaging, installation and launch.
- **Pass:** panel scope names/counts now use actual indexed windows, not missing
  rules. Both Overview and Layers status bars use the same index total and label
  it **content windows**. All uses an outline square; Unassigned uses a grey dot.
  Initial captures show 12 in both index and status; the later live capture
  shows 11 in both after the live inventory changed.
- **Pass:** real display map matches the native arrangement in top-left points:
  main DELL S3422DWG `(0,0,3440,1440)`, U32J59x
  `(-3840,-396,3840,2160)`, Action Agent Layer `(3440,0,1440,900)`.
  The left display is larger and extends above the main display; the smaller
  right display starts at the main display's top edge.
- **Pass:** last-known window positions are explicitly labelled Last known,
  not represented as live positions. Missing destinations are not invented.
- **Pending live proposed-stage comparison:** the selected Lattices windows
  are not eligible current-main-desktop windows. Preview therefore correctly
  displays “No eligible destinations were supplied”, with Would go unavailable.
  The side-effect-free planner is tested; no windows were moved to manufacture
  a live preview fixture.
- **Pass:** Unassigned and 600pt narrow views render without a blank page.
  No white captured state; still screenshots cannot prove absence of a transient
  white flash. Design-canvas pixel matching remains unverified (canvas unavailable).
- **Pending physical Command-click:** pointer automation cannot send modifiers
  with the available permission/daemon interface. Coordinator asked Arach to
  click Lattices, then hold Command and click fab; no result received at this
  checkpoint. Earlier Command-down evidence is not a physical-click test.
- **Pass:** workspace.json unchanged: SHA-256
  `08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc`,
  mtime_ns `1790863638274089681`, size 3172. No configuration writes or layer
  activation/placement actions were performed. Dev app remains running with
  Layers open at wide width.

## Screenshots

Under `apps/mac/EditorSlice1LiveEvidence/`:
- `pass2-overview.png` — Lattices display map and rules.
- `pass2-preview.png` — honest unavailable layout preview, last-known provenance.
- `pass2-unassigned.png` — Unassigned map and membership.
- `pass2-narrow.png` — narrow layout preview.
- `pass2-counts-live.png` — subsequent live index/status count agreement.

Logs: `/tmp/lattices-editor-slice-1/pass2-tests.log`, `pass2-release.log`,
`pass2-install.log`. Older acceptance records below describe previous revisions.

---

# Shared layer index acceptance

Native Overview now has a 212pt layer index, All windows, Unassigned and additive
layer browsing. The web index receives the same cached Editor projection and
ordered persisted selection. Approved Hudson f5fbca135131ababb1a0a5386b2c49247db1b336
is installed; six asset hashes match the approval. Token mapping is documented
in EDITOR-SLICE-1.md. Native monospace is SF Mono; web monospace is JetBrains Mono.

Validation:
- Swift tests with OVERVIEW_RENDER_DIR: **412 tests, 13 skipped, zero failures**.
  All OverviewRenderTests ran, including four new index render states. The fixed
  fixture footer avoids elapsed-time differences in overlay pixel comparisons.
- Production dev build/install/relaunch passed. Release app was not launched.
- Native All / Lattices / Lattices + fab scopes and the multi-layer footer passed.
  Multi-selection captured using Command-down after Lattices; Command-click uses
  the same additive selector but direct pointer-modifier automation was unavailable.
- Native fab selection appears in Layers immediately on switching pages. Reverse
  direction checked by selecting Talkie in the web index then opening Overview.
- Both indexes showed All=12, Lattices=2, fab=2, Talkie=2, Unassigned=6 in this run.
- 1110pt window keeps the index and desk visible, with kind filters in their menu.
- Current desktop maps are empty because these windows are elsewhere/last-known.
  The fixture render shows scoped green windows and faint outside-scope windows;
  no real window was moved to produce a screenshot.
- No blank or white captured states. Transient flash is not proven absent by stills.
- Workspace SHA-256 and mtime unchanged; no layer/configuration effects executed.

Evidence in EditorSlice1LiveEvidence/:
- desk-sidenav-all.png
- desk-sidenav-layer.png
- desk-sidenav-multi.png
- desk-sidenav-narrow.png
- layers-same-selection.png
- desk-sidenav-render-layer.png (fixture, not live desktop)

Logs: /tmp/lattices-editor-slice-1/sidenav-tests.log and sidenav-install.log.
All render outputs: /tmp/lattices-editor-slice-1/sidenav-renders/.
Dev remains open on Layers. No push, merge or PR. Earlier Pass 2 remains cancelled.

---

# Native Overview desk integration

Merged feat/native-overview-desk aa14e1f6 with merge commit a3539c14, no conflicts.
Merging origin/main (3058abf2) reported already up to date. No history rewritten.
Main checkout and its uncommitted files were not touched.

Imported Hudson 48b58e937b843bf8b5bb959953c486ef005a4de7. Six source/copied/installed
hashes match provenance.json. Cormorant font and license removed, including from
installed resources. Layers now has a sans-serif heading.

With LATTICES_HUDSON_PATH=/Users/arach/dev/hudson: swift test passed, 406 tests,
30 skipped, zero failures. Production dev build/install and dev-only launch passed.
Logs: /tmp/lattices-editor-slice-1/desk-tests.log and desk-install.log.

Screenshots in EditorSlice1LiveEvidence/:
- desk-overview.png: All windows filter, 11 in scope, shown in other desktop
  thumbnails and last-known/minimized lists; current desktop maps are empty.
- desk-overview-layer.png: Lattices scope, two members on last-known Desktop 1.
- layers-overview-sans.png: Layers Overview with sans heading and visible composer.

Both pages render without blank/white captured surfaces. Transient flash cannot
be ruled out from still captures. No stage, tile, focus-window or layer activation
was performed; only scope filters and page navigation were used.
Workspace hash remains 08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc,
mtime_ns 1790863638274089681. Dev app remains running. Pass 2 stays cancelled.

---

# Neutral controls and pinned composer follow-up

October 2, 2026. Imported approved Hudson `46018048d38caeabe16cc43cc089df10a1efe1c7`.
All eight copied and installed assets match the builder's hashes in provenance.json.

- Replaced accent-dependent native Picker with plain accessible segment buttons:
  selected #24282E, white .11 one-pixel border, ink #ECEDEF; unselected #B0B3B8.
- PASS: neutral selected styling in focused Overview, focused Workspace, narrow
  Overview and unfocused Overview (grey traffic lights in the extra capture).
- PASS: Overview composer fully visible in wide and 600px narrow captures.
  Short grid Chat panel shows the entire input. Reading/Try content scrolls.
- Debug and release builds passed; 369 tests, 13 skipped, zero failures.
  Dev package/install/launch passed. No release app launch.
- Workspace SHA-256 and nanosecond mtime unchanged from the checkpoint below.
- Refreshed overview-first-open.png, overview-workspace.png, overview-narrow.png;
  added overview-unfocused.png in EditorSlice1LiveEvidence/.
- Dev remains running. No white/blank captured states; transient flash remains
  unverified by still screenshots. No push, merge or PR.

---

# Overview bundle live acceptance

October 2, 2026. Native `adc62d2c`; approved Hudson
`fb63d654f3e0554923dcd0b15b4db5ba00e269e1`.

- PASS: all eight imported and installed asset SHA-256 values match approval.
  Font files and both licenses are bundled; importer validates local CSS URLs.
- PASS: bundle-tier production build, install and dev-only launch. Release app
  was not launched. Previous native validation: 369 tests, 13 skipped, no failures.
- PASS: first open defaults to Overview. READ ONLY tag, native segment and live
  status are visible; arrangement/panel controls are absent there.
- PASS: clicking + Preview opens Workspace and updates the native segment;
  arrangement, panels and source controls appear. Existing two-window selection
  and source highlighting remain visible.
- PASS: 600px-wide window collapses the web layer list into its narrow selector;
  native controls and status fit. Restored window to 1240px width afterward.
- No white or blank surface appears in the captured opening, Workspace or narrow
  states. Transient white flash remains unverified: still screenshots do not
  establish frame-by-frame behavior. No reload was requested on view switches.
- No functional defect observed in this pass. The active native segmented control
  uses macOS blue selection; other selection remains emerald.
- Workspace SHA-256 remains
  `08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc`;
  mtime_ns remains `1790863638274089681`. No config or layer actions performed.

Screenshots in `apps/mac/EditorSlice1LiveEvidence/`:
- `overview-first-open.png`
- `overview-workspace.png` (after + Preview)
- `overview-narrow.png` (600 × 760 window)

Build log: `/tmp/lattices-editor-slice-1/overview-dev-build.log`.
Dev app remains running on Layers / Overview.

---

# Layers page live acceptance — shell integration

October 2, 2026. Worktree /Users/arach/dev/lattices-editor-host-slice-1,
branch feat/editor-host-slice-1. Installed native code **683e871b** with
approved Hudson **b3dfd98f7a0d182bcf78ce4eed5fc59cfbda91e5**.

## Delivered

- **1c15827f**: Layers after Overview in Workspace; existing bridge/WKWebView
  embedded in the app shell. The actual standalone window is **removed**.
  EditorWindowController remains only as a compatibility router to Layers;
  both the Layers… menu item and lattices://editor open the main app window.
- One process-retained EditorWebHost owns the WKWebView. Returning from Activity
  retains the two selected windows, source highlights and grid arrangement.
  No second load is issued on page changes. Palette.bg is set before loading.
- Native PageActions own Arrangement, Panels and Inspect source. Menu selections
  and the source toggle track ui.state. Search stays the shell's usual action.
  Header says Layers / Read only; web header/status chrome is absent.
- **150cb8ee**: imported the approved host-chrome bundle only after its commit
  and five hashes were posted on hudson-editor-spec-20261001.
  All five copied AND installed hashes match, including font and license.
- **69f8dde4**, **10d93feb**: toggle accessibility and native checked menu items.
  Live testing exposed that a Label image was not a native menu checkmark;
  Toggle-backed items now visibly check the current panels.
- **8f1e8bab**, **683e871b**: compact header controls use actual window width;
  the existing three status slots compress proportionally at narrow widths.
  The old fixed status widths otherwise forced the entire shell to clip at
  its advertised 600px minimum. No Editor-specific status fields were added.

## Live results

| Check | Result |
|---|---|
| Layers routing and main-window chrome | Pass: sidebar order, title/subtitle, native actions and standard status slots visible; no standalone Editor window |
| Two selections | Pass: Ghostty + ChatGPT selected, two chips, panel-local selected count, Source highlights |
| Arrangement / Panels / Inspect source | Pass: native Columns/Grid actions, History toggle, Source off/on; native checked states reflect web state |
| Expanded composition | Pass: occupied Chat, Preview, History and Source grid |
| Narrow composition | Pass: 800px and 600px main-window widths; Preview, attached chips and Source stack; native controls remain accessible; standard status text truncates within its three slots |
| Return from another page | Pass: Activity → Layers preserves two selections and layout; same retained web host |
| Workspace safety | Pass: hash and mtime identical before and after all tests |
| Transient white flash | Not conclusively measured: stable captures are dark/nonblank; no reload on page switching; no frame-by-frame capture |

The initial first-open/two-selected and menu captures are from native 10d93feb.
Expanded, narrow, minimum-width and returned captures are from final 683e871b.
The later changes affect narrow native chrome only, not the approved web bytes.

## Screenshots

All under /Users/arach/dev/lattices-editor-host-slice-1/apps/mac/EditorSlice1LiveEvidence/:

- shell-first-open.png
- shell-two-selected.png
- shell-expanded.png
- shell-narrow.png
- shell-min-width.png
- shell-panels-menu.png
- shell-returned.png (final state left open)

## Builds and tests

- Native bundle build passed.
- Full suite during integration: **368 executed, 13 skipped, zero failures**.
- Final targeted Editor/membership suite after narrow fixes: **54 passed**.
- Free-tier compile passed for initial native integration (1c15827f); the
  subsequent changes are shared shell styling, not a new free-tier validation.
- Final signed/installed dev production build passed (225.41s; helper 0.25s).
- Logs: /tmp/lattices-editor-slice-1/shell-build.log,
  shell-all-tests.log, shell-free-build.log, shell-narrow-tests.log,
  shell-compact-dev-build.log.
- A redundant intermediate production compile was interrupted before editing
  the status-width fix; the final build above completed cleanly.

## Final state and safety

Dev bundle remains running **PID 33974**, main window **178212**, Layers selected,
1240×760, expanded grid, two windows selected. Release app remained stopped.
No push, PR or merge. No permission changes or workspace edits.

workspace.json SHA-256:
**08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc**
mtime_ns: **1790863638274089681**.
Evidence: shell-before.json / shell-after.json.

No layer activation, staging, desktop-window hiding or placement commands
were issued. Native UI actions changed only Editor layout/selection; resize
tests targeted only the app shell hosting Layers. Earlier human external-assign,
duplicate-fixture and runtime-font/first-frame checks are not claimed here.

---

# Slice 1 live acceptance — approved design refresh

October 2, 2026 (Toronto). Feature branch/worktree unchanged.

## Import and build

- Hudson **064386a68599ef7815928518a25d89fc50aa8468**, imported in **81bd76e2**.
- All **five** approved hashes verified after copying and again in the installed
  dev app, including JetBrains Mono WOFF2 and license. Importer updated to retain
  both assets. No approved CSS/JS/HTML bytes modified.
- Bundle Swift build passed (74.84s); targeted Editor/membership tests:
  **51 passed, zero failures**.
- Dev bundle build passed (0.68s; helper 0.37s), signed and installed.
  Only dev was quit/relaunched; release untouched.
- Logs: /tmp/lattices-editor-slice-1/design-{build,tests,dev-build}.log.
- Opened via explicit dev bundle deep link. Dev remains running **PID 68863**,
  Editor **177577**, restored to **1240×852**, Expanded layout, two selections.

## Visual checks

- First open: Chat + Preview columns, dark/nonblank, Terminal hidden. This is
  the approved new default, superseding the earlier four-panel default.
- Two selected windows: Ghostty and ChatGPT in the Lattices group, with two
  context chips and **2 windows selected** in the bottom status bar.
  Emerald row highlights, source highlights, chips and live indicator visible.
- Expanded layout: four occupied cells (Chat, Preview, History, Source).
- Narrow at 600px: vertical stack, Preview first; bottom status stays visible.
  Narrow Chat reduces to context chips, and layer/window counts disappear from
  status; both are explicitly implemented by Hudson's responsive CSS, not host
  failures. The first narrow capture retained the scrolled position; a second
  capture scrolls to the top. Restoring width returns the filled grid.
- Font: installed WOFF2 and license hashes match. CSS resolves its relative
  WOFF2 URL to the same Editor bundle directory; existing scheme handler serves
  font/woff2 and permits self fonts. Mono labels and Source render visibly.
  **Runtime font identity remains unverified:** no WebKit inspector/font API
  readback was available, so visual inspection cannot rule out a fallback.
- White flash: all captured states are dark and nonblank. **First-frame flash
  remains unverified**; still screenshots do not establish absence of a
  transient flash before capture.
- No new confirmed visual defect. The two limitations above are not passes.

## Screenshots

Under apps/mac/EditorSlice1LiveEvidence/ in this worktree:

- design-first-open.png
- design-two-selected.png
- design-expanded.png
- design-narrow.png
- design-narrow-top.png
- design-final.png (left open for Arach)

## Safety checkpoint

workspace.json unchanged across import/build/relaunch/interactions:
SHA-256 **08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc**,
mtime_ns **1790863638274089681**. Evidence: design-before.json and
design-after.json. No workspace edits, layer actions, permissions changes,
push, PR or merge. Only Editor selection, layout expansion and Editor resize
were exercised.

---

# Slice 1 live acceptance — merged tier split

October 1, 2026 (Toronto). Same feature worktree and branch as below.

- Merge **0df6b883** brings origin/main **3058abf2** into the feature only.
  AppShellView keeps ScreenText.shared and OverviewModel; drops unused
  commandState/selectedStudioLayerId.
- Follow-up **549db666** replaces the additional direct OcrModel reference at
  Core/Overlays/Overview/OverviewModel.swift:245 with ScreenText.shared.
  Boundary audit and build details are in EDITOR-SLICE-1.md.
- Default bundle build **PASS**, free build **PASS** (not installed).
  Full bundle tests: **365 executed, 13 skipped, zero failures**.
- Bundle dev production build **PASS** (244.76s), embedded helper **PASS**
  (2.69s); signed and installed at ~/Applications/dev/Lattices/Lattices.app.
  Log: /tmp/lattices-editor-slice-1/tier-dev-build.log.
- Launch log confirms **bundle [spatial-lens, screen-text, companion]**.
  Opened Editor with the explicit dev bundle deep link.
  Dev remains running **PID 19150**, Editor **177269**, 1240×852.
  Release remains stopped. No free app was installed or launched.
- Screenshot: [bundle tier with Editor](EditorSlice1LiveEvidence/tier-bundle-editor.png).
  Editor renders Chat, Preview, History & Results and Source in the retained
  filled 2×2 grid, Terminal hidden, with live groups/source populated.
  This run is an open/render smoke test, not a rerun of selection/membership.
- workspace.json hash **and mtime unchanged** across builds/tests/relaunch:
  SHA-256 `08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc`,
  mtime_ns `1790863638274089681`, size 3172.
  Evidence: tier-before.json, tier-after.json, tier-host.log.
- No restoreParked movement receipt observed. No config writes, layer actions,
  hide/move actions or permission changes. No push or merge into main.
- Approved Hudson UI remains **74679b4**; no newer bundle imported.
  Earlier pending duplicate, flash/console and human assignment checks remain.

---

# Slice 1 live acceptance — approved 2×2 grid regression

October 1, 2026 (Toronto). Worktree:
`/Users/arach/dev/lattices-editor-host-slice-1`, branch `feat/editor-host-slice-1`.

## Latest result: Hudson 74679b4

Imported approved Hudson `74679b445ae24cae817a3fd98bb9bf91720bc239`.
All three copied hashes match the coordinator's values; provenance records the
same clean source revision. Native bundle import commit: **19d92c89**.
This section supersedes the initial-panel defect and running-process details
in the historical deep-link report below.

- **Check 1 PASS:** first open after upgrade automatically replaced the previous
  saved three-column, Chat-hidden layout with the filled **2×2** grid:
  Chat / Preview above History & Results / Source. All four panels are visible,
  no empty cell, Terminal hidden. No manual layout reset or storage deletion.
  Screenshot: [migrated grid](EditorSlice1LiveEvidence/grid-migrated.png).
  This demonstrates migration of the existing saved layout on upgrade; a second
  migration-cycle test with a newly customized layout was not performed.
  The previously reported default-layout defect is resolved.
- **Selection spot-check PASS:** clicking the first Lattices Ghostty Preview row
  selected one window and highlighted exactly its project JSON object at Source
  lines 9–12. Screenshot:
  [selection](EditorSlice1LiveEvidence/grid-selection.png).
  Reverse selection passed in the earlier run; not repeated in this spot-check.
- **Check 6 PASS:** workspace.json unchanged across import, rebuild, relaunch
  and selection: SHA-256
  `08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc`,
  mtime_ns `1790863638274089681`, size 3172 bytes.
  Evidence: `grid-before.json` and `grid-after.json`.
- Checks 2 and 4 retain the earlier pass evidence, not rerun here.
  Check 3 duplicate subcase and check 5 transient flash/WebKit console remain
  pending as described below. Stable current captures are dark and nonblank.
  External assignment remains Arach's manual check.

## Current build and running state

- `swift build --package-path apps/mac`: passed (10.43s).
- `swift test --package-path apps/mac --filter 'EditorBridgeTests|LayerMembershipTests'`:
  **51 passed, zero failures**.
- Logs: `/tmp/lattices-editor-slice-1/grid-build.log` and
  `/tmp/lattices-editor-slice-1/grid-tests.log`.
- `bin/lattices-dev build`: passed; incremental production build 1.98s,
  embedded helper build 1.95s; signed and installed dev bundle.
  Log: `/tmp/lattices-editor-slice-1/grid-dev-build.log`.
  First build attempt safely refused while the quitting dev process was still
  exiting; retried only after confirming it had stopped.
- Launched with `bin/lattices-dev launch`, then
  `open -b dev.lattices.app.dev "lattices://editor"`.
- Dev remains running **PID 90586**, Editor **177158**, 1240×852.
  Release remains stopped. Editor is left open with the selected row.
- No config writes, layer operations, permission changes, push or merge.
  No manual window hide/move actions. The only test interaction after opening
  was a click inside the Editor's read-only Preview.
- No restoreParked movement receipt observed during this launch.

---

# Historical deep-link run

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
