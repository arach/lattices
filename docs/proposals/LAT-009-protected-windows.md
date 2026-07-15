# LAT-009: Protected Windows (Agent No-Go Zones)

Status: Proposed
Date: 2026-07-14
Audience: Lattices implementers, agent integrations

## Summary

Let users declare windows that agents must not touch. A protected window
rejects every agent-initiated action (input synthesis, element actions,
placement, focus) and every content capture (OCR, screenshot, AX text) at the
daemon boundary, with a structured refusal that lands in run receipts. The
human is never gated — protection applies only to the API surface.

This is the enforcement half of the "safe computer use" promise: treatments
and receipts make agent actions reviewable; protected windows make some
targets non-negotiable.

## Motivation

Agents can now observe, stage, execute, and verify against the real desktop
(LAT-008). That surface currently has no user-defined boundaries: nothing
stops an agent from clicking into 1Password, reading a banking tab via OCR,
or dragging a window the user considers off-limits. A user-declared no-go
list is the missing primitive, and it must be enforced in the daemon — not
suggested in prompts — so it holds regardless of which agent or harness is
connected.

## Rule model

Rules live in `~/.lattices/protected.json`, following the existing
file-backed store pattern (`layers.json`, `clusters.json`), hot-reloaded via
file watcher.

```json
{
  "rules": [
    { "app": "1Password*" },
    { "bundleId": "com.apple.Passwords" },
    { "app": "Safari", "titleContains": "banking" },
    { "wid": 4821, "note": "session-scoped, set via CLI" }
  ]
}
```

Matching semantics:

- `app` — window's owning app name, glob (`*` wildcard), case-insensitive.
- `bundleId` — exact match on the owning app's bundle identifier.
- `titleContains` — case-insensitive substring on the window title;
  combines AND-wise with `app`/`bundleId` in the same rule.
- `wid` — a specific window id, for ad-hoc session-scoped protection.
- A window is protected if any rule matches.

v1 has a single protection level, **no-touch**: the window stays visible in
`windows.search` (annotated `"protected": true` so agents can plan around
it), but no agent action or content capture may target it. An **invisible**
level (excluded from search and the OCR index entirely) is deferred to
phase 2.

## Enforcement

One policy type, one call site per resolution path:

- `ProtectedWindowPolicy` (new, `Core/Actions/`) — loads and watches
  `protected.json`, exposes `check(window: WindowEntry) -> Rule?` and
  `ensureAllowed(window:action:) throws`.
- **ComputerUseController**: every handler resolves its target
  `WindowEntry` before acting (`elementAction`, `typeElement`, `setValue`,
  `pressKey`, `hotkey`, `typeText`, `typeWindowText`, `click`/`doubleClick`/
  `rightClick`, `scroll`, `drag`, `focusWindow`, `magicCursor`). Guard at
  that resolution point. All treatments are refused, including `stage` —
  fail at staging time, not execute time.
- **Content capture**: `windowState` with `capture: [ocr|screen|tree]` and
  `verify` in OCR/AX modes refuse protected targets. Blocking clicks on a
  password manager while allowing screenshots of it would be theater.
- **Placement and focus**: `window.place`, `window.focus`, `window.move`,
  tiling, and `space.optimize` skip protected windows (optimize excludes
  them from the arrangement set rather than erroring).
- **`allowGlobal` inputs**: global keystrokes with no window target check
  the *currently focused* window; if it is protected, refuse.

Error shape, so agents get a parseable "no" and receipts record it:

```json
{
  "error": {
    "code": "protected_window",
    "message": "Window 4821 (1Password) is protected by user rule",
    "wid": 4821,
    "rule": { "app": "1Password*" }
  }
}
```

## Surface

- API: `protection.list` (rules + currently-matching windows),
  `protection.add`, `protection.remove` (write through to the file).
- CLI: `lattices protect add --app "1Password*"`, `lattices protect list`,
  `lattices protect rm <index|wid>`.
- `windows.search` / window payloads gain `"protected": true`.
- Docs: section in `docs/agents.md` + `docs/api.md`; the assistant knowledge
  base should mention it so the in-app assistant can explain refusals.

## Defaults

Ship no silently-active rules (surprise refusals read as bugs). Seed the
file on first run with commented-out suggestions — password managers
(1Password, Bitwarden, KeePassXC), Keychain Access/Passwords — and have
`lattices protect init` write them active.

## Phase 2 (deferred)

- **Invisible level**: exclude from `windows.search`, `terminals.search`,
  and the background OCR indexer (touches the indexer subsystem — the
  reason this is not v1).
- Menu bar app: right-click a window in the screen map → "Protect from
  agents" (writes a `wid` or derived `app` rule).
- Per-client scoping: companion bridge identities could later carry
  different rule sets per agent.

## Non-goals

- Gating human input. Protection is a daemon-API concept only.
- Preventing a malicious local process from using AX directly. This guards
  the Lattices surface; it is not an OS sandbox.

## Open questions

- Should `layer.activate` fail or partially proceed when a layer references
  a protected window? (Leaning: proceed, report skipped windows.)
- Does protecting an app also protect its sheets/child windows with empty
  titles? (Leaning: yes — match on owning pid.)
