<picture>
  <img alt="lattices" src="site/public/og.png" />
</picture>

# lattices

macOS workspace manager. Tile windows, switch between projects,
read on-screen text with OCR, and optionally run persistent tmux
sessions. There's a menu bar app, a CLI, and a WebSocket API with
30 methods so your AI agents can do all of this too.

## Install

```sh
npm install -g @arach/lattices
```

## Quick start

```sh
# Launch the menu bar app
lattices app

# Open the command palette from anywhere
# Cmd+Shift+M
```

The app scans your projects and gives you a command palette for
everything. If you want persistent terminal sessions, add tmux:

```sh
brew install tmux
cd my-project && lattices
```

That creates a tmux session with Claude Code on the left and your
dev server on the right. Detach, close your laptop, come back later,
reattach. Everything is where you left it.

## What's in the box

The menu bar app is the main thing. It gives you a command palette
(`Cmd+Shift+M`), window tiling, project discovery, workspace layers,
OCR, and runs a WebSocket daemon on `ws://127.0.0.1:9399`. Works
with or without tmux.

The CLI does tiling, session management, OCR queries, and tab groups.

The daemon exposes 30 RPC methods and 5 real-time events. Anything
you can do from the app, an agent can do over WebSocket.

```js
import { daemonCall } from '@arach/lattices/daemon-client'

const windows = await daemonCall('windows.list')
await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('window.tile', { session: 'frontend-a1b2c3', position: 'left' })
```

## Configuration

Drop a `.lattices.json` in your project root:

```json
{
  "ensure": true,
  "panes": [
    { "name": "claude", "cmd": "claude", "size": 60 },
    { "name": "server", "cmd": "pnpm dev" },
    { "name": "tests",  "cmd": "pnpm test --watch" }
  ]
}
```

Or skip it. Without a config, lattices reads your `package.json` and
picks the right dev command automatically.

### Layouts

```
2 panes              3+ panes

┌──────────┬───────┐ ┌──────────┬───────┐
│  claude  │server │ │  claude  │server │
│  (60%)   │(40%)  │ │  (60%)   ├───────┤
└──────────┴───────┘ │          │tests  │
                     └──────────┴───────┘
```

## Workspace layers

Group projects into switchable contexts. `Cmd+Option+1` tiles your
frontend and API side by side. `Cmd+Option+2` for the mobile stack.
Sessions stay alive across switches.

Configure in `~/.lattices/workspace.json`:

```json
{
  "layers": [
    {
      "id": "web", "label": "Web",
      "projects": [
        { "path": "/Users/you/dev/frontend", "tile": "left" },
        { "path": "/Users/you/dev/api", "tile": "right" }
      ]
    }
  ]
}
```

## Tab groups

Bundle related repos as tabs in one session. Each tab gets its own
pane layout from its `.lattices.json`.

```sh
lattices group talkie      # Launch iOS, macOS, Web, API as tabs
lattices tab talkie iOS    # Switch to the iOS tab
```

## Screen OCR

The app reads text from visible windows using Apple Vision and indexes
it with FTS5. You or your agents can search for error messages, read
terminal output, find content across windows.

```js
await daemonCall('ocr.scan')
const errors = await daemonCall('ocr.search', { query: 'error OR failed' })
```

## CLI

```
lattices                    Create or reattach to session
lattices init               Generate .lattices.json
lattices ls                 List active sessions
lattices kill [name]        Kill a session
lattices tile <position>    Tile frontmost window
lattices group [id]         Launch or attach a tab group
lattices tab <group> [tab]  Switch tab within a group
lattices ocr                View current OCR snapshot
lattices ocr search <query> Search OCR history
lattices app                Launch the menu bar app
lattices help               Show help
```

## Requirements

- macOS 13.0+
- Node.js 18+

### Optional

- tmux for persistent terminal sessions (`brew install tmux`)
- Swift 5.9+ to build the menu bar app from source

## Docs

[lattices.dev/docs](https://lattices.dev/docs/overview)

## License

MIT
