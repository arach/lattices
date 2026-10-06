# Layers Act wire — frozen v1

Existing v1 envelope. Correlated replies always use `<request kind>.result`.
Action replies contain the terminal ActionResult (not an acknowledgement).
The same result is emitted as `action.result` with `requestId:null`; deduplicate
by actionId. Assistant events likewise have requestId:null.

```ts
type Counts = { laidOut?: number; putAway?: number; opened?: number;
                restored?: number; skipped?: number };
type ActionResult = {
  actionId: string;
  planId: string | null;
  kind: 'gather' | 'open' | 'reveal' | 'undo';
  layerId: string | null;
  ok: boolean;
  at: string; // ISO-8601 UTC
  message: string; // host-authored, including partial failures
  counts: Counts;
  undoable: boolean;
  undoOfActionId?: string; // undo only
  reasons?: string[];
  error?: { code: string; message: string };
};
type Plan = {
  planId: string;
  kind: 'gather' | 'open';
  layerId: string;
  layerName: string;
  expiresAt: string;
  layoutCount: number;
  putAwayCount: number | null;
  displaysLeftAlone: { id: string; name: string }[];
  entries: { entryIndex: number; entryKey: string; app: string | null;
    method: 'url' | 'app' | 'command'; value: string; cwd?: string;
    description: string }[];
  explanation: string;
  shortcut: string | null;
  warnings: string[];
};
type History = {
  actions: { actionId: string; label: string; at: string;
    counts: Counts; undoable: boolean }[];
  newestUndoableActionId: string | null;
};
type AssistantState = {
  layerId: string | null;
  messages: { id: string; role: 'system' | 'user' | 'assistant'; text: string;
    readRules?: number; readWindows?: number }[];
  isSending: boolean;
  error: string | null;
  suggestions: { label: string; kind: 'gather' | 'open'; layerId: string;
    entryIndex?: number }[];
};
```

| Request | Payload | Correlated result payload |
|---|---|---|
| action.plan | {kind:'gather'\|'open',layerId,entryIndex?} | Plan |
| action.confirm | {planId} | ActionResult |
| action.reveal | {} | ActionResult |
| action.undo | {actionId} | ActionResult |
| actions.list | {} | History |
| assistant.send | {layerId,text} | {} |
| assistant.state | {layerId} | AssistantState |

Capabilities enumerate supported methods; do not show Undo until action.undo is
advertised. IDs are strings; entryIndex is a zero-based integer in layers[].projects.
Plans bind the exact source revision and snapshotId, expire after 60 seconds,
and are single-use (consumed before freshness checks/execution). No stale retry.
Cancel/outside/Escape never confirms. Planning requires an explicit action button;
only a second explicit confirmation invokes Gather/Open.

Gather uses native focus without config persistence. Open is launch-only:
layoutCount=0, putAwayCount=0; it starts only the listed missing entries.
Unknown Gather putAwayCount is null. Counts in results describe observed outcomes;
omit unavailable counts rather than inventing zero/success. Launch requests alone
must not be reported as confirmed opened windows in counts.opened.

History is newest-first, last 10 original actions, not undo receipts. Only
newestUndoableActionId can be undone. Undo is single-use, reverses recorded moves,
and skips closed or subsequently moved windows. Partial skips return ok:true
with restored/skipped counts and reasons. Invalid ordering returns ok:false,
error.code=undo_order, without effects. Undo results have undoable:false and
undoOfActionId. Open undo never closes/quits; message includes
“Opened apps stay open”. Refresh history after action results.

No extra projection launch metadata is required in this pass. Web may display
canonical source fields for provisional row hints, but the native Plan is the
authority for launchability and confirmation wording. Do not invent shortcuts.

Assistant state is per-layer; request it on layer selection to restore history.
Assistant transport is tool-free, with no local-command/runtime/Scout fallback.
Suggestions are inert and follow the same plan/confirm path. No effects on page
open, selection, view changes, replies, history reads or assistant state reads.

This file is the target contract. Native Undo mutation-journal integration is
not complete yet and action.undo must remain unadvertised until it is.
