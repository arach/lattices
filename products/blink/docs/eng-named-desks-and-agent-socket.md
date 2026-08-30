# Blink v2 — Named Desks and Agent Socket (Layer 2.5) Implementation Spec

> Specification for Codex implementation. Reference companion docs: `docs/agent-api.md`, `docs/agent-integration.md`, `docs/placement.md`, `docs/cli.md`.

## Overview & Goals

Implement two complementary capabilities for Blink:
1. **Named Desk Arrangements**: Ability to snapshot the currently open floating note panels and their geometry/slots into named configurations (`blink desk save <name>`, `blink desk restore <name>`, `blink desk ls`, `blink desk rm <name>`).
2. **Agent Unix Domain Socket (Layer 2.5)**: A live, bidirectional JSON-RPC 2.0 Unix domain socket at `$BLINK_HOME/blink.sock` exposing live runtime desk state (`placements.list`), compound presentation verbs (`notes.present`), named desk verbs (`desk.save/restore`), and live event subscription (`events.subscribe`).

---

## 1. Named Desk Layouts

### Data Model & Storage
- **Location**: `$BLINK_HOME/desks/<name>.json` (or via `BlinkPaths.home()`).
- **Schema**:
  ```json
  {
    "name": "incident-response",
    "updated": "2026-08-19T21:30:00Z",
    "panels": [
      {
        "id": "incident-lead-log",
        "slot": 1,
        "mode": "read",
        "frame": { "x": 100, "y": 200, "width": 400, "height": 500 },
        "display": 1
      }
    ]
  }
  ```
- **DeskStore / DeskManager**: In `BlinkCore`, create a clean store for saving, loading, listing, and deleting desk layouts atomically.

### CLI Commands (`Sources/BlinkCLI/DeskCommands.swift`)
- `blink desk save <name>`: Requests running app to snapshot current open panels and geometry, writes `$BLINK_HOME/desks/<name>.json`.
- `blink desk restore <name>`: Loads `$BLINK_HOME/desks/<name>.json`, commands running app to open/move panels to match layout.
- `blink desk ls [--json]`: Lists saved desk layouts.
- `blink desk show <name> [--json]`: Shows layout details.
- `blink desk rm <name>`: Deletes a saved layout.

---

## 2. Unix Domain Socket (Layer 2.5)

### Socket Lifecycle
- **Path**: `$BLINK_HOME/blink.sock` (honors `BLINK_HOME`, fallback `~/Library/Application Support/Blink/blink.sock`).
- **Permissions**: `0600` (owner only).
- **Lifecycle**: Created when `BlinkApp` launches, removed on clean termination. Stale sockets from previous unclean runs are cleaned up on startup.
- **Framing**: Newline-delimited JSON-RPC 2.0 (`\n`).

### Protocol & Core RPC Methods
- **`system.hello`**: Returns `{ "protocol": "2.0", "version": "2.0.0", "app": "Blink" }`.
- **`placements.list`**: Returns live open panel states (`id`, `frame`, `slot`, `screen`, `mode`, `shaded`, `focused`, `z`).
- **`notes.list`**: Returns in-memory index from `NoteStore`.
- **`notes.get`**: `{ "id": "<id>", "content": true }` returns frontmatter and note body.
- **`notes.present`**: Compound verb `{ "id": "<id>", "content": "...", "slot": 6, "style": "focus" }` — creates/updates note and positions panel in one call.
- **`desk.save`**: `{ "name": "<name>" }` saves current desk layout.
- **`desk.restore`**: `{ "name": "<name>" }` restores named layout.
- **`events.subscribe`**: `{ "topics": ["notes", "placements"] }` streams notifications (`{"jsonrpc":"2.0","method":"panel.moved",...}`).

---

## 3. Implementation Plan & Deliverables

1. **`Sources/BlinkCore`**:
   - Add `DeskLayout` model & `DeskLayoutStore` with atomic file operations.
   - Update `BlinkDeskCommand` with `saveDesk` and `restoreDesk` support.
2. **`Sources/BlinkApp`**:
   - `BlinkSocketServer`: Set up `AF_UNIX` listener on background queue, handling client connections, dispatching JSON-RPC requests to `MainActor` (`PanelManager` / `AppModel` / `NoteStore`).
   - Wire `BlinkSocketServer` into `AppDelegate` lifecycle (start on launch, stop on exit).
3. **`Sources/BlinkCLI`**:
   - Extend `DeskCommand` with `save`, `restore`, `ls`, `show`, `rm`.
   - Add socket client helper with fallback to distributed notifications / files.
4. **Tests & Verification**:
   - Unit tests in `Tests/BlinkCoreTests` for `DeskLayoutStore`.
   - Build verification with `swift build` and `swift test`.
