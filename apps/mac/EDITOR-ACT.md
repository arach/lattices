# Layers Act host

Branch: feat/layers-act. Hudson Act bundle 8614115c imported; all six approved SHA-256 values match provenance.json.

## Safety boundary

- Page opening, layer selection, view commands, projection and chat never invoke actions.
- Planning is read-only. Confirm requires an opaque, single-use 60-second token bound to source revision and projection snapshot ID. The token is consumed before freshness checking or execution; failures cannot be retried.
- Gather uses the native focus switch with rebound-pin persistence disabled. Ordinary hotkey behavior is unchanged.
- Open launches only the confirmed missing, unambiguous entries. It does not switch, stage, tile or save configuration. Group-only entries without an opening method are omitted.
- Show all is an explicit action.reveal request.
- action.undo is advertised with the production journal. Gather records native layout/tile, park/restore and hide mutations before AX writes, then records actual frame readback. Open is launch-only and its empty move list is undoable without closing anything. Reveal remains the restore-only escape hatch, not an inverse that would put windows away.
- Existing WorkspaceAssistantSession can run local commands and unrestricted tools. The editor instead uses isolated per-layer WorkspaceAssistantSession instances with a tool-free Claude transport: tools empty, MCP empty/strict, slash commands disabled, settings sources empty, hooks disabled, no session persistence, no runtime/Scout fallback. Suggestions are text data; they never execute.
- The live Gather/Open test is prohibited until separately approved.

## Wire

See EDITOR-ACT-WIRE.md, the approved frozen v1 contract.

## Validation so far

- Debug build passed (42.20s), existing deprecation warnings.
- Final native run: 436 tests, 13 skipped, zero failures (16.91s).
- Full output: /tmp/lattices-editor-slice-1/act-journal-full.log.
- Frozen contract approved by coordinator; initial native/contract commit 4681e54c.
- No live Gather, Open or Undo. Dev relaunch and confirmation/chat screenshots completed; see EDITOR-SLICE-1-LIVE.md.
- workspace.json SHA-256 unchanged:
  08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc
  mtime_ns: 1790863638274089681.
- KeyboardRemapController unchanged; prior hidutil startup stall remains a separate issue.


## Mutation journal

The journal is scoped to explicit action execution. WindowTiler's resolved layout
batch and batch frame writes, plus LayerStage park/restore calls, capture the AX
frame before writing and read back the frame afterward. Missing before geometry
fails closed for that move. No whole-desktop diff is used.

The deferred LayerStage verification carries the same journal. Undo seals it so
an outstanding verification cannot repark a window after restoration. Successful
restores reconcile only that window's parking ledger; skipped user-moved windows
are not moved. The journal preserves a window's pre-existing parked record.

The last 10 original actions form a stack. Out-of-order and replayed undo fail.
Open has no window moves: its undo keeps opened apps open. Layout/tile moves
within Gather use the same instrumented WindowTiler path. No separate Tile
bridge method was added to the frozen contract.

Validation is automated/injected only for mutations. The first real action run
remains with the user.
