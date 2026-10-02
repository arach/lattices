# Lattices Editor: slice 1 native handoff

## Ownership and baseline

- Branch: `feat/editor-host-slice-1`
- Worktree: `/Users/arach/dev/lattices-editor-host-slice-1`
- Base: `codex/native-workspace` at `91e2e3ab`.
- Only this feature worktree changed. No app launch, desktop action, push or merge.
- Hudson owns the UI and static build. The approved Hudson bundle is now
  imported and hash-verified. Live native acceptance still requires Arach's
  authorization; this build has not been launched or installed.

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
resource bundles, matching existing package/release behavior. No installed app
was rebuilt or replaced by this work.

## Bundle handoff (imported and verified)

Approved Hudson commit: `ada590fddbdff2d50a0f4f0e38d54eef9d111268`.
Source: `/Users/arach/dev/hudson-worktrees/lattices-editor-slice-1/apps/lattices-editor/dist`.
All three copied files match the coordinator-approved SHA-256 values:

| File | SHA-256 |
|---|---|
| `editor.css` | `f47c38467762442d6fb3aa4d5f74bf72a59b70ec2c2076fa04386d63e78c65bb` |
| `editor.js` | `434f3e40a3aadfd8c08cf824fdedadde51d17bf2f2f3bf279d95cda6777c33c3` |
| `index.html` | `73af1bc2c2f6f69c0674176a2ca4f3746cacebab8146ef26f07f307f0dce0e69` |

The Hudson HEAD advanced during import to
`eb075a499ff40a19ba2a1b3188a12a661d19e711` (only a package.json test-script
path correction). The initial HEAD-equality assertion caught that change;
all asset hashes passed. Provenance retains the actual import HEAD and the
approved revision separately; the approved bundle bytes did not change.

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
  `/tmp/lattices-editor-slice-1/build-bundle.log`.
- `swift test --package-path apps/mac --filter 'EditorBridgeTests|LayerMembershipTests'`:
  **51 tests passed, zero failures** (12 Editor, 39 membership).
- Test log: `/tmp/lattices-editor-slice-1/tests-bundle.log`.
- Initial compile exposed a WebKit argument-label mismatch, corrected to
  `callAsyncJavaScript(..., in: nil, in: .page, ...)`; the final test build passes.
- Existing repository deprecation/concurrency warnings remain outside scope.
- No live app, WKWebView rendering, screenshot, tiling, focus or other desktop
  action was exercised. Those checks require Arach's go-ahead.
