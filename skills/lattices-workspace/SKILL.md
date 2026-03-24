---
name: lattices-workspace
description: Control a macOS developer workspace via the Lattices daemon API. Use when managing windows, tiling layouts, launching terminal sessions, searching screen text, switching workspace layers, or automating desktop workflows. Activates on "lattices", "tile windows", "workspace layout", "screen text", "session layers", or any desktop automation task on macOS.
compatibility: Requires macOS with the Lattices menu bar app running (ws://127.0.0.1:9399). Node.js 18+ for the client library.
metadata:
  author: arach
  version: "0.3.0"
---

# Lattices Workspace Control

Lattices is a macOS developer workspace manager with a native menu bar app that exposes full desktop control over WebSocket. You can list windows, tile them, launch terminal sessions, search screen text via OCR, manage workspace layers, and react to real-time events.

## Connection

The daemon runs at `ws://127.0.0.1:9399`. JSON-RPC over WebSocket — no auth, no handshake.

### Node.js (recommended)

```js
import { daemonCall, isDaemonRunning } from '@lattices/cli'

// Check if daemon is up
if (await isDaemonRunning()) {
  const windows = await daemonCall('windows.list')
}
```

### Raw WebSocket (any language)

```json
{"id":"1","method":"windows.list"}
→ {"id":"1","result":[{"wid":1234,"app":"Terminal","title":"zsh",...}]}
```

### Self-discovery

Call `api.schema` to get the full method/model definitions at runtime:

```js
const schema = await daemonCall('api.schema')
// Returns { version, models[], methods[] } with params, types, descriptions
```

## Core Methods

### Windows

| Method | Description |
|--------|-------------|
| `windows.list` | All tracked windows with app, title, frame, spaceIds |
| `windows.get` | Single window by `{ wid }` |
| `windows.search` | Search by title, app, or OCR text `{ query }` |
| `window.tile` | Snap window `{ wid, position }` — positions: left, right, maximize, center, top-left, top-right, bottom-left, bottom-right |
| `window.focus` | Focus window `{ wid }` or `{ session }` — switches Spaces if needed |
| `layout.distribute` | Distribute all visible windows evenly |

### Sessions (tmux)

| Method | Description |
|--------|-------------|
| `session.launch` | Create or reattach `{ path }` — auto-detects dev command |
| `tmux.sessions` | List lattices-tracked sessions |
| `session.kill` | Kill session `{ name }` |
| `session.sync` | Reconcile session to its config |
| `session.restart` | Restart a pane process |
| `projects.list` | All discovered projects with status |

### Screen Text (OCR)

| Method | Description |
|--------|-------------|
| `ocr.search` | Full-text search across all indexed windows `{ query }` |
| `ocr.snapshot` | Current OCR for all visible windows |
| `ocr.scan` | Trigger immediate Vision OCR scan |
| `ocr.recent` | Recent OCR entries across all windows |

### Session Layers (dynamic window groups)

| Method | Description |
|--------|-------------|
| `session.layers.create` | Create named layer `{ name, windowIds? }` |
| `session.layers.list` | All layers with activeIndex |
| `session.layers.switch` | Switch by `{ index }` or `{ name }` |
| `session.layers.assign` | Add windows `{ layerName, wid }` |
| `session.layers.remove` | Remove window ref `{ layerName, refId }` |
| `session.layers.delete` | Delete layer `{ name }` |
| `session.layers.clear` | Clear all session layers |

### Config Layers (from workspace.json)

| Method | Description |
|--------|-------------|
| `layers.list` | Configured layers and active index |
| `layer.switch` | Switch by `{ index }` or `{ name }` |

## Real-Time Events

Hold a WebSocket connection open to receive broadcasts (no `id` field):

```js
// Events arrive as: {"event":"windows.changed","data":{...}}
```

| Event | Data |
|-------|------|
| `windows.changed` | `{ windowCount, added[], removed[] }` |
| `tmux.changed` | `{ sessionCount, sessions[] }` |
| `layer.switched` | `{ index, name }` |
| `processes.changed` | `{ interestingCount, pids[] }` |
| `ocr.scanComplete` | `{ windowCount, totalBlocks }` |

## Common Patterns

### Launch and tile two projects side by side

```js
await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('session.launch', { path: '/Users/you/dev/api' })

const sessions = await daemonCall('tmux.sessions')
await daemonCall('window.tile', { session: sessions[0].name, position: 'left' })
await daemonCall('window.tile', { session: sessions[1].name, position: 'right' })
```

### Find text across all windows

```js
const results = await daemonCall('ocr.search', { query: 'TODO' })
// Returns windows containing "TODO" with matched text blocks
```

### Create a focus layer and switch to it

```js
await daemonCall('session.layers.create', {
  name: 'review',
  windowIds: [1234, 5678]  // CGWindowIDs from windows.list
})
await daemonCall('session.layers.switch', { name: 'review' })
```

### React to workspace changes

```js
const ws = new WebSocket('ws://127.0.0.1:9399')
ws.onmessage = (raw) => {
  const msg = JSON.parse(raw.data)
  if (msg.event === 'windows.changed') {
    // A window was opened or closed
  }
  if (msg.event === 'layer.switched') {
    // User switched layers via hotkey
  }
}
```

## Error Handling

`daemonCall` throws on errors. Always wrap in try/catch:

```js
try {
  await daemonCall('session.launch', { path: '/nonexistent' })
} catch (err) {
  // err.message: "Not found", "Missing parameter: ...", "Unknown method: ..."
  // ECONNREFUSED means daemon is not running
}
```

## CLI Fallback

If the daemon isn't running, you can use the CLI directly:

```bash
lattices ls                    # list sessions
lattices ~/dev/myapp           # launch session
lattices tile left             # tile frontmost window
lattices scan search "error"   # search screen text
lattices layer 0               # switch layer
lattices daemon status         # check daemon health
```

## Intents (Voice & Agent Automation)

Lattices exposes a structured intent system for voice control and cross-service integration.

| Method | Description |
|--------|-------------|
| `intents.list` | Discover all intents with examples and typed slots |
| `intents.execute` | Execute an intent `{ intent, slots, rawText?, source? }` |

Available intents: `tile_window`, `focus`, `launch`, `switch_layer`, `search`, `list_windows`, `list_sessions`, `distribute`, `create_layer`, `kill`, `scan`

```js
// Voice service integration: fetch catalog, extract intent, execute
const catalog = await daemonCall('intents.list')
// → [{ intent, description, examples[], slots[] }]

await daemonCall('intents.execute', {
  intent: 'tile_window',
  slots: { position: 'left', app: 'Chrome' },
  rawText: 'put Chrome on the left',
  source: 'vox'
})
```

See [Intent Protocol](references/INTENTS.md) for the full catalog and voice integration pattern.

## References

- [API Reference](references/API.md) — full method docs with params and return types
- [Intent Protocol](references/INTENTS.md) — voice control and cross-service integration
- [Configuration](references/CONFIG.md) — .lattices.json format and CLI commands
- [Layers & Groups](references/LAYERS.md) — workspace organization patterns
- [Architecture](references/ARCHITECTURE.md) — how sessions, tiling, and the daemon work together
