---
title: Daemon API
description: WebSocket API reference for programmatic control of lattice
order: 5
---

# Daemon API

The lattice menu bar app runs a WebSocket daemon on `ws://127.0.0.1:9399`.
It exposes 20 RPC methods and 3 real-time events — everything the app
can do, agents and scripts can do too.

## Who this is for

- **AI coding agents** that need to discover projects, launch sessions,
  tile windows, and switch contexts without human interaction
- **Scripts and automation** — CI, dotfile bootstraps, workspace setup
- **Custom tools** — build your own launcher, dashboard, or orchestrator

## Quick start

1. Launch the daemon (it starts with the menu bar app):

```bash
lattice app
```

2. Check that it's running:

```bash
lattice daemon status
```

3. Call a method from Node.js:

```js
import { daemonCall } from 'lattice/daemon-client'

const windows = await daemonCall('windows.list')
console.log(windows) // [{ wid, app, title, frame, ... }, ...]
```

Or from any language — it's a standard WebSocket:

```bash
# Plain websocat example
echo '{"id":"1","method":"daemon.status"}' | websocat ws://127.0.0.1:9399
```

## Wire protocol

lattice uses a JSON-RPC-style protocol over WebSocket on port **9399**.

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

## Node.js client

lattice ships a zero-dependency WebSocket client that works with
Node.js 18+. It handles connection, framing, and request/response
matching internally.

### `daemonCall(method, params?, timeoutMs?)`

Send an RPC call and await the response.

```js
import { daemonCall } from 'lattice/daemon-client'

// Read-only
const status = await daemonCall('daemon.status')
const windows = await daemonCall('windows.list')
const win = await daemonCall('windows.get', { wid: 1234 })

// Mutations
await daemonCall('session.launch', { path: '/Users/you/dev/myapp' })
await daemonCall('window.tile', { session: 'myapp-a1b2c3', position: 'left' })

// Custom timeout (default: 5000ms)
await daemonCall('projects.scan', null, 10000)
```

**Returns** the `result` field from the response.
**Throws** if the daemon returns an error, the connection fails, or the timeout is reached.

### `isDaemonRunning()`

Check if the daemon is reachable.

```js
import { isDaemonRunning } from 'lattice/daemon-client'

if (await isDaemonRunning()) {
  console.log('daemon is up')
}
```

Returns `true` if `daemon.status` responds within 1 second.

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
    "title": "[lattice:myapp-a1b2c3] zsh",
    "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
    "spaceIds": [1],
    "isOnScreen": true,
    "latticeSession": "myapp-a1b2c3"
  }
]
```

The `latticeSession` field is present only on windows that belong to
a lattice session (matched via the `[lattice:name]` title tag).

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

List tmux sessions that belong to lattice.

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

List all tmux sessions including orphans (sessions not tracked by lattice).

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

Reconcile a running session to match its declared `.lattice.json` config.
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
`bottom-left`, `bottom-right`, `maximize`, `center`

**Returns**: `{ "ok": true }`

---

### `window.focus`

Focus a window — bring it to front and switch Spaces if needed.

**Params** (one of):

| Field     | Type   | Required | Description                     |
|-----------|--------|----------|---------------------------------|
| `wid`     | number | no       | CGWindowID (any window)         |
| `session` | string | no       | Session name (lattice windows)  |

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

### `projects.scan`

Trigger a re-scan of the project directory. Useful after cloning a new
repo or adding a `.lattice.json` config.

**Params**: none

**Returns**: `{ "ok": true }`

---

## Events

Events are pushed to all connected WebSocket clients when state changes.
They have no `id` field — listen for messages with an `event` field.

### `windows.changed`

Fired when the desktop window list changes (windows opened, closed,
moved, or resized).

```json
{
  "event": "windows.changed",
  "data": {
    "windows": [ ... ],
    "added": [1234],
    "removed": [5678]
  }
}
```

| Field     | Type     | Description                        |
|-----------|----------|------------------------------------|
| `windows` | array    | Full current window list           |
| `added`   | number[] | Window IDs that appeared           |
| `removed` | number[] | Window IDs that disappeared        |

---

### `tmux.changed`

Fired when tmux sessions change (created, killed, panes added/removed).

```json
{
  "event": "tmux.changed",
  "data": {
    "sessions": [ ... ]
  }
}
```

| Field      | Type  | Description              |
|------------|-------|--------------------------|
| `sessions` | array | Full current session list |

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

## Agent integration patterns

### CLAUDE.md snippet

Add this to your project's `CLAUDE.md` so any AI agent working in the
project knows how to control the workspace:

```markdown
## Workspace Control

This project uses lattice for workspace management. The daemon API
is available at ws://127.0.0.1:9399.

### Available commands
- List windows: `daemonCall('windows.list')`
- List sessions: `daemonCall('tmux.sessions')`
- Launch a project: `daemonCall('session.launch', { path: '/absolute/path' })`
- Tile a window: `daemonCall('window.tile', { session: 'name', position: 'left' })`
- Switch layer: `daemonCall('layer.switch', { index: 0 })`

### Import
\```js
import { daemonCall } from 'lattice/daemon-client'
\```
```

### Multi-agent orchestration

An orchestrator agent can set up the full workspace for sub-agents:

```js
import { daemonCall } from 'lattice/daemon-client'

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

### Reactive event pattern

Subscribe to events for real-time workspace awareness:

```js
import WebSocket from 'ws' // or use the built-in client

const ws = new WebSocket('ws://127.0.0.1:9399')

ws.on('message', (raw) => {
  const msg = JSON.parse(raw)

  if (msg.event === 'tmux.changed') {
    console.log('Sessions changed:', msg.data.sessions.length, 'active')
  }

  if (msg.event === 'windows.changed') {
    const latticeWindows = msg.data.windows.filter(w => w.latticeSession)
    console.log('Lattice windows:', latticeWindows.length)
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
import { isDaemonRunning, daemonCall } from 'lattice/daemon-client'

if (!(await isDaemonRunning())) {
  console.error('lattice daemon is not running — start it with: lattice app')
  process.exit(1)
}

const status = await daemonCall('daemon.status')
console.log(`Daemon up for ${Math.round(status.uptime)}s, tracking ${status.windowCount} windows`)
```
