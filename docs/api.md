---
title: Agent API
description: WebSocket API reference for programmatic control of lattices
order: 5
---

The lattices menu bar app runs a WebSocket server on `ws://127.0.0.1:9399`.
35+ RPC methods and 5 real-time events.

## Quick start

1. Launch the server (it starts with the menu bar app):

```bash
lattices app
```

2. Check that it's running:

```bash
lattices daemon status
```

3. Call a method from Node.js:

```js
import { daemonCall } from '@lattices/cli'

const windows = await daemonCall('windows.list')
console.log(windows) // [{ wid, app, title, frame, ... }, ...]
```

Or from any language — it's a standard WebSocket:

```bash
# Plain websocat example
echo '{"id":"1","method":"daemon.status"}' | websocat ws://127.0.0.1:9399
```

## Wire protocol

lattices uses a JSON-RPC-style protocol over WebSocket on port **9399**.

### Request

```json
{
  "id": "unique-string",
  "method": "windows.list",
  "params": { "wid": 1234 }
}
```

| Field    | Type    | Required | Description                          |
|----------|---------|----------|--------------------------------------|
| `id`     | string  | yes      | Caller-chosen ID, echoed in response |
| `method` | string  | yes      | Method name (see below)              |
| `params` | object  | no       | Method-specific parameters           |

### Response

```json
{
  "id": "unique-string",
  "result": [ ... ],
  "error": null
}
```

| Field    | Type           | Description                                  |
|----------|----------------|----------------------------------------------|
| `id`     | string         | Echoed from request                          |
| `result` | any \| null    | Method return value (null on error)          |
| `error`  | string \| null | Error message (null on success)              |

### Errors

| Error           | Meaning                              |
|-----------------|--------------------------------------|
| Unknown method  | The `method` string is not recognized |
| Missing parameter | A required param was not provided   |
| Not found       | The referenced resource doesn't exist |

### Connection lifecycle

- The server starts when the menu bar app launches and stops when it quits.
- Connections are plain WebSocket. No handshake, no auth, no heartbeat.
- The Node.js `daemonCall()` client opens a fresh connection per call and
  closes it when the response arrives. For event subscriptions, hold the
  connection open (see [Reactive event pattern](#agent-integration)).
- If the server restarts (e.g. after `lattices app restart`), existing
  connections are dropped. Clients should reconnect and treat it as
  stateless. There is no session resumption.

## Node.js client

lattices ships a zero-dependency WebSocket client that works with
Node.js 18+. It handles connection, framing, and request/response
matching internally.

### `daemonCall(method, params?, timeoutMs?)`

Send an RPC call and await the response.

```js
import { daemonCall } from '@lattices/cli'

// Read-only
const status = await daemonCall('daemon.status')
const windows = await daemonCall('windows.list')
const win = await daemonCall('windows.get', { wid: 1234 })

// Mutations
await daemonCall('session.launch', { path: '/Users/you/dev/myapp' })
await daemonCall('window.place', {
  session: 'myapp-a1b2c3',
  placement: { kind: 'tile', value: 'left' }
})

// Custom timeout (default: 3000ms)
await daemonCall('projects.scan', null, 10000)
```

**Returns** the `result` field from the response.
**Throws** if the server returns an error, the connection fails, or the timeout is reached.

### `isDaemonRunning()`

Check if the server is reachable.

```js
import { isDaemonRunning } from '@lattices/cli'

if (await isDaemonRunning()) {
  console.log('daemon is up')
}
```

Returns `true` if `daemon.status` responds within 1 second.

### Error handling

`daemonCall` throws on errors — always wrap calls in try/catch:

```js
import { daemonCall } from '@lattices/cli'

try {
  await daemonCall('session.launch', { path: '/nonexistent' })
} catch (err) {
  // err.message is one of:
  //   "Not found"              — resource doesn't exist
  //   "Missing parameter: ..." — required param missing
  //   "Unknown method: ..."    — bad method name
  //   "Daemon request timed out" — no response within timeout
  //   ECONNREFUSED             — daemon not running
  console.error('Daemon error:', err.message)
}
```

---

## System

| Method | Type | Description |
|--------|------|-------------|
| `daemon.status` | read | Health check and stats |
| `api.schema` | read | Full API schema for self-discovery |
| `diagnostics.list` | read | Recent diagnostic entries |

#### `daemon.status`

Health check and basic stats.

**Params**: none

**Returns**:

```json
{
  "uptime": 3600.5,
  "clientCount": 2,
  "version": "1.0.0",
  "windowCount": 12,
  "tmuxSessionCount": 3
}
```

#### `api.schema`

Return the full API schema including version, models, and method definitions.
Useful for agent self-discovery.

**Params**: none

CLI shortcut:

```bash
lattices call api.schema
```

#### `diagnostics.list`

Return recent diagnostic log entries from the daemon.

**Params**:

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| `limit` | number | no       | Max entries to return (default 50) |

---

## Windows & Spaces

| Method | Type | Description |
|--------|------|-------------|
| `windows.list` | read | All visible windows |
| `windows.get` | read | Single window by ID |
| `windows.search` | read | Search windows by query |
| `spaces.list` | read | macOS display spaces |
| `window.place` | write | Place a window or session using a typed placement spec |
| `window.tile` | write | Compatibility wrapper for session tiling |
| `window.focus` | write | Focus a window / switch Spaces |
| `window.move` | write | Move a window to another Space |
| `window.assignLayer` | write | Tag a window to a layer |
| `window.removeLayer` | write | Remove a window's layer tag |
| `window.layerMap` | read | All window→layer assignments |
| `space.optimize` | write | Optimize a set of windows using an explicit scope and strategy |
| `layout.distribute` | write | Compatibility wrapper for visible-window balancing |

#### `windows.list`

List all visible windows tracked by the desktop model.

**Params**: none

**Returns**: array of window objects:

```json
[
  {
    "wid": 1234,
    "app": "Terminal",
    "pid": 5678,
    "title": "[lattices:myapp-a1b2c3] zsh",
    "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
    "spaceIds": [1],
    "isOnScreen": true,
    "latticesSession": "myapp-a1b2c3",
    "layerTag": "web"
  }
]
```

The `latticesSession` field is present only on windows that belong to
a lattices session (matched via the `[lattices:name]` title tag).

The `layerTag` field is present when a window has been manually assigned
to a layer via `window.assignLayer`.

#### `windows.get`

Get a single window by its CGWindowID.

**Params**:

| Field | Type   | Required | Description       |
|-------|--------|----------|-------------------|
| `wid` | number | yes      | CGWindowID        |

**Returns**: a single window object (same shape as `windows.list` items).
**Errors**: `Not found` if the window ID doesn't exist.

#### `windows.search`

Search windows by text query across title, app name, session tags, and OCR content. Returns results with `matchSource` indicating how the match was found, and `ocrSnippet` for OCR matches.

**Params**:

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| `query` | string | yes      | Search query (matches title, app, session, OCR text) |
| `ocr`   | boolean| no       | Include OCR text in search (default true) |
| `limit` | number | no       | Max results (default 50)       |

**Returns**: array of window objects with additional search fields:

```json
[
  {
    "wid": 265,
    "app": "iTerm2",
    "title": "✳ Claude Code",
    "matchSource": "ocr",
    "ocrSnippet": "…~/dev/vox StatusBarIconFolder…",
    "frame": { "x": 688, "y": 3, "w": 1720, "h": 720 },
    "isOnScreen": true
  }
]
```

`matchSource` values: `"title"`, `"app"`, `"session"`, `"ocr"`.

**CLI usage**:

```bash
# Basic search (uses windows.search)
lattices search vox

# Deep search — adds terminal tab/process inspection for ranking
lattices search vox --deep

# Pipeable output
lattices search vox --wid
lattices search vox --json

# Search + focus + tile in one step
lattices place vox right
```

#### `spaces.list`

List macOS display spaces (virtual desktops).

**Params**: none

**Returns**: array of display objects:

```json
[
  {
    "displayIndex": 0,
    "displayId": "main",
    "currentSpaceId": 1,
    "spaces": [
      { "id": 1, "index": 0, "display": 0, "isCurrent": true },
      { "id": 2, "index": 1, "display": 0, "isCurrent": false }
    ]
  }
]
```

#### `window.place`

Canonical window placement mutation. Use this when an agent needs a
single, typed placement contract across voice, CLI, and daemon clients.

**Params**:

| Field       | Type            | Required | Description                              |
|-------------|-----------------|----------|------------------------------------------|
| `wid`       | number          | no       | Target window ID                          |
| `session`   | string          | no       | Target lattices session                   |
| `app`       | string          | no       | Target app name                           |
| `title`     | string          | no       | Optional title substring for app matching |
| `display`   | number          | no       | Target display index                      |
| `placement` | string \| object | yes     | Placement shorthand or typed object       |

Target resolution priority is `wid` → `session` → `app/title` → frontmost window.

**Placement strings**: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`,
`bottom-left`, `bottom-right`, `left-third`, `center-third`, `right-third`,
`top-third`, `middle-third`, `bottom-third`, `left-quarter`, `right-quarter`,
`top-quarter`, `bottom-quarter`, `maximize`, `center`, or `grid:CxR:C,R`.

**Typed placement examples**:

```json
{ "kind": "tile", "value": "top-right" }
{ "kind": "grid", "columns": 3, "rows": 2, "column": 2, "row": 0 }
{ "kind": "fractions", "x": 0.5, "y": 0, "w": 0.5, "h": 1 }
```

**Returns**: execution receipt including resolved target, placement, and trace.

#### `window.tile`

Compatibility wrapper for `window.place` when the target is a lattices
session window.

**Params**:

| Field      | Type   | Required | Description                             |
|------------|--------|----------|-----------------------------------------|
| `session`  | string | yes      | Session name                            |
| `position` | string | yes      | Placement shorthand or grid syntax      |

This method exists for compatibility. New integrations should prefer
`window.place`.

#### `window.focus`

Focus a window — bring it to front and switch Spaces if needed.

**Params** (one of):

| Field     | Type   | Required | Description                     |
|-----------|--------|----------|---------------------------------|
| `wid`     | number | no       | CGWindowID (any window)         |
| `session` | string | no       | Session name (lattices windows)  |

Provide either `wid` or `session`. If `wid` is given, it takes priority.

#### `window.move`

Move a session's window to a different macOS Space.

**Params**:

| Field     | Type   | Required | Description                |
|-----------|--------|----------|----------------------------|
| `session` | string | yes      | Session name               |
| `spaceId` | number | yes      | Target Space ID (from `spaces.list`) |

#### `window.assignLayer`

Manually tag a window to a layer. Tagged windows are raised and tiled
when that layer activates, even if they aren't declared in `workspace.json`.

**Params**:

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| `wid`   | number | yes      | CGWindowID                     |
| `layer` | string | yes      | Layer ID to assign             |

#### `window.removeLayer`

Remove a window's layer tag.

**Params**:

| Field | Type   | Required | Description    |
|-------|--------|----------|----------------|
| `wid` | number | yes      | CGWindowID     |

#### `window.layerMap`

Return all current window→layer assignments.

**Params**: none

**Returns**:

```json
{
  "1234": "web",
  "5678": "mobile"
}
```

Keys are CGWindowIDs (as strings), values are layer IDs.

#### `space.optimize`

Canonical space-balancing mutation. Use this when the goal is to make
the current workspace coherent rather than placing one specific window.

**Params**:

| Field       | Type     | Required | Description                                         |
|-------------|----------|----------|-----------------------------------------------------|
| `scope`     | string   | no       | `visible`, `active-app`, `app`, or `selection`      |
| `strategy`  | string   | no       | `balanced` or `mosaic`                              |
| `app`       | string   | no       | App name for `app` scope                            |
| `title`     | string   | no       | Optional title substring for app matching           |
| `windowIds` | number[] | no       | Explicit window IDs for `selection` scope           |

If `windowIds` is provided, scope is inferred as `selection`.
If `app` is provided and `scope` is omitted, scope is inferred as `app`.

**Returns**: execution receipt including resolved scope, strategy,
affected window IDs, and trace.

#### `layout.distribute`

Compatibility wrapper for `space.optimize` with `scope=visible` and
`strategy=balanced`.

**Params**: none

---

## Sessions

| Method | Type | Description |
|--------|------|-------------|
| `tmux.sessions` | read | Lattices tmux sessions |
| `tmux.inventory` | read | All sessions including orphans |
| `session.launch` | write | Launch a project session |
| `session.kill` | write | Kill a session |
| `session.detach` | write | Detach clients from a session |
| `session.sync` | write | Reconcile session to config |
| `session.restart` | write | Restart a pane's process |

All session methods require tmux to be installed.

#### `tmux.sessions`

List tmux sessions that belong to lattices.

**Params**: none

**Returns**: array of session objects:

```json
[
  {
    "name": "myapp-a1b2c3",
    "windowCount": 1,
    "attached": true,
    "panes": [
      {
        "id": "%0",
        "windowIndex": 0,
        "windowName": "main",
        "title": "claude",
        "currentCommand": "claude",
        "pid": 9876,
        "isActive": true
      }
    ]
  }
]
```

#### `tmux.inventory`

List all tmux sessions including orphans (sessions not tracked by lattices).

**Params**: none

**Returns**:

```json
{
  "all": [ ... ],
  "orphans": [ ... ]
}
```

Both arrays contain session objects (same shape as `tmux.sessions`).

#### `session.launch`

Launch a new tmux session for a project. If a session already exists,
it will be reattached. The project must be in the scanned project list —
call `projects.list` to check, or `projects.scan` to refresh.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |

**Returns**: `{ "ok": true }`
**Errors**: `Not found` if the path isn't in the scanned project list.

#### `session.kill`

Kill a tmux session by name.

**Params**:

| Field  | Type   | Required | Description         |
|--------|--------|----------|---------------------|
| `name` | string | yes      | Session name        |

#### `session.detach`

Detach all clients from a session (keeps it running).

**Params**:

| Field  | Type   | Required | Description         |
|--------|--------|----------|---------------------|
| `name` | string | yes      | Session name        |

#### `session.sync`

Reconcile a running session to match its declared `.lattices.json` config.
Recreates missing panes, re-applies layout, restores labels, re-runs
commands in idle panes.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |

**Errors**: `Not found` if the path isn't in the project list.

#### `session.restart`

Restart a specific pane's process within a session.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |
| `pane` | string | no       | Pane name to restart (defaults to first pane) |

---

## Projects & Layers

| Method | Type | Description |
|--------|------|-------------|
| `projects.list` | read | Discovered projects |
| `projects.scan` | write | Re-scan project directory |
| `layers.list` | read | Workspace layers and active index |
| `layer.activate` | write | Activate a workspace layer using an explicit mode |
| `layer.switch` | write | Compatibility wrapper for launch-style layer activation |
| `group.launch` | write | Launch a tab group |
| `group.kill` | write | Kill a tab group |

#### `projects.list`

List all discovered projects.

**Params**: none

**Returns**: array of project objects:

```json
[
  {
    "path": "/Users/you/dev/myapp",
    "name": "myapp",
    "sessionName": "myapp-a1b2c3",
    "isRunning": true,
    "hasConfig": true,
    "paneCount": 2,
    "paneNames": ["claude", "server"],
    "devCommand": "pnpm dev",
    "packageManager": "pnpm"
  }
]
```

`devCommand` and `packageManager` are present only when detected.

#### `projects.scan`

Trigger a re-scan of the project directory. Useful after cloning a new
repo or adding a `.lattices.json` config.

**Params**: none

#### `layers.list`

List configured workspace layers and the active index.

**Params**: none

**Returns**:

```json
{
  "layers": [
    { "id": "web", "label": "Web", "index": 0, "projectCount": 2 },
    { "id": "mobile", "label": "Mobile", "index": 1, "projectCount": 2 }
  ],
  "active": 0
}
```

Returns empty `layers` array if no workspace config is loaded.

#### `layer.activate`

Canonical layer mutation. Use this when an agent wants an explicit
activation mode instead of implicit "switch" behavior.

**Params**:

| Field   | Type   | Required | Description                                 |
|---------|--------|----------|---------------------------------------------|
| `index` | number | no       | Layer index (0-based)                       |
| `name`  | string | no       | Layer ID or label                           |
| `mode`  | string | no       | `launch`, `focus`, or `retile`              |

Provide either `index` or `name`.

**Modes**:

- `launch` — bring up the layer, launching missing projects and retiling
- `focus` — raise the layer's windows in place
- `retile` — re-apply the layer layout without launch semantics

**Returns**: execution receipt including resolved layer, mode, and trace.

#### `layer.switch`

Compatibility wrapper for `layer.activate` with `mode=launch`.
It keeps the old semantics and still posts a `layer.switched` event.

#### `group.launch`

Launch a tab group session.

**Params**:

| Field | Type   | Required | Description      |
|-------|--------|----------|------------------|
| `id`  | string | yes      | Group ID         |

**Errors**: `Not found` if the group ID doesn't match any configured group.

#### `group.kill`

Kill a tab group session.

**Params**:

| Field | Type   | Required | Description      |
|-------|--------|----------|------------------|
| `id`  | string | yes      | Group ID         |

---

## Processes & Terminals

| Method | Type | Description |
|--------|------|-------------|
| `processes.list` | read | Running developer processes |
| `processes.tree` | read | Process tree from a PID |
| `terminals.list` | read | Terminal instances with processes |
| `terminals.search` | read | Search terminals by criteria |

#### `processes.list`

List running processes relevant to development (editors, servers, build tools).

**Params**:

| Field     | Type   | Required | Description                        |
|-----------|--------|----------|------------------------------------|
| `command` | string | no       | Filter by command name substring   |

**Returns**: array of process objects:

```json
[
  {
    "pid": 1234,
    "ppid": 567,
    "command": "node",
    "args": "server.js",
    "cwd": "/Users/you/dev/myapp",
    "tty": "/dev/ttys003",
    "tmuxSession": "myapp-a1b2c3",
    "tmuxPaneId": "%0"
  }
]
```

#### `processes.tree`

Get the process tree rooted at a given PID.

**Params**:

| Field | Type   | Required | Description   |
|-------|--------|----------|---------------|
| `pid` | number | yes      | Root PID      |

**Returns**: array of process objects (same shape as `processes.list`).

#### `terminals.list`

List all discovered terminal instances with their processes, tabs, and tmux associations.

**Params**:

| Field     | Type    | Required | Description                          |
|-----------|---------|----------|--------------------------------------|
| `refresh` | boolean | no       | Force-refresh the terminal tab cache |

**Returns**: array of terminal instance objects:

```json
[
  {
    "tty": "/dev/ttys003",
    "app": "Terminal",
    "windowIndex": 0,
    "tabIndex": 0,
    "isActiveTab": true,
    "tabTitle": "myapp",
    "processes": [ ... ],
    "shellPid": 1234,
    "cwd": "/Users/you/dev/myapp",
    "tmuxSession": "myapp-a1b2c3",
    "tmuxPaneId": "%0",
    "hasClaude": true,
    "displayName": "Terminal — myapp"
  }
]
```

#### `terminals.search`

Search terminal instances by various criteria.

**Params**:

| Field      | Type    | Required | Description                          |
|------------|---------|----------|--------------------------------------|
| `command`  | string  | no       | Filter by command name substring     |
| `cwd`      | string  | no       | Filter by working directory substring |
| `app`      | string  | no       | Filter by terminal app name          |
| `session`  | string  | no       | Filter by tmux session name          |
| `hasClaude`| boolean | no       | Filter to only Claude-running TTYs   |

**Returns**: filtered array of terminal instance objects (same shape as `terminals.list`).

---

## OCR

| Method | Type | Description |
|--------|------|-------------|
| `ocr.snapshot` | read | Current OCR results for all visible windows |
| `ocr.search` | read | Full-text search across OCR history |
| `ocr.history` | read | OCR timeline for a specific window |
| `ocr.scan` | write | Trigger an immediate OCR scan |

See [Screen OCR](/docs/ocr) for configuration, scan schedules, and storage details.

#### `ocr.snapshot`

Get the current in-memory OCR results for all visible windows.

**Params**: none

**Returns**: array of OCR result objects:

```json
[
  {
    "wid": 1234,
    "app": "Terminal",
    "title": "zsh",
    "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
    "fullText": "~/dev/myapp $ npm run dev\nready on port 3000",
    "blocks": [
      {
        "text": "~/dev/myapp $ npm run dev",
        "confidence": 0.95,
        "x": 0.02, "y": 0.05, "w": 0.6, "h": 0.04
      }
    ],
    "timestamp": 1709568000.0
  }
]
```

#### `ocr.search`

Full-text search across OCR history using SQLite FTS5.

**Params**:

| Field   | Type    | Required | Description                              |
|---------|---------|----------|------------------------------------------|
| `query` | string  | yes      | FTS5 search query                        |
| `app`   | string  | no       | Filter by application name               |
| `limit` | number  | no       | Max results (default 50)                 |
| `live`  | boolean | no       | Search live snapshot instead of history (default false) |

**FTS5 query examples**: `error`, `"build failed"`, `error OR warning`, `npm AND dev`, `react*`

#### `ocr.history`

Get the OCR timeline for a specific window, ordered by most recent first.

**Params**:

| Field   | Type   | Required | Description                |
|---------|--------|----------|----------------------------|
| `wid`   | number | yes      | CGWindowID                 |
| `limit` | number | no       | Max results (default 50)   |

#### `ocr.scan`

Trigger an immediate OCR scan of all visible windows, bypassing the
periodic timer. Results available via `ocr.snapshot` once complete;
an `ocr.scanComplete` event is broadcast to all clients.

**Params**: none

---

## Events

Events are pushed to all connected WebSocket clients when state changes.
They have no `id` field — listen for messages with an `event` field.

| Event | Trigger |
|-------|---------|
| `windows.changed` | Desktop window list changes |
| `tmux.changed` | Sessions created, killed, or modified |
| `layer.switched` | Active workspace layer changes |
| `ocr.scanComplete` | OCR scan cycle finishes |
| `processes.changed` | Developer processes start or stop |

#### `windows.changed`

```json
{ "event": "windows.changed", "data": { "windowCount": 12, "added": [1234], "removed": [5678] } }
```

#### `tmux.changed`

```json
{ "event": "tmux.changed", "data": { "sessionCount": 3, "sessions": ["myapp-a1b2c3"] } }
```

#### `layer.switched`

```json
{ "event": "layer.switched", "data": { "index": 1, "name": "mobile" } }
```

#### `ocr.scanComplete`

```json
{ "event": "ocr.scanComplete", "data": { "windowCount": 12, "totalBlocks": 342 } }
```

#### `processes.changed`

```json
{ "event": "processes.changed", "data": { "interestingCount": 5, "pids": [1234, 5678] } }
```

---

## Agent integration

### CLAUDE.md snippet

Add this to your project's `CLAUDE.md` so any AI agent working in the
project knows how to control the workspace:

```markdown
## Workspace Control

This project uses lattices for workspace management. The daemon API
is available at ws://127.0.0.1:9399.

### Search (find windows)
- Search by content: `daemonCall('windows.search', { query: 'myproject' })`
  Returns windows with `matchSource` ("title", "app", "session", "ocr") and `ocrSnippet`
- Search terminals: `daemonCall('terminals.search', {})` — tabs, cwds, processes
- CLI: `lattices search myproject` or `lattices search myproject --deep`

### Actions
- Focus a window: `daemonCall('window.focus', { wid: 1234 })`
- Place a window: `daemonCall('window.place', { session: 'name', placement: 'left' })`
- Launch a project: `daemonCall('session.launch', { path: '/absolute/path' })`
- Activate a layer: `daemonCall('layer.activate', { name: 'web', mode: 'launch' })`
- Optimize the workspace: `daemonCall('space.optimize', { scope: 'visible', strategy: 'balanced' })`
- CLI: `lattices place myproject left` (search + focus + tile in one step)

### Import
\```js
import { daemonCall } from '@lattices/cli'
\```
```

### Multi-agent orchestration

An orchestrator agent can set up the full workspace for sub-agents:

```js
import { daemonCall } from '@lattices/cli'

// Discover what's available
const projects = await daemonCall('projects.list')

// Launch the projects we need
await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('session.launch', { path: '/Users/you/dev/api' })

// Tile them side by side
const sessions = await daemonCall('tmux.sessions')
const fe = sessions.find(s => s.name.startsWith('frontend'))
const api = sessions.find(s => s.name.startsWith('api'))

await daemonCall('window.place', { session: fe.name, placement: 'left' })
await daemonCall('window.place', { session: api.name, placement: 'right' })
```

### Reactive event pattern

Subscribe to events to react to workspace changes:

```js
import WebSocket from 'ws'

const ws = new WebSocket('ws://127.0.0.1:9399')

ws.on('message', (raw) => {
  const msg = JSON.parse(raw)

  if (msg.event === 'tmux.changed') {
    console.log('Sessions:', msg.data.sessions.join(', '))
  }

  if (msg.event === 'windows.changed') {
    console.log('Windows:', msg.data.windowCount, 'total')
  }

  if (msg.event === 'layer.switched') {
    console.log('Switched to layer', msg.data.index)
  }
})

// You can also send RPC calls on the same connection
ws.on('open', () => {
  ws.send(JSON.stringify({ id: '1', method: 'daemon.status' }))
})
```

### Health check before use

Always verify the daemon is running before making calls:

```js
import { isDaemonRunning, daemonCall } from '@lattices/cli'

if (!(await isDaemonRunning())) {
  console.error('lattices daemon is not running — start it with: lattices app')
  process.exit(1)
}

const status = await daemonCall('daemon.status')
console.log(`Daemon up for ${Math.round(status.uptime)}s, tracking ${status.windowCount} windows`)
```
