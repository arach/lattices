---
title: Daemon API
description: WebSocket API reference for programmatic control of lattices
order: 5
---

The lattices menu bar app runs a WebSocket daemon on `ws://127.0.0.1:9399`.
It exposes 30 RPC methods and 5 real-time events — everything the app
can do, agents and scripts can do too.

## Method index

| Method | Type | Description |
|--------|------|-------------|
| `daemon.status` | read | Health check and stats |
| `windows.list` | read | All visible windows |
| `windows.get` | read | Single window by ID |
| `tmux.sessions` | read | Lattices tmux sessions |
| `tmux.inventory` | read | All sessions including orphans |
| `projects.list` | read | Discovered projects |
| `spaces.list` | read | macOS display spaces |
| `layers.list` | read | Workspace layers and active index |
| `processes.list` | read | Running developer processes |
| `processes.tree` | read | Process tree from a PID |
| `terminals.list` | read | Terminal instances with processes |
| `terminals.search` | read | Search terminals by criteria |
| `ocr.snapshot` | read | Current OCR results for all visible windows |
| `ocr.search` | read | Full-text search across OCR history |
| `ocr.history` | read | OCR timeline for a specific window |
| `ocr.scan` | write | Trigger an immediate OCR scan |
| `api.schema` | read | Full API schema for self-discovery |
| `session.launch` | write | Launch a project session |
| `session.kill` | write | Kill a session |
| `session.detach` | write | Detach clients from a session |
| `session.sync` | write | Reconcile session to config |
| `session.restart` | write | Restart a pane's process |
| `window.tile` | write | Tile a window to a position |
| `window.focus` | write | Focus a window / switch Spaces |
| `window.move` | write | Move a window to another Space |
| `layer.switch` | write | Switch workspace layer |
| `group.launch` | write | Launch a tab group |
| `group.kill` | write | Kill a tab group |
| `projects.scan` | write | Re-scan project directory |
| `layout.distribute` | write | Distribute windows evenly |

## Quick start

1. Launch the daemon (it starts with the menu bar app):

```bash
lattices app
```

2. Check that it's running:

```bash
lattices daemon status
```

3. Call a method from Node.js:

```js
import { daemonCall } from '@arach/lattices/daemon-client'

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

### Event (server-pushed)

```json
{
  "event": "windows.changed",
  "data": { ... }
}
```

Events have no `id` — they are broadcast to all connected clients
whenever state changes.

### Errors

Three error types:

| Error           | Meaning                              |
|-----------------|--------------------------------------|
| Unknown method  | The `method` string is not recognized |
| Missing parameter | A required param was not provided   |
| Not found       | The referenced resource doesn't exist |

### Connection lifecycle

- The daemon starts when the menu bar app launches and stops when it quits.
- Connections are plain WebSocket — no handshake, no auth, no heartbeat.
- The Node.js `daemonCall()` client opens a fresh connection per call and
  closes it when the response arrives. For event subscriptions, hold the
  connection open (see [Reactive event pattern](#reactive-event-pattern)).
- If the daemon restarts (e.g. after `lattices app restart`), existing
  connections are dropped. Clients should reconnect and treat the daemon
  as stateless — there is no session resumption.

## Node.js client

lattices ships a zero-dependency WebSocket client that works with
Node.js 18+. It handles connection, framing, and request/response
matching internally.

### `daemonCall(method, params?, timeoutMs?)`

Send an RPC call and await the response.

```js
import { daemonCall } from '@arach/lattices/daemon-client'

// Read-only
const status = await daemonCall('daemon.status')
const windows = await daemonCall('windows.list')
const win = await daemonCall('windows.get', { wid: 1234 })

// Mutations
await daemonCall('session.launch', { path: '/Users/you/dev/myapp' })
await daemonCall('window.tile', { session: 'myapp-a1b2c3', position: 'left' })

// Custom timeout (default: 3000ms)
await daemonCall('projects.scan', null, 10000)
```

**Returns** the `result` field from the response.
**Throws** if the daemon returns an error, the connection fails, or the timeout is reached.

### `isDaemonRunning()`

Check if the daemon is reachable.

```js
import { isDaemonRunning } from '@arach/lattices/daemon-client'

if (await isDaemonRunning()) {
  console.log('daemon is up')
}
```

Returns `true` if `daemon.status` responds within 1 second.

### Error handling

`daemonCall` throws on errors — always wrap calls in try/catch:

```js
import { daemonCall } from '@arach/lattices/daemon-client'

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

## Read methods

### `daemon.status`

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

---

### `windows.list`

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
    "latticesSession": "myapp-a1b2c3"
  }
]
```

The `latticesSession` field is present only on windows that belong to
a lattices session (matched via the `[lattices:name]` title tag).

---

### `windows.get`

Get a single window by its CGWindowID.

**Params**:

| Field | Type   | Required | Description       |
|-------|--------|----------|-------------------|
| `wid` | number | yes      | CGWindowID        |

**Returns**: a single window object (same shape as `windows.list` items).

**Errors**: `Not found` if the window ID doesn't exist.

---

### `tmux.sessions`

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

---

### `tmux.inventory`

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

---

### `projects.list`

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

---

### `spaces.list`

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

---

### `layers.list`

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

---

### `processes.list`

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

---

### `processes.tree`

Get the process tree rooted at a given PID.

**Params**:

| Field | Type   | Required | Description   |
|-------|--------|----------|---------------|
| `pid` | number | yes      | Root PID      |

**Returns**: array of process objects (same shape as `processes.list`).

---

### `terminals.list`

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

---

### `terminals.search`

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

### `ocr.snapshot`

Get the current in-memory OCR results for all visible windows. Each result
includes the full extracted text and individual text blocks with bounding
boxes and confidence scores.

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

| Field       | Type     | Description                                    |
|-------------|----------|------------------------------------------------|
| `wid`       | number   | CGWindowID                                     |
| `app`       | string   | Application name                               |
| `title`     | string   | Window title                                   |
| `frame`     | object   | Window position and size                       |
| `fullText`  | string   | All recognized text concatenated               |
| `blocks`    | array    | Individual text blocks with positions           |
| `timestamp` | number   | Unix timestamp of the scan                     |

Each block contains:

| Field        | Type   | Description                           |
|--------------|--------|---------------------------------------|
| `text`       | string | Recognized text                       |
| `confidence` | number | Vision confidence score (0.0–1.0)     |
| `x, y, w, h` | number | Normalized bounding box (0.0–1.0)    |

---

### `ocr.search`

Full-text search across OCR history using SQLite FTS5. Supports boolean
operators, phrase queries, and prefix matching.

**Params**:

| Field   | Type    | Required | Description                              |
|---------|---------|----------|------------------------------------------|
| `query` | string  | yes      | FTS5 search query                        |
| `app`   | string  | no       | Filter by application name               |
| `limit` | number  | no       | Max results (default 50)                 |
| `live`  | boolean | no       | Search live snapshot instead of history (default false) |

**Returns**: array of search result objects:

```json
[
  {
    "id": 42,
    "wid": 1234,
    "app": "Code",
    "title": "main.swift",
    "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
    "fullText": "func applicationDidFinishLaunching...",
    "snippet": "func <b>applicationDidFinishLaunching</b>...",
    "timestamp": 1709568000.0
  }
]
```

**FTS5 query examples**:

| Query              | Matches                                   |
|--------------------|-------------------------------------------|
| `error`            | Any window containing "error"             |
| `"build failed"`   | Exact phrase match                        |
| `error OR warning` | Either term                               |
| `npm AND dev`      | Both terms present                        |
| `react*`           | Prefix match (react, reactive, reactDOM)  |

---

### `ocr.history`

Get the OCR timeline for a specific window, ordered by most recent first.
Useful for tracking what content appeared in a window over time.

**Params**:

| Field   | Type   | Required | Description                |
|---------|--------|----------|----------------------------|
| `wid`   | number | yes      | CGWindowID                 |
| `limit` | number | no       | Max results (default 50)   |

**Returns**: array of search result objects (same shape as `ocr.search`).

---

### `api.schema`

Return the full API schema including version, models, and method definitions.

**Params**: none

**Returns**: a structured schema object describing all registered endpoints,
their parameters, return types, and data models. Useful for agent
self-discovery.

---

## Write methods

### `session.launch`

Launch a new tmux session for a project.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |

**Returns**: `{ "ok": true }`

**Errors**: `Not found` if the path isn't in the scanned project list.
Run `projects.scan` first if needed.

**Notes**: If a session already exists for this project, it will be
reattached. The project must be in the scanned project list — call
`projects.list` to check, or `projects.scan` to refresh.

---

### `session.kill`

Kill a tmux session by name.

**Params**:

| Field  | Type   | Required | Description         |
|--------|--------|----------|---------------------|
| `name` | string | yes      | Session name        |

**Returns**: `{ "ok": true }`

---

### `session.detach`

Detach all clients from a session (keeps it running).

**Params**:

| Field  | Type   | Required | Description         |
|--------|--------|----------|---------------------|
| `name` | string | yes      | Session name        |

**Returns**: `{ "ok": true }`

---

### `session.sync`

Reconcile a running session to match its declared `.lattices.json` config.
Recreates missing panes, re-applies layout, restores labels, re-runs
commands in idle panes.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |

**Returns**: `{ "ok": true }`

**Errors**: `Not found` if the path isn't in the project list.

---

### `session.restart`

Restart a specific pane's process within a session.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |
| `pane` | string | no       | Pane name to restart (defaults to first pane) |

**Returns**: `{ "ok": true }`

**Errors**: `Not found` if the path isn't in the project list.

---

### `window.tile`

Tile a session's terminal window to a screen position.

**Params**:

| Field      | Type   | Required | Description                         |
|------------|--------|----------|-------------------------------------|
| `session`  | string | yes      | Session name                        |
| `position` | string | yes      | Tile position (see below)           |

**Positions**: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`,
`bottom-left`, `bottom-right`, `left-third`, `center-third`, `right-third`,
`maximize`, `center`

**Returns**: `{ "ok": true }`

---

### `window.focus`

Focus a window — bring it to front and switch Spaces if needed.

**Params** (one of):

| Field     | Type   | Required | Description                     |
|-----------|--------|----------|---------------------------------|
| `wid`     | number | no       | CGWindowID (any window)         |
| `session` | string | no       | Session name (lattices windows)  |

Provide either `wid` or `session`. If `wid` is given, it takes priority.

**Returns**: `{ "ok": true }` (with `wid` and `app` if focused by wid)

---

### `window.move`

Move a session's window to a different macOS Space.

**Params**:

| Field     | Type   | Required | Description                |
|-----------|--------|----------|----------------------------|
| `session` | string | yes      | Session name               |
| `spaceId` | number | yes      | Target Space ID (from `spaces.list`) |

**Returns**: `{ "ok": true }`

---

### `layer.switch`

Switch the active workspace layer.

**Params**:

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| `index` | number | yes      | Layer index (0-based)          |

**Returns**: `{ "ok": true }`

**Notes**: This focuses and tiles all windows in the target layer,
launches any projects that aren't running yet, and posts a
`layer.switched` event.

---

### `group.launch`

Launch a tab group session.

**Params**:

| Field | Type   | Required | Description      |
|-------|--------|----------|------------------|
| `id`  | string | yes      | Group ID         |

**Returns**: `{ "ok": true }`

**Errors**: `Not found` if the group ID doesn't match any configured group.

---

### `group.kill`

Kill a tab group session.

**Params**:

| Field | Type   | Required | Description      |
|-------|--------|----------|------------------|
| `id`  | string | yes      | Group ID         |

**Returns**: `{ "ok": true }`

**Errors**: `Not found` if the group ID doesn't match any configured group.

---

### `ocr.scan`

Trigger an immediate OCR scan of all visible windows, bypassing the
periodic timer. The scan runs asynchronously — results will be available
via `ocr.snapshot` once complete, and an `ocr.scanComplete` event is
broadcast to all connected clients.

**Params**: none

**Returns**: `{ "ok": true }`

---

### `projects.scan`

Trigger a re-scan of the project directory. Useful after cloning a new
repo or adding a `.lattices.json` config.

**Params**: none

**Returns**: `{ "ok": true }`

---

### `layout.distribute`

Distribute all visible lattices windows evenly across the screen.

**Params**: none

**Returns**: `{ "ok": true }`

---

## Events

Events are pushed to all connected WebSocket clients when state changes.
They have no `id` field — listen for messages with an `event` field.

### `windows.changed`

Fired when the desktop window list changes (windows opened, closed,
moved, or resized). Fires immediately on each change — not debounced.

```json
{
  "event": "windows.changed",
  "data": {
    "windowCount": 12,
    "added": [1234],
    "removed": [5678]
  }
}
```

| Field         | Type     | Description                        |
|---------------|----------|------------------------------------|
| `windowCount` | number   | Total window count after change    |
| `added`       | number[] | Window IDs that appeared           |
| `removed`     | number[] | Window IDs that disappeared        |

---

### `tmux.changed`

Fired when tmux sessions change (created, killed, panes added/removed).

```json
{
  "event": "tmux.changed",
  "data": {
    "sessionCount": 3,
    "sessions": ["myapp-a1b2c3", "api-d4e5f6"]
  }
}
```

| Field          | Type     | Description                   |
|----------------|----------|-------------------------------|
| `sessionCount` | number   | Total session count           |
| `sessions`     | string[] | Session names                 |

---

### `layer.switched`

Fired when the active workspace layer changes.

```json
{
  "event": "layer.switched",
  "data": {
    "index": 1
  }
}
```

| Field   | Type   | Description                  |
|---------|--------|------------------------------|
| `index` | number | Index of the now-active layer |

---

### `ocr.scanComplete`

Fired when an OCR scan cycle finishes (periodic or manually triggered).

```json
{
  "event": "ocr.scanComplete",
  "data": {
    "windowCount": 12,
    "totalBlocks": 342
  }
}
```

| Field         | Type   | Description                                |
|---------------|--------|--------------------------------------------|
| `windowCount` | number | Number of windows scanned                  |
| `totalBlocks` | number | Total text blocks recognized across all windows |

---

### `processes.changed`

Fired when the set of interesting developer processes changes
(editors, servers, build tools starting or stopping).

```json
{
  "event": "processes.changed",
  "data": {
    "interestingCount": 5,
    "pids": [1234, 5678, 9012]
  }
}
```

| Field              | Type     | Description                           |
|--------------------|----------|---------------------------------------|
| `interestingCount` | number   | Count of interesting developer processes |
| `pids`             | number[] | PIDs of those processes               |

---

## Agent integration patterns

### CLAUDE.md snippet

Add this to your project's `CLAUDE.md` so any AI agent working in the
project knows how to control the workspace:

```markdown
## Workspace Control

This project uses lattices for workspace management. The daemon API
is available at ws://127.0.0.1:9399.

### Available commands
- List windows: `daemonCall('windows.list')`
- List sessions: `daemonCall('tmux.sessions')`
- Launch a project: `daemonCall('session.launch', { path: '/absolute/path' })`
- Tile a window: `daemonCall('window.tile', { session: 'name', position: 'left' })`
- Switch layer: `daemonCall('layer.switch', { index: 0 })`

### Import
\```js
import { daemonCall } from '@arach/lattices/daemon-client'
\```
```

### Multi-agent orchestration

An orchestrator agent can set up the full workspace for sub-agents:

```js
import { daemonCall } from '@arach/lattices/daemon-client'

// Discover what's available
const projects = await daemonCall('projects.list')

// Launch the projects we need
await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('session.launch', { path: '/Users/you/dev/api' })

// Tile them side by side
const sessions = await daemonCall('tmux.sessions')
const fe = sessions.find(s => s.name.startsWith('frontend'))
const api = sessions.find(s => s.name.startsWith('api'))

await daemonCall('window.tile', { session: fe.name, position: 'left' })
await daemonCall('window.tile', { session: api.name, position: 'right' })
```

### OCR-powered context awareness

Agents can read what's on screen to gain context about the user's work:

```js
import { daemonCall } from '@arach/lattices/daemon-client'

// Search all windows for error messages
const errors = await daemonCall('ocr.search', { query: 'error OR failed OR exception' })
for (const result of errors) {
  console.log(`[${result.app}] ${result.title}: ${result.snippet}`)
}

// Get current content of a specific window
const snapshot = await daemonCall('ocr.snapshot')
const terminal = snapshot.find(w => w.app === 'Terminal')
console.log('Terminal says:', terminal?.fullText)

// Track what happened in a window over time
const history = await daemonCall('ocr.history', { wid: 1234, limit: 10 })
```

The OCR system scans visible windows every 30 seconds using Apple's Vision
framework. Use `ocr.scan` to trigger an immediate scan, then read results
with `ocr.snapshot`. Historical data is stored in SQLite FTS5 and
searchable via `ocr.search`. Entries older than 3 days are automatically
purged.

### Reactive event pattern

Subscribe to events for real-time workspace awareness:

```js
import WebSocket from 'ws' // or use the built-in client

const ws = new WebSocket('ws://127.0.0.1:9399')

ws.on('message', (raw) => {
  const msg = JSON.parse(raw)

  if (msg.event === 'tmux.changed') {
    console.log('Sessions:', msg.data.sessions.join(', '))
  }

  if (msg.event === 'windows.changed') {
    console.log('Windows:', msg.data.windowCount, 'total')
    if (msg.data.added.length) console.log('  Added:', msg.data.added)
    if (msg.data.removed.length) console.log('  Removed:', msg.data.removed)
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
import { isDaemonRunning, daemonCall } from '@arach/lattices/daemon-client'

if (!(await isDaemonRunning())) {
  console.error('lattices daemon is not running — start it with: lattices app')
  process.exit(1)
}

const status = await daemonCall('daemon.status')
console.log(`Daemon up for ${Math.round(status.uptime)}s, tracking ${status.windowCount} windows`)
```
