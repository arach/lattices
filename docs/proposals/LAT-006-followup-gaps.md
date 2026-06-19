# LAT-006 Follow-up: Next Use Cases & Gaps (Load / Voice / Type / Click)

Assessment date: 2026-06-17. Scope: current working tree on `main` (uncommitted LAT-006
runs/capture/computer-use slice). Focus: root-cause product/API shape, not workarounds.

## What exists today (grounded)

A real **observe → act → capture → trace** layer landed (LAT-006 Phase 2 + a computer-use
extension), wired end to end:

- **Daemon** (`apps/mac/Sources/Core/Daemon/LatticesApi.swift`):
  - `runs.create | runs.list | runs.get | runs.artifacts`
  - `capture.screenshotWindow`
  - `computer.prepare | computer.focusWindow | computer.typeText | computer.showCursor | computer.demoTerminal`
  - `settings.cursorAppearance.get | .set`
- **Controllers**: `Core/Actions/ComputerUseController.swift`, `Core/Capture/CaptureController.swift`,
  `Core/Runs/RunStore.swift` + `RunModels.swift` (persists to `~/Library/Application Support/Lattices/Runs/`, `runs.json` index).
- **CLI** (`bin/lattices.ts`): `lattices computer|capture|runs|terminals`.
- **Palette** (`PaletteCommand.swift`): "Screenshot Current Window", "Review Runs" under a new `.run` category → `ScreenMapWindowController.showPage(.runs)` + `RunsReviewView.swift`.
- **Safety model**: `ComputerTreatment` = observe/stage/present/execute. Typing only targets
  scored *safe* terminals (avoids claude/codex/vim, requires idle shell for Enter), with a transport
  ladder: tmux `send-keys` → iTerm session `write text` → pasteboard/key-events (active tab only).

This is a strong foundation. The gaps below are about **shape**, not patching.

## Gaps by focus area (root-cause)

### 1. Loading apps — not a first-class, composable operation
App/project launch lives only inside the voice `launch` intent → `session.launch`
(`Intents/LaunchIntent.swift`), with a brittle fallback (capitalize first letter, `NSWorkspace`
name match; no bundle-id resolution). Root cause: **there is no `apps.launch` daemon verb and no
"wait until window exists" precondition.** So launching can't be wrapped as a Run, can't be composed
with capture/type/click, and the computer-use layer can't open a target app before acting on it.
→ Add `apps.launch` (name/bundleId/project) returning a `RunSession` with surfaces, plus a shared
`waitForWindow` primitive that `computer.focusWindow/typeText/click` reuse as a precondition.

### 2. Voice/talk flows — the new capabilities are invisible to voice
`IntentEngine.swift` vocabulary stops at workspace control: tile_window, focus, launch,
switch_layer, search, list_*, distribute, create_layer, kill, scan, swap, hide, highlight,
move_to_display, find_mouse, summon_mouse, undo. Root cause: **none of `computer.*`, `capture.*`,
or `runs.*` is registered as an intent.** Voice can move/observe windows but cannot drive the proof
loop (screenshot, type, review a run). The slot/dispatch plumbing already exists, so this is additive.
→ Register `screenshot` → `capture.screenshotWindow`; `type` → `computer.typeText` (default
`treatment=stage`, require explicit confirm before execute — matches the HandsOff "don't act on
questions" preference); `show_cursor`/`click` → cursor/click methods; `review_run` → runs page.

### 3. Typing — solid, but terminal-only
Strongest area. The transport ladder + safety scoring is the right shape. Root-cause limits:
- Typing targets **terminals exclusively** (`TerminalCandidate` / `ProcessModel.synthesizeTerminals`).
  There is no "type into the focused text field of app X" (browser URL bar, native field).
- The pasteboard path saves/restores the clipboard but requires the tab already active; iTerm is
  explicitly excluded from the keyboard transport, so non-tmux iTerm has no fallback.
→ Add an AX-based `computer.typeInto` that resolves the focused element / a target text field, keeping
the terminal path as the specialized *safe* case. This generalizes typing without weakening the
terminal safety model.

### 4. Clicking around — the verb does not exist
**There is no click action.** `computer.showCursor` only renders a visual marker; it posts no mouse
event. The only `CGEvent` mouse code (`Core/Input/MouseGestureController.swift`) *recognizes* gestures
— it does not synthesize targeted clicks. So the "act" half of the loop for non-terminal targets
(buttons, links, menu items) is entirely missing. This is the single biggest missing primitive.
→ Add `computer.click` (+ `computer.moveCursor`) that resolves a target (coordinate, AX element, or
window+role) and posts left/right down/up via `CGEvent`, wrapped in a Run with before/after capture,
gated by the same treatment model (observe/stage/present/execute).

### 5. Cross-cutting: the proof loop is open at both ends
- **Recording not implemented.** Proposal lists `capture.recordWindow/recordRegion` + an AppKit
  `--recording-probe` (Phase 3); only screenshots exist (`WindowCapture` uses `SCStream` for stills).
  Also missing: `runs.start`, `runs.stop`.
- **No verify step.** `typeText` captures before/after screenshots but never asserts the text landed.
  An OCR/AX diff (reusing the existing `ocr.search`) would close observe → act → **verify** and feed
  LAT-005 receipts.

## Suggested implementation order (highest leverage first)

1. **`computer.click` + `computer.moveCursor`** — fills the only missing computer-use verb; reuse
   treatment model + Run wrapper + before/after capture.
2. **Voice intents over existing `computer.*`/`capture.*`/`runs.*`** — additive, low risk; stage-by-default
   for any execute, explicit confirm gate.
3. **`apps.launch` (Run-wrapped) + `waitForWindow` precondition** — unblocks "load app, then act".
4. **`computer.typeInto` (AX focused-element)** — generalize typing beyond terminals.
5. **LAT-006 Phase 3 recording probe + `runs.stop`**, then an **OCR/AX verify** step on type/click runs.

## Testing steps

- CLI dogfood (per project convention — test via `lattices`, not raw daemon):
  `lattices computer prepare`, `lattices computer type --text "ls" --dry-run`, `lattices capture window`,
  `lattices runs list`, `lattices runs <id> --json`.
- Treatment matrix: observe/stage/present/execute each produce a Run with correct artifacts and never
  over-act (stage/observe must not focus or type).
- Safety regression: `computer.typeText` refuses claude/codex/vim targets; refuses Enter on non-idle shells.
- Click (new): coordinate click + AX-element click on a known button → before/after artifacts in the run
  dir; assert no click when `treatment != execute`.
- Voice: "screenshot this window" / "type ls in my terminal" resolve to the right daemon method; execute
  paths require confirm.
- Persistence: confirm `~/Library/Application Support/Lattices/Runs/` + `runs.json` survive an app restart.

## Owner / next move

This is an answer, not a handoff — no other agent needs waking. The clearest single next step that
unblocks the most use cases is **`computer.click`** (closes the "act" gap for non-terminal targets),
immediately followed by **exposing the existing computer/capture/run methods to voice**. Both are owned
by the Lattices macOS app. Recording + verify are the right Phase-3 follow-ups once click + voice land.
