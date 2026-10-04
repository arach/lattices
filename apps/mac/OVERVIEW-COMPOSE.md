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

## Direct screen drops, movable toolbar, and display pin/hide

### Exact user paths

- Drag a tile, tray row, or All windows row directly onto any ordinary desktop
  thumbnail. The whole thumbnail accepts the selection, not just a chip in the
  layer-scoped strip. One batch receipt reports the outcome.
- Drag onto a large display map to move **and** place in one verified relocation.
  The top fifth previews Full; the middle previews left/right halves; the bottom
  previews left/middle/right thirds. The green rectangle is the same normalized
  PlacementSpec geometry used for execution. The hover label names the desktop
  and placement. Compact pinned-column maps are targets too.
- A large-map drop on a last-known desktop does not require Back to live. The
  existing runtime verifies destination membership and geometry, then the app
  requests and verifies switching to that desktop. A switch failure explicitly
  says that placement happened but the desktop could not be shown. Full-screen
  Spaces, unavailable windows, hidden apps, and stale destinations report why
  they cannot accept the operation. Thumbnail-only moves do not switch views.
- Select a window: its action toolbar defaults to the reserved strip beneath
  the display maps and above the tray. Drag the left grip to reposition it
  anywhere within Overview. Double-click the grip to reset. The toolbar is
  clamped to the visible area, horizontally scrolls when needed, and remembers
  positions by content size, with a clamped last-position fallback on resize.
- Click a display header's pin to give it the main area, with other displays
  stacked in a compact column. Click again to unpin. Click the crossed-out eye
  to hide a display; click its `Display name · hidden` chip to restore it.
  Pinning a hidden display restores it; hiding the pinned display unpins it.
  These choices and toolbar positions use UserDefaults only, never workspace.json.

### Drag-source diagnosis and regression

A hosted native row test reproduced the previous drag failure before changing
its hit logic. The native source's parent was an AppKitPlatformViewHost, while
SwiftUI hit-testing returned the containing NSHostingView. The old descendant
check rejected mouse-down, leaving the payload nil. The diagnostic failure is
in `/tmp/lattices-desk-source-trace.log`; the same test passes after the fix in
`/tmp/lattices-desk-source-verify.log`. The source now resolves the frontmost
visible drag source in AppKit view order, rather than requiring the hosting
view to be a descendant of its background wrapper. Floating controls have a
transparent drag shield so they cannot arm a tile behind them. Tests cover
source arming, overlapping sources, shields, and hidden source rejection.

No real desktop/window mutation was used for diagnosis. Full native pointer
tracking still needs hand acceptance; these are event/hosted-view regressions,
not evidence of a successful live drag.

### Evidence

Fixture screenshots (not live desktop edits):
- `EditorSlice1LiveEvidence/desk-screen-snap-hover.png`
- `EditorSlice1LiveEvidence/desk-toolbar-strip.png`
- `EditorSlice1LiveEvidence/desk-pinned-display.png`
- `EditorSlice1LiveEvidence/desk-hidden-display.png`

Tests cover snap zones and canonical placement geometry, current/last-known
screen drops through WindowRelocation environment fakes, foreign payload
rejection, toolbar clamping, per-size keys, and pin/hide persistence in unique
UserDefaults suites. Existing no-shift pixel tests now sample only the map
region, excluding the newly reserved toolbar strip, and pass with selection
and error state changes.

Final verification: **480 app tests, 13 conditional skips, zero failures** with
all Overview fixture renders enabled; **22 Swift package tests passed**;
`bun run test` passed (47 CLI tests, one skip; 9 Bun tests); `check:types` passed.
The design scan and `git diff --check` are clean. Logs are
`/tmp/lattices-desk-final-tests.log`, `/tmp/lattices-desk-packages.log`,
`/tmp/lattices-desk-bun.log`, `/tmp/lattices-desk-types.log`, and
`/tmp/lattices-desk-dev-final.log`.

Remaining hand acceptance: actual pointer drags from all three sources,
multi-selection, hovering and dropping on ordinary and compact maps, last-known
desktop switching/placement, toolbar grip/reset/resize, and persisted pin/hide
choices after app restart. No live window relocation or workspace edit was
issued during these tests.

Dev build/install/restart passed with `LATTICES_HUDSON_PATH=/Users/arach/dev/hudson`
and Xcode's Swift toolchain on PATH. Running dev bundle is
`/Users/arach/Applications/dev/Lattices/Lattices.app`, `dev.lattices.app.dev`,
PID 58000. The release app was not rebuilt or relaunched. The workspace file's
SHA-256 and mtime remain the pre-launch values:
`d5c47f68d67ea83f59ffc74d25227b6be2f867b8b3bac659f8abe193388ce95f`,
`1791063065` seconds.

## Native drop delivery and text/tray follow-up

### Confirmed missing-drop cause

The prior fix covered drag **arming**, not delivery. A real CGEvent sequence in
an isolated dev-app fixture reproduced four failures: screen, thumbnail, layer
row, and New layer all started native drags and ended with operation 0; no
SwiftUI drop callback ran. Instrumentation showed SwiftUI's native destination
views registered for `public.data,public.item`, while the NSPasteboardItem
advertised only two **undeclared custom UTIs**. They had no public.data
conformance, so AppKit never delivered them to SwiftUI. This was not payload
visibility or a hidden drop surface.

Both UTIs now explicitly conform to public.data at runtime and are exported
in the source, dev-build, and package-build Info.plists. The same real input
then reached the production handlers, decoded the session-bound payload, and
completed all four fixture operations. Only temporary fixture membership was
saved; physical placement ran through WindowRelocation environment fakes.
`EditorSlice1LiveEvidence/drop-input-before.log` and `drop-input-after.log`
retain the protocol trace; `drop-input-result.json` records the four assertions.

Re-run with `scripts/test-overview-drag.sh`. It quits the dev app, launches its
isolated fixture, posts CGEvent down/drag/up to the actual window, asserts all
four outcomes, and prints the temporary evidence directory. It requires the
**dev app's** existing event-posting permission and never requests or changes
permissions. `--debug` additionally builds/installs a signed debug executable
and synchronizes its UTI declarations. Use `bin/lattices-build dev:restart`
after that diagnostic mode to restore the normal dev build. The default test
mode does not rebuild or re-sign anything. Reopen the dev app after testing.
The fixture starts before the live daemon/inventory, uses fake window IDs and
a unique defaults suite, writes only below its dedicated /private/tmp folder,
and blocks sheet Create from reaching production persistence.

The preview frame now preserves the relative grab point: grabbing the middle
puts the cursor at the preview's middle, not its bottom-left corner. Tests cover
center and off-center grabs.

### Text audit and tray changes

The concrete readability problems were 8–10pt JetBrains Mono used for ordinary
UI text, low-contrast ink multiplied by whole-map/tile/row opacity, and fractional
map/text origins. Overview also had a sidebar compositing boundary. There was
**no text scaleEffect or drawingGroup**, and the dot texture is a background,
not an overlay over the glyphs. No GPU rasterization defect was established.

UI text now uses integer-size SF Pro; section labels/data use JetBrains Mono.
Map rectangles and toolbar positions align to whole points, layout no longer
centers map groups at fractional origins, whole text-container dimming and the
sidebar compositing boundary are removed, and muted titles keep one foreground
color instead of compounded opacity. The AppKit Layer picker also uses SF Pro.

Tray columns share integer widths, 12pt insets, 18pt section headers, and 32pt
rows. Each row starts with an 18pt NSWorkspace app icon (generic fallback only
when the app cannot be resolved), followed by SF Pro 13 medium app name and a
muted SF Pro 12 title. Source selection and dragging are unchanged.

`tray-before/after-1x/2x.png` and `crisp-before/after-1x/2x.png` are fixture
comparisons in EditorSlice1LiveEvidence. The tray evidence test uses
a native NSHostingView with explicit window backing, layer contents, and
SwiftUI display scales of 1 and 2, including its NSScrollView-backed rows.
ImageRenderer alone omits those native scrolling contents and is not used. These are fixture
renders, not claims of testing every physical monitor's display settings.

Validation: **484 app tests, 13 conditional skips, zero failures**, including
all fixture renders; **22 Swift package tests passed**; `bun run test` passed
(47 CLI tests, one skip; 9 Bun tests); `bun run check:types` passed. Plist and
shell syntax checks, `git diff --check`, and the UI design scan passed. The
fixture's own CGEvent input test is separate from the Swift test suite; it
asserts actual handler delivery, not direct model calls.

Logs: `/tmp/lattices-drop-final-tests.log`, `/tmp/lattices-drop-packages.log`,
`/tmp/lattices-drop-bun.log`, `/tmp/lattices-drop-types.log`,
`/tmp/lattices-drop-input-registration.log`, `/tmp/lattices-drop-input-final.log`,
`/tmp/lattices-drop-dev-final.log`, and `/tmp/lattices-drop-shipped-input.log`.
Remaining hand acceptance: preview attachment feel at arbitrary grab points,
real-window relocation (intentionally not exercised), and text appearance on
the user's physical 1x/2x displays. Input delivery to all four target kinds is
now automated and verified rather than left entirely to hand acceptance.

The final installed dev build passed the **same four CGEvent-driven drop
assertions again**, without a debug executable substitution. The checked-in
result/after trace are from that installed build. Dev build/install/restart
passed; the ordinary dev app was reopened afterward with this checkout's CLI
root. Bundle: `/Users/arach/Applications/dev/Lattices/Lattices.app`, identifier
`dev.lattices.app.dev`. No release bundle was rebuilt or launched.
Workspace SHA-256 and mtime stayed unchanged across the input runs and launches:
`d5c47f68d67ea83f59ffc74d25227b6be2f867b8b3bac659f8abe193388ce95f`,
`1791063065` seconds.

## Same-display Space carry pass (October 4, 2026)

### Changes and diagnosed behavior

Same-display ordinary-desktop relocation now calls `WindowSpaceCarry` directly,
not CGS followed by carry. This is shared by Overview drops, Move menus, and
context menus through `ActionRuntime.executeWindowMove`. Cross-display staging
retains its existing relocation/rollback contract. The gate was already
recursive; no lock bug was found or changed.

Production logging now records native drag arming/end, provider delivery,
destination and payload, rejected drops, relocation source/target/method, and
verified outcome or failure in `~/.lattices/lattices.log`. Previously the drop
logs existed only inside the isolated fixture, so their absence from the live
log did not prove no drop handler ran.

A bounded live input run reproduced `Mission Control didn't open`: the move
started inside SwiftUI's drop callback, before AppKit ended the originating
native drag. Relocation now reserves its selection and shows progress
immediately, but waits for `draggingSession(...endedAt:)` and the next main-loop
turn before starting Mission Control. Its launch is also dispatched on main.
A regression test asserts the action cannot start inside the drop or native
end callback. The subsequent live attempt opened Mission Control and moved
outbound successfully. These two scheduling changes were validated together;
no claim is made that either was independently sufficient.

Progress says `Moving to Desktop N…`. A single success names the app; a failure
shows the actual reason. Menus use the same progress/result state. Batch moves
still serialize. A screen-map placement no longer switches to the destination
Desktop afterward: carry restores the viewed Desktop, and the model preserves
its browsing scope.

### Bounded live acceptance: PARTIAL, not complete

Only newly created, uniquely named TextEdit test documents were eligible for
live actions. The dev-only `--overview-carry-live <temporary-document-path>`
probe hosts the real Overview drag source and destinations, posts real CGEvent
input, uses production LiveOverviewActions, and guards every action by the
exact test window ID, PID, main display and the two allowed Spaces. It starts
before normal app services and never enables layer persistence. A single
read-only DesktopModel sweep supplies runtime target resolution.

There were three input runs: an inventory-preflight failure before any carry;
a carry attempt that failed to open Mission Control; and the final outbound /
return run. An earlier setup launch rejected `/tmp` path canonicalization
before posting any input. No further input or carry retries were made.

Final input run, window **212290**, main display **2**:

- Thumbnail drop: Space **4 → 5** (Desktop **3 → 4**) **verified success**.
  Mission Control opened; window membership was `[5]`; all three display views
  matched their starting Spaces `[4, 2326, 2377]` afterward.
- Big-map drop back: Space **5 → 4**, with left-half placement, **failed**.
  Mission Control opened, but the carry did not take. Membership remained `[5]`;
  the relocation reported source-staging failure and unchanged original frame
  and desktop. The viewed Spaces were restored. No success was fabricated.
- The exact test document was closed. A later post-cleanup readback found main
  view 3 rather than 4; it was explicitly restored to 4, without moving a
  window. Final readback confirmed all original views `[4, 2326, 2377]` and no
  remaining test windows. The other two displays required no restoration.

**Remaining blocker:** carry from an inactive source Desktop was not reliable
in the return test. It needs another explicitly authorized live diagnostic
pass; this change must not be described as a fully working round trip. The
original user's exact failed attempt also cannot be reconstructed from the
old, uninstrumented drop log.

Durable evidence: `EditorSlice1LiveEvidence/carry/` contains input and relocation
traces, JSON results (intentionally `passed: false`), setup/failure evidence,
cleanup readback, view restoration, and the exact one-off command used.
`live-run-command.sh` is evidence, **not** part of the test suite or permission
to rerun live movement. Do not run it without fresh authorization.

Validation: **487 app tests, 13 skipped, zero failures**, including fixture
renders; **22 Swift package tests passed**; `bun run test` passed (47 CLI tests,
one skip; 9 Bun tests), and `bun run check:types` passed. App test log:
`/tmp/lattices-carry-tests-final.log`; other logs:
`/tmp/lattices-carry-packages.log`, `/tmp/lattices-carry-bun.log`, and
`/tmp/lattices-carry-types.log`. The isolated fake-window CGEvent test also
passed all four targets before the carry changes; final-build check follows.

Workspace SHA-256 remains
`d5c47f68d67ea83f59ffc74d25227b6be2f867b8b3bac659f8abe193388ce95f`.

Final dev build/install/restart passed (`/tmp/lattices-carry-dev-build.log`).
The installed optimized dev app passed all four fake-window CGEvent drop
assertions again (`carry/shipped-fixture-input.log`). This does **not** supersede
the partial live result above. The ordinary dev app was reopened with this
checkout's explicit CLI root; no release app was rebuilt or launched. Final
view readback is `carry/final-view-readback.log`; no test TextEdit documents
remain. Workspace mtime remains `1791063065` and the hash above is unchanged.

## Return carry and active-first monitors (October 4, 2026)

### Return carry: closed out by a verified round trip

The previous carry accepted the first Spaces-bar frame with nonnegative Y.
That is an animation-start test, not a settled-target test. WindowManager's AX
position changes in **both axes** as the bar expands. The captured Desktop 3
button starts at `(1673, -33)` and settles at `(1597, 102)` during a drag;
hover-only expansion puts it at `(1473, 102)`. AXSize remains the label's size,
so adding half that size is not a valid way to find the drop point either.
The desktop index stayed correct; cached/in-flight target geometry was unsafe,
particularly for a leftward return. Earlier logs did not record the exact
failed drop coordinate, so they cannot prove which intermediate point it hit.

Carry now reacquires the live Spaces bar, validates its count, and waits until
the target frame is stable for 200ms (and expansion has had at least 350ms)
before dragging to its AXPosition. It also resolves the actual source AX
thumbnail by bundle, source Space and title, rather than relying on a cached
CG frame. Duplicate app/title candidates require a unique geometry match;
otherwise the move fails safely instead of picking another window. Both
source and target geometry are logged. The fix was verified as a whole, not
as separate experiments for each safeguard.

There were exactly **three real-input runs** in this pass. The first two never
armed a native drag or reached relocation. A separate fake-window input trace
caught an extra, unrelated mouse-down, and the live probe now records input
window identity and source hit-testing. Two read-only Mission Control
inspections captured the collapsed/expanded AX tree; they did not drag windows.
No further live carry runs were used after the successful third run.

Final live test: newly created TextEdit document **`lattices-carry-test`**,
window **212872**, main display **2**:

- Real CGEvent thumbnail drop **Space 4 → 5** / Desktop 3 → 4: verified `[5]`.
- Real CGEvent big-map drop **Space 5 → 4**, left half: verified `[4]` and frame.
- Mission Control appeared in both directions. The three displays were back
  on `[4, 2326, 2377]` after each completion. The test document was closed.
- The JSON result is `passed: true`. This supersedes the partial result in the
  previous section. No test operated on an existing user document.

Evidence is in `EditorSlice1LiveEvidence/return-carry/`: native input trace,
relocation outcomes, JSON verification, and redacted AX trees. Unrelated app
window titles were omitted from the committed AX evidence. This live test used
an isolated host for the production Overview drag source/drop handlers and
LiveOverviewActions; it is not a claim of exhaustive Mission Control coverage.

### Active-first, aspect-fitted layout

`OverviewMonitorLayout` is a pure layout planner. It uses the canvas space
already allocated above the toolbar and tray; it does not measure the views it
just laid out. One monitor gets the whole aspect-fitted room. Two go side by
side in a wide room and stack in a tall one. Three or more give the pinned/main
monitor the lead map and evaluate both a secondary column and a secondary row,
choosing the greatest drawn map area. The lead stays larger than each secondary
map. Actual aspect-fitted bounds are packed together with aligned headers and
16pt gaps, not centered separately in oversized allocation cells.

Off, asleep, mirrored, and empty-current-desktop displays collapse to labeled
chips. Activity comes from the unfiltered window snapshot, not the selected
layer, search, or browsed Desktop. Clicking a chip explicitly restores it.
Manual hide wins over automatic activity; pin and explicit restore win over
automatic collapse. The new optional `revealed` preference decodes old v1
preferences without losing existing pin/hide settings. These choices use only
UserDefaults, not workspace.json.

Live screen state comes from CoreGraphics plus NSScreen. Online mirrored or
sleeping displays absent from NSScreen are included. A disconnected display
already seen by this model remains as an off chip with its name and identity;
a device entirely unknown to the running app cannot be discovered while it is
disconnected. Stable display IDs keep views from being replaced when NSScreen
indices change. Screen, sleep/wake, active-Space, and window notifications share
one 200ms debounce. Activity and screen state are sampled together. A fixed
chip-row reservation prevents collapse from first resizing the canvas and then
reflowing it again. One short 180ms animation follows the resulting plan; Reduce
Motion and native dragging disable it.

Nine `monitors-*.png` fixtures cover one/two/three monitors, wide/tall canvases,
one off, restored-off and a different pinned lead. They were inspected in one
batch, internal aspect-fit gutters were packed in one correction, and the
confirmation batch was inspected. Toolbar/tray remain clear. Physical monitor
power cycling was not performed; topology/activity behavior is covered with
fixtures and pure unit tests.

Validation: **495 app tests, 13 skipped, zero failures** (including all fixture
renders); **22 Swift package tests passed**; `bun run test` passed (47 CLI tests,
one skip, 9 Bun tests); `bun run check:types` passed. New tests cover layout
choice and bounds/aspects, main/pin ordering, inactive reasons and overrides,
old preference decoding, disconnect/reconnect identity, scope-independent
activity, and rejecting unsettled leftward targets / ambiguous thumbnails.
Logs: `/tmp/lattices-monitors-tests-final.log`,
`/tmp/lattices-monitors-packages.log`, `/tmp/lattices-monitors-bun.log`,
`/tmp/lattices-monitors-types.log`, and `/tmp/lattices-return-run3.log`.

Final optimized dev build/install/restart passed
(`/tmp/lattices-monitors-dev-build.log`). The installed app passed all four
fake-window CGEvent drop assertions with the new layout
(`return-carry/shipped-fixture-input.log`). It was reopened normally with this
checkout's explicit CLI root; bundle ID remains `dev.lattices.app.dev`. No
release app was rebuilt or launched. Final readback confirms original display
views `[4, 2326, 2377]` and zero remaining test windows
(`return-carry/final-view-readback.log`). Workspace hash and mtime remain
`d5c47f68d67ea83f59ffc74d25227b6be2f867b8b3bac659f8abe193388ce95f` and
`1791063065` respectively. No workspace.json write, push, merge or PR.

## Gesture entry-point follow-up: drop delivery fixed, return carry still fails

**Partial completion. Do not report desktop dragging as fully fixed.** The
three-run live limit is exhausted. The earlier isolated-window round trip
does not establish reliable return carry on the user's surface.

### Surface and diagnosis

The middle-button action calls
`ScreenMapWindowController.shared.showScreenMapOverview()`. This opens
`AppShellView` in a `NoFocusRingWindow` at level 0, not a high-level overlay
panel. Both input probes now call that exact entry point and use its shell,
window factory, layout, and chrome. They inject restricted model data/actions;
they do not start normal inventory timers, the daemon, or workspace persistence.
The live probe still restricts actions to its own TextEdit window.

The baseline native-drag run on this host accepted both destinations. Thus the
reported native `operation=0` failure was not reproduced with restricted data.
It remains incorrect to attribute that failure to a nonactivating panel.

A separate hit-testing error was reproduced. `NSView.visibleRect` can extend
outside a SwiftUI representable's bounds. A target whose window rectangle was
`(1039,357,84,72)` was treated as hit at `(919,161)`. The existing source picker
used the same visibleRect-only test, so it could arm a window outside its tile.
Source and destination hit tests now intersect visibleRect with bounds.

### Implemented input changes

Overview's own pointer drags no longer depend on native drop registration.
A router owns the down/drag/up sequence and resolves explicit target views in
paint order. It carries the frozen payload, shows a nonactivating preview,
updates highlights, and dispatches one release. Escape, app deactivation, and
release without a visible target cancel it. A terminal release guard prevents
a second dispatch. Floating controls shield targets behind them.

Main maps, Desktop thumbnails, layer rows, the layer Desktop strip, and
composition slots use this route. Existing item-provider drop handlers remain
for their callers. Mission Control starts asynchronously after the pointer
router removes its preview and releases input.

Production logs include source/window identity, target enter/exit, validation,
perform, and rejection reasons. Native validation is no longer suppressed.
The fake-window CGEvent probe uses the same gesture entry point and checks six
cases: map, thumbnail, layer, new layer, Escape, and no target. Positive cases
must decode once and produce one receipt; cancellation must produce none.

### Live results and remaining failure

Exactly three live runs moved only newly created `lattices-carry-test`
documents on the main display. Initial views were `[3,2326,2377]`.

| Run | Transport | Thumbnail 3 → 4 | Main map 4 → 3 |
| --- | --- | --- | --- |
| 1 | Native baseline, real shell | Verified | Drop accepted; carry reported Space 2736 instead of 3 |
| 2 | Pointer router | Verified | Dispatched once; carry reported Space 2749 instead of 3 |
| 3 | Pointer router | Verified | Dispatched once; carry reported Space 2754 instead of 3 |

The return destination was Desktop 2, Space ID 3. The failure is now downstream
of input delivery: `WindowSpaceCarry` / source staging, not a missing target.
Re-resolving the Mission Control button after hover and waiting longer for the
requested Space did not fix it. Those experimental backend changes were
reverted; this commit does not claim a carry-backend fix.

Each test document was closed. Final cleanup readback showed no test windows
and the original views. Raw traces and failed JSON results are preserved in
`EditorSlice1LiveEvidence/gesture-carry/`. Unredacted Mission Control screenshots
remain only in `/private/tmp/lattices-carry-live.0MqHNh/`; they are not committed.
Further live investigation requires another explicitly authorized run budget.

Validation: 498 app tests, 13 skipped, zero failures with render fixtures;
22 Swift package tests passed; 47 CLI tests passed with one skip; 9 Bun tests
passed; TypeScript checks passed. The render runner first failed because its
output directory did not exist; creating that directory resolved the harness
failure without a code change. The six-case debug input probe passed on the
real shell. Tests cover bounded source/target hit regions, hidden targets,
terminal release/cancellation, and deferred relocation after pointer release.
Logs: `/tmp/lattices-pointer-render-tests-final.log`,
`/tmp/lattices-pointer-packages.log`, `/tmp/lattices-pointer-bun.log`,
`/tmp/lattices-pointer-types.log`, `/tmp/lattices-pointer-six-input.log`.

The optimized dev app was rebuilt and installed successfully
(`/tmp/lattices-pointer-dev-build.log`). Its six-case input probe passed
(`gesture-carry/shipped-fixture-input.log`). The first optimized probe received
extra pointer events, including a release before its planned endpoint and extra
mouse-downs; it failed new-layer and Escape checks. That trace is retained as
`shipped-fixture-interrupted.log`. The repeat passed all six cases. This does
not establish that input interference caused the separate live carry failures.

A final read-only Space catalog places IDs 2736, 2749, and 2754 on the Action
virtual display, not the main display. Cleanup did not issue virtual-display Space-management
commands. Further investigation should record actual pointer
positions and input-event provenance around Mission Control release, in
addition to intended coordinates. Do not infer a fix from the intended drop
point alone.

The dev app was reopened normally with this checkout's explicit CLI root.
`gesture-carry/final-readback.log` confirms views `[3,2326,2377]`, zero test
windows, unchanged workspace hash/mtime, and the running dev process. No
release app build, workspace write, push, merge, or PR was performed.
