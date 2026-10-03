# Layers Act host

Branch: feat/layers-act. Native implementation in progress; no Act web bundle imported.

## Safety boundary

- Page opening, layer selection, view commands, projection and chat never invoke actions.
- Planning is read-only. Confirm requires an opaque, single-use 60-second token bound to source revision and projection snapshot ID. The token is consumed before freshness checking or execution; failures cannot be retried.
- Gather uses the native focus switch with rebound-pin persistence disabled. Ordinary hotkey behavior is unchanged.
- Open launches only the confirmed missing, unambiguous entries. It does not switch, stage, tile or save configuration. Group-only entries without an opening method are omitted.
- Show all is an explicit action.reveal request.
- Undo is now authorized by addendum vo20po. The pure reverse/skip/stack engine exists; native mutation journaling and action.undo bridge integration are still pending. Receipts remain undoable:false until that integration is complete.
- Existing WorkspaceAssistantSession can run local commands and unrestricted tools. The editor instead uses isolated per-layer WorkspaceAssistantSession instances with a tool-free Claude transport: tools empty, MCP empty/strict, slash commands disabled, settings sources empty, hooks disabled, no session persistence, no runtime/Scout fallback. Suggestions are text data; they never execute.
- The live Gather/Open test is prohibited until separately approved.

## Wire

Existing version-1 envelope, correlated replies use request kind plus .result.
Unsolicited action.result and assistant.state events have requestId:null.

- action.plan: {kind:gather|open,layerId,entryIndex?}.
  Reply: {planId,kind,layerId,expiresAt,layoutCount,putAwayCount,displaysLeftAlone:[{id,name}],entries:[{entryIndex,entryKey,method,value,cwd?,description}],explanation,shortcut,warnings}.
  Open has layoutCount:0 and putAwayCount:0. Gather putAwayCount:null when unknown.
- action.confirm: {planId}. action.reveal: {}.
  Reply/event: {actionId,planId,layerId,ok,at,message,label,counts,undoable:false,error?:{code,message}}.
- actions.list: {} -> {actions:[receipts],newestUndoableActionId:null}. Memory only, last 50.
- assistant.send: {layerId,text} -> {}.
- assistant.state: {layerId} -> {layerId,messages:[{id,role,text}],isSending,error,suggestions:[{label,kind,layerId}]}.
  Same payload on assistant.state events.

## Validation so far

- Debug build passed (42.20s), existing deprecation warnings.
- Final native run: 430 tests, 13 skipped, zero failures (20.17s); five new EditorActions tests pass.
- Full output: /tmp/lattices-editor-slice-1/act-final-tests.log.
- Final wire agreement pending. Undo is now in scope; the builder has been asked to agree undo result fields. No commit before agreement.
- No live actions, relaunch, bundle import or new screenshots yet.
- workspace.json SHA-256 unchanged:
  08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc
  mtime_ns: 1790863638274089681.
- KeyboardRemapController unchanged; prior hidutil startup stall remains a separate issue.


## Undo addendum (in progress)

EditorUndo keeps the newest 10 journal entries, rejects out-of-order/replayed undo,
and reverses explicit frame/park/hide records. Frame restoration checks PID,
display and the recorded after frame (3-point tolerance), so moved or closed
windows are skipped. Already-hidden apps are never unhidden. Open uses an empty
move list and reports that opened apps stay open.

This engine is not connected to the live dispatcher yet. Integration must record
mutations at their native call sites, before they occur, including the deferred
LayerStage verification pass; a whole-desktop before/after diff is not sufficient
because it can capture user moves. Undo must reconcile the parked-window ledger
and cancel superseded verification, not merely send AX frame changes.

No real Gather, Open, Reveal or Undo was performed.
