# Lattices Editor: slice 1 native handoff

## Ownership and baseline

- Branch: `feat/editor-host-slice-1`
- Worktree: `/Users/arach/dev/lattices-editor-host-slice-1`
- Base: `codex/native-workspace` at `91e2e3ab`.
- Only this feature worktree changed. No push or merge.
- Hudson owns the UI and static build. The approved Hudson bundle is now
  imported and hash-verified. Authorized dev-app live evidence is recorded in
  EDITOR-SLICE-1-LIVE.md. The release app stays stopped.

## Locked bridge

Canonical contract: Hudson's `docs/proposals/editor-read-bridge-v1.md` in
`/Users/arach/dev/hudson-worktrees/lattices-editor-slice-1`.
Channel: `hudson-editor-spec-20261001`.

- `WKScriptMessageHandlerWithReply` handler `hudsonEditor`.
- Events: `CustomEvent('hudson:host-event', {detail: envelope})`.
- Envelope: `{v:1, requestId, subjectId, revision, kind, payload}`.
- Replies use `<call>.result`; errors use `error` and `{code,message}`.
- Discovery binds `subjectId: workspace-layers`, kind
  `lattices.workspace-layers`, label `Workspace Layers`.
- Four read-only calls: `capabilities`, `subject.read`, `preview.project`,
  `events.subscribe`. There is no generic daemon/RPC forwarding.
- Null revisions are legal for discovery, reads and subscription. Projection
  requires the current revision; stale requests return `stale_revision` with
  the current revision. Successful reads/project replies always have a revision.
- Capabilities remain discoverable with revision null if the initial file is
  unreadable. Subscription still succeeds. Reads return `unavailable`; recovery
  emits `config.changed`. An invalid edit after a good read invalidates at the
  last good revision. An unchanged-content recovery also emits an invalidation.
- Events may precede the subscription reply. Registration precedes capture, and
  the client must install its listener before requesting subscription.
- Exact displayed source: sorted-key pretty JSON of
  `{kind:'workspace-layers',version:1,layers:[...]}`, retaining unknown fields.
- Revision: `sha256:<hex>` of sorted-key compact UTF-8 JSON of that subset.
  Revisions are opaque equality tokens, not clocks.
- Entry key: `sha256:<hex>` of sorted compact `{layerId,content:<raw project>}`.
  Only `layers[].projects[]` is addressed; `match`, `pins`, `saved` remain fields.
- Source ranges are UTF-16 half-open offsets into exact `source.text`. They are
  recorded during emission, not found through substring matching. Duplicate
  entries share a key with every range and `ambiguous:true`; no range is picked.
- Membership is exclusively `LayerMembership.resolve`. Its snapshot-local index
  only retrieves the precomputed layer/content key; it is never wire identity.
- The resolver's groups, companions and process-liveness results are frozen per
  projection. Rebind outcomes are read-only; `keepRebinds` is never called.
- `snapshotId` hashes projected groups and entries, independently of revision.

## Host and packaging

The menu-bar context menu's **Editor…** item opens a dedicated resizable window.
It uses a dark under-page background, persistent WK website storage and a saved
native window frame. Closing removes the reply handler and stops the timer.

`lattices-editor://bundle/index.html` is served by `WKURLSchemeHandler` from
`Bundle.module/Editor`. No localhost port or companion process exists in this
path. The scheme restricts origin/path, resolves symlinks before confinement,
serves GET only, supplies a restrictive CSP and blocks off-origin navigation.
Only the bundled main frame may invoke the handler. Event payloads are passed
as structured JavaScript arguments, never interpolated into executable source.

The subject is read from workspace.json; the adapter has no write API. Inventory
comes from the app's existing DesktopModel cache. A window-scoped 500ms timer
observes config/projection invalidations without a full webview reload. Actual
window-inventory latency also depends on DesktopModel's existing poll interval.

SwiftPM copies the Editor resources. The dev packager now copies SwiftPM
resource bundles, matching existing package/release behavior. The dev app is rebuilt and installed only with Arach’s authorization.

## Bundle handoff (imported and verified)

Approved Hudson commit: `74679b445ae24cae817a3fd98bb9bf91720bc239`.
Source: `/Users/arach/dev/hudson-worktrees/lattices-editor-slice-1/apps/lattices-editor/dist`.
All three copied files match the coordinator-approved SHA-256 values:

| File | SHA-256 |
|---|---|
| `editor.css` | `f47c38467762442d6fb3aa4d5f74bf72a59b70ec2c2076fa04386d63e78c65bb` |
| `editor.js` | `9beb4fb47f3b3acd4e59172138eb93c694f51a1b34f418842b762705ada46250` |
| `index.html` | `73af1bc2c2f6f69c0674176a2ca4f3746cacebab8146ef26f07f307f0dce0e69` |

Hudson HEAD matches the approved revision, with a clean source tree. This
bundle enables Chat, Preview, History and Source in a filled 2×2 default grid,
Terminal hidden, with a one-time saved-layout migration.

Commands run from this worktree:

```sh
bun bin/import-editor-bundle.ts /Users/arach/dev/hudson-worktrees/lattices-editor-slice-1/apps/lattices-editor/dist
swift build --package-path apps/mac
swift test --package-path apps/mac --filter 'EditorBridgeTests|LayerMembershipTests'
```

`Resources/Editor/provenance.json` records the actual import HEAD, clean source
state, approved revision, and exact copied asset hashes. The bundled index now
loads the approved Editor UI, replacing the temporary unavailable placeholder.

## Acceptance evidence

| Acceptance | Status |
|---|---|
| Open Editor; five panels, Terminal hidden, Chat reflow | Native menu/window wired; approved Hudson bundle imported; interactive verification pending |
| Preview agrees with Lattices membership | Same resolver; native projection/pins/Unassigned tests pass; live side-by-side check pending |
| Cross-selection, including duplicates | Content-key/range contract tested with emoji, escapes, nested content, reorders and duplicates; end-to-end UI check pending |
| External assign updates Source/Preview/History in about a second | 500ms invalidation observation implemented and event transitions tested; live timing/flicker check pending |
| Layout persists and narrow widths stack | Persistent WK store configured and Hudson bundle imported; native verification pending |
| Older host displays unavailable, not blank | Native missing-bundle fallback present; older-host client behavior belongs to Hudson |
| No workspace writes or effects | Closed read-only allowlist, unknown mutations rejected before capture; native code has no config-write/effect path |

## Verification

- `swift build --package-path apps/mac`: **passed** after bundle import and provenance update; log in
  `/tmp/lattices-editor-slice-1/grid-build.log`.
- `swift test --package-path apps/mac --filter 'EditorBridgeTests|LayerMembershipTests'`:
  **51 tests passed, zero failures** (12 Editor, 39 membership).
- Test log: `/tmp/lattices-editor-slice-1/grid-tests.log`.
- Initial compile exposed a WebKit argument-label mismatch, corrected to
  `callAsyncJavaScript(..., in: nil, in: .page, ...)`; the final test build passes.
- Existing repository deprecation/concurrency warnings remain outside scope.
- The original build-only acceptance table above is historical. Authorized live
  results, including the new grid regression, are in EDITOR-SLICE-1-LIVE.md.


## Main tier-split integration (October 1)

Merged origin/main `3058abf2` into the feature branch at **0df6b883**.
The only conflict, AppShellView.swift:75–76, keeps `ScreenText.shared` and
`@StateObject private var overview = OverviewModel()`. Removed the obsolete
commandState and selectedStudioLayerId declarations: neither has a remaining
use in the merged file.

Audit of branch-touched native source found one additional bundle dependency:
OverviewModel.swift:245 directly read OcrModel. **549db666** changes it to
`ScreenText.shared.results`. No references to OcrModel, OcrStore,
SpatialLensController, LatticesCompanionBridgeServer, LatticesDeckHost or
DeckActionRequest remain in branch-touched native source. Existing
CompanionAppsMenu is a core product-family menu, not the bundle Companion host.

Build environment was resolved with `bin/lattices-build-env.ts shell`:
default bundle yields LATTICES_BUNDLE=1; LATTICES_TIER=free yields
LATTICES_BUNDLE=0. Both retain the manifest's voice feature.

- Default bundle Swift build: passed (98.77s).
- Free Swift build: passed (73.09s), build only; not installed.
- Full bundle Swift test suite: 365 executed, 13 skipped, zero failures
  (352 non-skipped passes).
- Logs: /tmp/lattices-editor-slice-1/tier-{bundle-build,free-build,tests}.log.
- A preliminary compile was discarded after the Overview source was corrected
  while it was compiling; the reported builds were rerun on the fixed tree.
- Dev bundle reinstall and screenshot evidence: EDITOR-SLICE-1-LIVE.md.


## Approved design refresh (October 2)

Hudson 064386a68599ef7815928518a25d89fc50aa8468, clean source import. The importer now explicitly
includes the bundled JetBrains Mono WOFF2 and its license. SwiftPM copies the
whole Editor directory. CSS uses the sibling URL
`./jetbrains-mono-latin-400-normal.woff2`; the existing scheme handler serves
WOFF2 as font/woff2 and CSP permits self fonts.

- index.html: de8f487e24e1b0488743fb798cad73d33fccad6c2e2f9675bec9612c79e417cc
- editor.js: b3a550368c7aea87dd7439b7d9587a353fd87c1aa0ac7abd7f2dc9b5afb86042
- editor.css: 29169eafdc1c975e92415ad93ffb5636a495f3146dd707eeeb7362d95d6cdb51
- jetbrains-mono-LICENSE.txt: 403581b69dac5cff4079205e01c6b467e56af449ecbd7247693ddb1baafa005b
- jetbrains-mono-latin-400-normal.woff2: 14425ba9c695763c1547f48a206b7aa60350a33ae23de09f0407877f3fcd89eb

All five copied hashes match the approved values. Design live evidence is in
EDITOR-SLICE-1-LIVE.md.


## Layers shell integration (native, October 2)

The standalone Editor window is removed. The compatibility
EditorWindowController.show() entry point now selects AppPage.layers in the
main app window. The menu item is Layers…; lattices://editor keeps working.

Layers appears after Overview in Workspace. A process-retained LayersPageModel
owns one EditorWebHost/WKWebView, created and loaded only on first visit.
Switching pages detaches/reattaches the same web view without reloading it.
Its under-page color and the SwiftUI host background are Palette.bg.

PageAction adds optional menu items and selected state. Appearance remains in
PageActionButton; the shell falls back to icon controls when the header is narrow.
Layers publishes Arrangement, Panels and Inspect source. Search remains the
shell action, and the existing three-slot status bar is unchanged.

Hosted capabilities advertises chrome:"host" and ui.state. UI state validates
known arrangements/panels and source visibility, acknowledges with
ui.state.result payload {}, and never captures or writes the workspace.
Commands use the standard v1 hudson:host-event envelope, kind ui.command, and
the approved payload shapes. Controls remain disabled until initial ui.state,
so commands cannot be sent before the web layout is ready. Selected states
come only from the web's reported state, not optimistic native toggles.

Native bundle build passed; 54 targeted tests passed, including hosted
capabilities, valid/invalid UI state, no capture for UI-only calls, command
allowlist/envelopes, navigation order and action selected-state equality.
The external design canvas could not be fetched; implementation follows the
explicit version-7 requirements in the coordinator's message.

No new web bundle imported yet. Integration screenshots and dev relaunch wait
for the Hudson builder's approved commit and hashes.


### Hosted bundle imported

Approved on hudson-editor-spec-20261001: Hudson b3dfd98f7a0d182bcf78ce4eed5fc59cfbda91e5.
All five copied hashes match approval; provenance records the clean source.

- editor.css: c3da4864461752e8e47563d00863f42e6ab4fa5fb19e9a56acc8f57170fc8dc8
- editor.js: 54a1a1eec8928b11efc245bf03f74c3bbaf6841eb73433db52e7ff39ec12f85f
- index.html: f8959618fcd68f274db3a9f718dcc1c495855e6a5bc0859944f2c31a06b0a83a
- jetbrains-mono-LICENSE.txt: 403581b69dac5cff4079205e01c6b467e56af449ecbd7247693ddb1baafa005b
- jetbrains-mono-latin-400-normal.woff2: 14425ba9c695763c1547f48a206b7aa60350a33ae23de09f0407877f3fcd89eb


### Shell acceptance completed

See EDITOR-SLICE-1-LIVE.md for installed 683e871b and screenshot evidence.
Page switching retains selection and layout; native commands and checked menus
work. Both 800px and 600px shell widths show the responsive web composition.
Header controls compact using root-window geometry. The standard status slots
keep their identities and scale widths with the window instead of forcing a
632px content minimum. Wide status sizing is unchanged.

The latest targeted suite has 54 passes; full integration suite had
368 executed / 13 skipped / zero failures. Final dev production build passed.
workspace.json hash and mtime remained identical.
