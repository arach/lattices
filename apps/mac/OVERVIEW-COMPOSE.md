# Overview layer composition

Branch: feat/layers-compose, based on origin/main e9d70400.

The window Layer menu now offers Add to, removable memberships (or a disabled
rule-held explanation), and New layer with this window. The multi-selection
footer offers New layer from N windows and, with one layer scoped, Add N to it.
A staged sheet names the layer and picks Left/Middle/Right/Full slots. The preview
uses LayerLayout.frames; the exact preview boxes are encoded as explicit grid
tiles. Only Create saves them; it never activates or arranges the layer.

Default lanes use AppTypeClassifier and LayerLayout.lane. Empty neighboring
lanes are reserved for explicit Left/Middle/Right picks. Full fills the display
and may overlap other slots. Off-desktop windows are kept in membership.

After create/add, shared layer selection follows the destination and Overview
shows a one-line confirmation. Remove uses the existing removal feasibility
calculation; no editing code was duplicated.

## Validation

Baseline: 441 Swift tests executed, 13 skipped, zero failures. Three new fixture-only composition tests plus two render tests
 cover terminal + Chrome lane geometry, off-desktop pinned membership,
slot/preview consistency, defaults and deduplication. No real layer was created,
added, removed or edited during development.

Unrelated bundle edits were preserved in stash
4ee5bdd30acbf851eac05e9784301f92499bc83e
(On feat/layers-act: Preserve coordinator bundle edits before layers-compose).
They are not part of this branch.

## User test

1. Open Overview and select All windows in the left index.
2. Open the window list with the panel toggle.
3. Click the Ghostty window, then Command-click the Chrome window.
4. In the selection footer, click New layer from 2 windows.
5. Name it Chrome + terminal. Confirm Ghostty = Left and Chrome = Right.
6. Click Create. This saves membership only; nothing moves.
7. Select the new layer in Layers and use Gather separately when ready.

For one window, select it, open Layer, then Add to > a layer, or
New layer with this window. Cancel dismisses the sheet without saving.


## Evidence and live limits

- compose-layer-menu.png: live dev app, a Chrome window on a last-known desktop;
  Add to, Remove from and New layer are visible. The menu was dismissed.
- compose-multi-footer.png and compose-new-layer-sheet.png: **fixture renders**,
  not screenshots of the user's real selection. They use Ghostty + Chrome and
  exercise the same native views; render Create callbacks fail the test if run.
- Direct event-posting permission is absent for this shell; daemon modifier
  automation did not produce a reliable multi-selection. No permissions changed.
  Real Command-click, multi-window sheet opening and Cancel remain for user
  acceptance. No live Create/Add/Remove, Gather or layout action was run.
- Release build passed (229.91s); dev app installed/relaunched from this worktree.
  The release app was not touched.
- workspace.json SHA-256 and mtime_ns unchanged from the pre-launch baseline:
  08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc;
  1790863638274089681.
- Logs: /tmp/lattices-editor-slice-1/compose-final-tests.log,
  compose-release.log and compose-install.log.

## Picker, drag and right-click addendum

### Picker diagnosis and fix
The toolbar was mounted only when a child emitted a geometry anchor. A missing
anchor removed the entire menu owner even while focusedWid remained selected.
Its position also followed geometry refreshes beneath an open menu. No
hover-driven visibility or mouse-out selection clearing exists in this view.
A diagnostic render was built/run before the fix (compose-picker-trace.log).
The intermittent pointer symptom was not reliably reproduced live.

The toolbar now stays mounted for the selected window, including when its
canvas anchor is missing. Its placement is latched per selection, with a
fallback for an off-canvas/last-known window, so refresh does not drag an open
menu away. Toolbar gaps consume clicks instead of falling through to canvas
selection clearing. A render regression selects an unplaced window then
changes desktop scope.

### Membership drag
Canvas tiles, tray rows and All windows rows supply an own-process membership
payload. Dragging a selected window carries the entire selection; dragging an
unselected one carries only it. A per-model session token rejects foreign
payloads. Drop routes through the same add/remove/move methods as the menus:
- Layer row: add. Hover shows Add to <layer>.
- Unassigned: remove removable memberships; rule-held memberships remain and
  are reported.
- Option held at drag start, from a scoped layer: move to the target using
  moveWindow. If source rules retain membership, the confirmation says so.
- Sheet: drag a staged window row onto Drop: Left/Middle/Right inside the preview.
  This changes only the draft. Cancel never saves it.

A drag never calls a window placement or activation API.

### Context menus
Canvas tiles and list rows offer Add to Layer, New Layer, removable memberships
and New layer from N selected. Layer index rows offer Add selected windows here.
All share addWindows/createLayer/moveWindow/removeWindow paths.

### Undo decision
Membership Undo is deliberately omitted. addWindows/createLayer may remove pins
from other layers, and move/remove may rewrite multiple entries. A safe inverse
requires revision-checked configuration transactions rather than a cheap
single-entry reversal. No desktop Undo is reused for configuration edits.

### Exact user paths
- Picker: select a window → Layer ▾ → Add to → target layer. Or New layer with
  this window → name/slot → Create.
- Drag: drag a window tile or list row onto Talkie in the left index. Select
  several with Command-click first to carry all. Hold Option **before starting**
  from one scoped layer to move instead of add. Unassigned removes membership
  where rules permit.
- Right-click: right-click a window → Add to Layer → target, or New Layer.
  Right-click a layer index row → Add selected windows here.
- Compose: select Ghostty + Chrome → New layer from 2 windows → name →
  Ghostty Left / Chrome Right → Create. Gather remains a separate step.

### Addendum validation and remaining acceptance
- Final suite: **446 tests executed, 13 skipped, zero failures** (20.164s).
  Release build passed (226.24s), dev bundle installed from this worktree.
- `compose-drag-hover.png`, `compose-new-layer-sheet.png`, and
  `compose-unplaced-toolbar.png` are fixture renders, not live drag evidence.
  Tests also cover multi-selection payloads, serialization, and rejection of
  another model's drag session without configuration writes.
- Live right-click and picker traversal remain **pending**. A daemon AX click
  intended for Overview crashed the dev app: the crash report identifies
  `ComputerUseController.swift:3345` (`pressViaAX`) invoking AppKit off the main
  thread ("Must only be used from the main thread"). This existing automation
  path was not changed. No further AX automation was attempted. Crash report:
  `/Users/arach/Library/Logs/DiagnosticReports/Lattices-2026-10-03-133353.ips`.
- The earlier pointer click's focus helper moved the dev app's own main window
  to the current Space; no other window was moved. Dev was relaunched afterward
  (PID 69793), with Layers open. Release app was not launched.
- Real drag/drop, Command-click, menu stability, and sheet Cancel still need
  manual acceptance. No actual membership drop or Create/Add/Remove ran live.
- Real workspace hash and mtime remain identical to the baseline above.
- Logs: `/tmp/lattices-editor-slice-1/compose-drag-final-tests.log`,
  `compose-drag-release.log`, `compose-drag-install.log`.

## Lost submenu pick follow-up (gpct1j)

Reviewed supplied f07: the Add to submenu is visible with Lattices highlighted;
that proves the menu opened, not whether its action reached the model. The old
code had no request log. **The exact cause of that recorded click cannot be
established retrospectively.** No claim is made that a failed write was observed.

Confirmed defects in the old path:
- The ed092712 menu owner was inside a conditional geometry-preference overlay.
  Anchor disappearance removed the owner; refreshed anchors also repositioned
  it. The prior latch fixed disappearance but left the toolbar detached.
- Add silently discarded missing window IDs via compactMap. Its error was only
  shown in the selection inspector, not a persistent page-level result line.

Changes:
- Selection actions now occupy a dedicated dock below the filter row, outside
  the canvas. They cannot obscure another tile or depend on a tile anchor.
- Layer uses an AppKit menu snapshot. The tracking loop retains the NSMenu,
  submenu action targets, selected window ID and destination IDs until dismissal.
  SwiftUI/desktop refresh cannot replace an in-flight submenu's action closure.
- Add logs request and outcome, rejects unavailable windows explicitly, shows
  persistence failures above the canvas, and distinguishes already-held windows
  from added ones. Other action errors also appear in that page-level line.

Verification uses the explicitly allowed UI-test alternative, not the real
workspace. Two AppKit tests invoke `NSMenu.performActionForItem(at:)` on the
**actual Add to submenu generated by the production picker**. They do not call
addComposition directly. A selection clear and desktop refresh happen before
activation. The injected persistence boundary uses LayerEditing's pure adding
implementation and writes/reads a unique temporary file; the test asserts the
new pin and the visible success message. A second test checks a write failure
and a window disappearing after the menu opened; both produce visible errors,
and the stale window never reaches persistence.

448 tests executed, 13 skipped, zero failures (20.237s). The dock fixture is
`EditorSlice1LiveEvidence/compose-docked-toolbar.png`. These are fixture/UI-test
results, not a live edit of the user's workspace. Historical root-cause attribution
remains unverified; this change removes the vulnerable menu lifecycle entirely.

Release build passed (213.72s); dev app reinstalled and relaunched (PID 78801).
No live Add/Create/Remove or desktop action was sent by this verification.

Workspace audit caveat: the file changed during this session, before the first
picker test began (13:43:04) and before reinstall/relaunch (13:48). Its mtime is
13:41:43 on October 3; the existing dev app logs show live hotkey activity around
that time. I did not issue a configuration write, and did not revert the change.
Post-launch SHA-256 is
`a61dfc55b02149bf64322f15e308593eefb8b49a331408e16ccc4de1716b121e`,
mtime_ns `1791049303105507831`. Thus I cannot claim the earlier session baseline
is unchanged. The only test persistence above is a unique temporary file.

Logs: `/tmp/lattices-editor-slice-1/compose-picker-action-tests.log`,
`compose-picker-full-tests.log`, `compose-picker-release.log`, and
`compose-picker-install.log`.

## Desktop and new-layer drag pass

This supersedes the earlier statement that a drag never relocates a window:
**desktop chips move windows; layer rows edit membership only.**

### Exact user paths

- Select one layer in Overview's left index. The strip below the scope bar
  lists every display and its desktops, with this layer's window count on each.
  Drag a window tile or list row onto a desktop chip. Command-select several
  first to move the selection. Relocations run serially through the existing
  verified relocation action. One final receipt reports the successful count
  and identifies unavailable windows or failures. Membership is unchanged.
- Drag a tile or selection onto **+ New layer**, pinned below the scrolling
  layer list. The existing sheet opens with those windows and the name field
  focused. Name it, set slots if desired, then Create. Creation and source
  membership removal save as one configuration transaction, using the existing
  removal/ownership rules. A rule-retained source is reported. Cancel saves
  nothing. This does not Gather, activate a layer, or physically move windows.
- From a scoped layer, the new layer takes membership from that source. From
  All windows it takes the dragged windows from their recorded memberships.
- Existing layer rows still add by default; hold Option before mouse-down to
  move from the scoped source. Hover text reflects the captured operation.
- Native AppKit drag sessions start after four points of pointer movement,
  without SwiftUI's drag recognizer. The preview includes the grabbed title and
  multi-selection count. Rows and chips use their entire bounds as targets;
  two-line hover labels do not change row heights or move neighboring targets.

### Verification and acceptance

`drag-desktop-hover.png`, `drag-new-layer-hover.png`, and
`drag-prefilled-sheet.png` in `EditorSlice1LiveEvidence/` are **fixture renders**,
not live interaction evidence. The sheet is staged by the production drop
handler; render callbacks fail if Create is invoked. Persistence tests write
only a unique temporary fixture file. Batch tests cover serialization, the
single receipt, partial failure and overlap rejection; a separate batch test
runs the actual WindowRelocation engine with fake environment callbacks.

Hand acceptance remains: actual mouse-down/drag latency on canvas and list,
Command-selection preservation, Option hover and dropping, name-field focus,
sheet Cancel, and physical relocation across displays/desktops. No real window
was moved and no live layer edit was issued by this verification.

Final checks: app suite **473 tests, 39 conditional skips, zero failures**;
Swift packages **22 tests, zero failures**; CLI **47 passed, one skipped**;
Bun **9 passed**; `bun run check:types` passed. Six new drag behavior tests
passed, and the final three-evidence render test passed separately with
`OVERVIEW_RENDER_DIR` enabled. The earlier full render-enabled suite passed
471 tests with 13 skips before the last two behavior tests were added.
`git diff --check` and the design detector passed.

Logs: `/tmp/lattices-drag-final-tests.log`, `/tmp/lattices-drag-packages.log`,
`/tmp/lattices-drag-bun.log`, `/tmp/lattices-drag-types.log`,
`/tmp/lattices-drag-evidence.log`, and `/tmp/lattices-drag-dev-final.log`.
The system's `swiftly` 6.2.3 pin is missing; verification used Xcode's installed
Swift 6.3.3 via `xcrun`, and dev restart prepended that toolchain to PATH.

Final dev rebuild/install/restart passed using `bin/lattices-build dev:restart`
with `LATTICES_HUDSON_PATH=/Users/arach/dev/hudson`. Running bundle:
`/Users/arach/Applications/dev/Lattices/Lattices.app`, identifier
`dev.lattices.app.dev`, PID 5106. The release app was not rebuilt or relaunched.
The read-only audit before and after these dev launches matched:
workspace SHA-256 `d5c47f68d67ea83f59ffc74d25227b6be2f867b8b3bac659f8abe193388ce95f`,
mtime (seconds) `1791063065`. This is this pass's baseline, not the older
historical baselines above.
