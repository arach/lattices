# LAT-010 Greenlit Wave — Codex coordinator brief

Status: Greenlit for implementation
Date: 2026-08-12
Source of truth for product intent: `design/api-gaps-memo.html`
This file is the source of truth for *this wave*.

You are the **parent coordinator**. Do not implement all four lanes yourself.
Immediately spawn **four Codex subagents in fast mode** (fastest available
coding model / low reasoning effort). You stay the high-reasoning parent:
merge, wire `LatticesApi.swift`, review, run checks, and report.

Work in the **current checkout** (`/Users/art/dev/lattices`, branch `main`).
Do **not** create worktrees or branches. There is already unrelated dirty
work (`bin/cli/map.ts`, companion/deck files, iOS). Do not touch it.

## Why this wave

The daemon is already unusually complete (~120 methods). Agents do not need
more click variants. They need:

1. one situational-awareness call
2. exact tmux pane text
3. mutations that do not lie about being done
4. permission truth before a capture fails

Those four are greenlit. Everything else in the memo is **held**.

## Held — do not implement

- `user.ask` / `user.confirm`
- `session.claim` / `window.lease`
- LAT-009 protected windows
- event-model overhaul (`window.focused`, subscribe/filter)
- `window.hide` / minimize / close
- `space.switch` as a new first-class mutation (deck already has a path)
- clipboard get/set
- connection hello / client identity
- cross-family transactions
- new computer-use verbs

If a worker drifts into a held item, stop them.

## How to divide

Spawn four isolated workers. They must **not** all edit `LatticesApi.swift`.
Each worker writes a module + tests. **You** register the endpoints after
the modules land.

| Lane | Fast worker owns | Must not touch |
|------|------------------|----------------|
| A Snapshot | new `DesktopSnapshot.swift` (+ tests if a Swift test target exists) | `LatticesApi.swift`, CLI, docs |
| B Pane read | new `TmuxPaneCapture.swift` | `LatticesApi.swift`, CLI, docs |
| C Honest completion | `SessionManager.swift`, `session.launch` / `window.move` internals | snapshot/capture modules |
| D Permissions + docs | `PermissionChecker` status payload, `docs/api.md`, `docs/agents.md` search guidance | Swift computer-use |

After A–D return:

1. Wire endpoints in `apps/mac/Sources/Core/Daemon/LatticesApi.swift`.
2. Add CLI surfaces only if a one-line `lattices call` example is not enough.
   Prefer `lattices call <method>` over new top-level commands.
3. `api.schema` must include the new methods automatically via `register`.
4. Run `bun run check:app` (or `swift build --package-path apps/mac`) and
   `bun run test:cli` if you touch CLI/docs tests.
5. Update the “35+ RPC methods” line in `docs/api.md` to the real count.

## Lane A — `desktop.snapshot`

New read method. One call for “what is in front of the user?”

**Method:** `desktop.snapshot`  
**Access:** read  
**Params:** none required. Optional `includeOffscreen: bool` default false.

**Return shape (required fields):**

```json
{
  "frontmost": { "wid": 1234, "app": "iTerm2", "title": "…", "pid": 1 },
  "activeLayer": { "id": "web", "index": 0 },
  "displays": [ /* same coordinate system as spaces.list */ ],
  "currentSpaceId": 1,
  "windows": [
    {
      "wid": 1234,
      "app": "iTerm2",
      "title": "…",
      "pid": 5678,
      "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
      "spaceIds": [1],
      "isOnScreen": true,
      "zIndex": 0,
      "focused": true,
      "latticesSession": "lattices-a1b2c3",
      "layerTag": "web",
      "lastInteraction": "2026-08-12T12:00:00Z"
    }
  ],
  "sessions": [ { "name": "lattices-a1b2c3", "attached": true, "windowCount": 1 } ],
  "permissions": {
    "accessibility": true,
    "screenRecording": true,
    "inputMonitoring": false
  }
}
```

Reuse `DesktopModel`, `TmuxModel`, `WorkspaceManager` / layers, and
`PermissionChecker.shared`. Do not recapture windows. Do not OCR.

`windows[]` should be on-screen by default, sorted by `zIndex` ascending
(0 = frontmost). Include `lastInteraction` only when `DesktopModel` already
tracks it (`lastInteractionDate(for:)`).

Also enrich `daemon.status` with the same `permissions` object and
`frontmostWid` if cheap. Do not bloat status beyond that.

There is an uncommitted CLI `lattices map` in `bin/cli/map.ts`. Leave that
file alone. `desktop.snapshot` is the daemon primitive; map can consume it
later.

## Lane B — `terminals.capture`

New read method. Exact tmux pane text. Not OCR.

**Method:** `terminals.capture`  
**Access:** read  
**Params:**

| Field | Required | Notes |
|-------|----------|--------|
| `session` | one of session/paneId/tty | lattices or any tmux session name |
| `pane` | no | pane name or `%id` |
| `paneId` | no | tmux pane id (`%12`) |
| `tty` | no | `/dev/ttys003` |
| `lines` | no | last N lines, default 80, max 500 |
| `escape` | no | if false (default), strip ANSI via `tmux capture-pane -p` |

Use `tmux capture-pane -p -t <target> -S -<lines>`. Prefer
`TmuxQuery.resolvedPath`. Never fall back to screenshot/OCR.

Return:

```json
{
  "ok": true,
  "session": "lattices-a1b2c3",
  "paneId": "%3",
  "paneName": "claude",
  "tty": "/dev/ttys012",
  "text": "…last N lines…",
  "lineCount": 80
}
```

If the target is ambiguous, throw a structured error with candidates
(session/pane list). If tmux is missing, throw a clear error.

Look at existing tmux helpers (`TmuxQuery`, `TmuxModel`, `ProcessModel`)
before inventing a new process runner.

## Lane C — honest completion

Today `session.launch` does `DispatchQueue.main.async { SessionManager.launch }`
and returns `{ ok: true }` immediately. `window.move` does the same.

Change those two (and `session.kill` if it is also fire-and-forget on the
router side — kill itself already `waitUntilExit`, but the router should
still return whether the session is gone).

**`session.launch`**

- Run launch on the main thread and **wait**.
- Then wait up to ~4s for a window tagged `[lattices:<session>]` or for
  `tmux has-session`.
- Return a receipt, not a bare ok:

```json
{
  "ok": true,
  "session": "myapp-a1b2c3",
  "alreadyRunning": false,
  "wid": 1234,
  "verified": true
}
```

`ok: false` / `verified: false` if the session or window never appeared.
Do not return success because the dispatch was queued.

**`window.move`**

- Accept `wid` **or** `session` (today session-only).
- Wait for `WindowTiler.moveWindowToSpace` on the main thread.
- Return the `MoveResult` (`success`, `alreadyOnSpace`, `windowNotFound`,
  `failed`) plus `wid`, `spaceId`, `method`.

Do not change `window.place` (it already has receipts).

Reuse `ComputerUseController.waitForWindow` patterns if they are easy to
lift. Do not make that type public unless you have to; a small local wait
loop is fine.

## Lane D — permissions + docs truth

1. Add `permissions.status` as a tiny read endpoint **or** just put
   permissions on `daemon.status` and `desktop.snapshot`. Prefer one
   shared helper: `PermissionChecker.shared.snapshotJSON()`.
   Include accessibility, screenRecording, and input monitoring if already
   tracked; omit fields you cannot know.

2. Docs:
   - `docs/api.md`: add `desktop.snapshot`, `terminals.capture`, updated
     `session.launch` / `window.move` receipts, permissions on
     `daemon.status`. Fix the “35+ methods / 5 events” lede.
   - Document `lattices.search` as the unified search. Keep
     `windows.search` as the weaker title/app/OCR index. Agent snippets
     in `docs/agents.md` and the CLAUDE.md block in `docs/api.md` should
     recommend `lattices.search` first.
   - Do not rewrite the whole API page.

3. CLI: if `lattices search` already calls the unified endpoint, say so
   in docs. Do not invent a new search command.

## Parent wiring (you)

Register:

- `desktop.snapshot`
- `terminals.capture`
- updated `session.launch`, `window.move`
- `permissions.status` only if you did not fold it into `daemon.status`

Match existing `Endpoint` / `Param` / `Encoders` style. Add models to
`api.model(...)` when the return shape is stable.

If Xcode/SPM needs the new Swift files listed, follow how other Core
files are included (`apps/mac/Package.swift` / sources glob). Prefer
dropping them next to existing Core types so the glob picks them up.

## Checks

```bash
swift build --package-path apps/mac
bun run test:cli
```

If the app build is too heavy, at least typecheck the new Swift files
with the package build. Do not claim done without a compile.

Manual smoke (if the app/daemon is running):

```bash
lattices call desktop.snapshot
lattices call terminals.capture '{"session":"<a live session>","lines":40}'
lattices call daemon.status
lattices call api.schema
```

## Extra juice (read before spawning)

- Daemon: `apps/mac/Sources/Core/Daemon/LatticesApi.swift`
- Router errors: search `RouterError` in that file / `DaemonProtocol.swift`
- Windows encoder: `Encoders.window` around line 4770
- Sessions: `apps/mac/Sources/Core/Workspace/SessionManager.swift`
- Move: `WindowTiler.moveWindowToSpace` in `apps/mac/Sources/Core/Desktop/WindowTiler.swift`
- Permissions: `apps/mac/Sources/Core/System/PermissionChecker.swift`
- Terminal synthesis: `ProcessModel.synthesizeTerminals`
- Unified search already exists: `lattices.search` in `LatticesApi.swift` ~line 544
- Agent contracts: `docs/agents.md`, `docs/api.md`
- Product memo: `design/api-gaps-memo.html`

Conventions:

- Session names are `<basename>-<sha256-6chars>`.
- Window frames are top-left global, same as `windows.list`.
- Localhost daemon, no auth. Do not add auth.
- Receipts over `{ok:true}` for mutations.
- No new dependencies.
- Keep comments short and factual.

## Report back

When the wave is in (or blocked), reply with:

- what landed (methods + files)
- compile/test output
- what each fast worker did
- anything you refused because it was held
- leftover nits for a human

Do not open a PR unless asked. Leave the diff in the working tree.
