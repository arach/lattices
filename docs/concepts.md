---
title: Concepts
description: Core ideas, glossary, and architecture of lattices
order: 1
---

# Concepts

## What is lattices?

lattices is a developer workspace launcher. It creates pre-configured
terminal layouts for your projects using tmux, so you can go from
"I want to work on X" to a full development environment in one click.

It has two parts:

1. **CLI** (`lattices`) — creates and manages tmux sessions from the terminal
2. **Menu bar app** — a native macOS companion for launching, tiling,
   and navigating sessions with a command palette

## Glossary

### Daemon
The lattices daemon is a WebSocket server (`ws://127.0.0.1:9399`) that
runs inside the menu bar app. It exposes 20 RPC methods and 3 real-time
events, giving scripts and AI agents full programmatic control over
sessions, windows, layers, and projects. See the
[API reference](/docs/api).

### Agent
Any program that calls the daemon API to control the workspace
autonomously — an AI coding agent, a shell script, a CI pipeline,
or a custom tool. Agents can discover projects, launch sessions, tile
windows, switch layers, and react to real-time events without human
interaction.

### Session
A tmux session is a persistent workspace that lives in the background.
It survives terminal crashes, disconnects, and even closing your laptop.
Think of it as a virtual desktop for a single project.

### Pane
A pane is a single terminal view inside a session. A typical lattices
setup has two panes side by side — one running Claude Code and one
running your dev server. You can have up to four or more.

### Attach / Detach
Attaching connects your terminal window to an existing session.
Detaching disconnects your terminal but keeps the session alive.
Your dev server keeps running, Claude keeps thinking — nothing is lost.

### tmux
tmux (terminal multiplexer) is the engine behind lattices. It manages
sessions, panes, and layouts. lattices configures tmux for you so you
don't need to learn tmux commands — but knowing a few shortcuts helps.

### Multiplexer
A program that lets you run multiple terminal sessions inside a single
window and switch between them. tmux is the most popular one.

### Sync / Reconcile
Sync (`lattices sync`) brings a running session back in line with its
declared config. It recreates missing panes, re-applies the layout,
restores labels, and re-runs commands in idle panes. Useful when a pane
was accidentally killed but you don't want to restart the whole session.

### Ensure / Prefill
Two modes for restoring exited commands when you reattach to a session:

- **Ensure** — automatically re-runs the command (hands-free recovery)
- **Prefill** — types the command into the pane but waits for you to
  press Enter (manual confirmation)

Set via `"ensure": true` or `"prefill": true` in `.lattices.json`.

### Command Palette
The menu bar app's primary interface, opened with **Cmd+Shift+M**.
A searchable list of actions: launch/attach projects, tile windows,
sync sessions, restart panes, open settings.

### Window Tiling
Both the CLI (`lattices tile`) and the menu bar app can snap terminal
windows to preset screen positions (halves, quarters, maximize, center).
Tiling uses AppleScript bounds and respects the menu bar and dock.

## How it works

1. You create a `.lattices.json` file in your project root (or run `lattices init`)
2. lattices reads the config and creates a tmux session with your layout
3. Each pane gets its command (claude, dev server, tests, etc.)
4. The session persists in the background until you kill it
5. You can attach/detach from any terminal at any time
6. If `ensure` is enabled, exited commands auto-restart on reattach

## Architecture

### Four-layer stack

```
┌─────────────────────────────┐
│  AI Agents / Scripts        │  ← daemon API: 20 RPC methods, real-time events
├─────────────────────────────┤
│  Menu bar app (Swift/AppKit)│  ← GUI: command palette, tiling, project list
├─────────────────────────────┤
│  CLI (Node.js)              │  ← lattices, lattices sync, lattices restart ...
├─────────────────────────────┤
│  tmux                       │  ← session/pane lifecycle, layout, persistence
└─────────────────────────────┘
```

- The **CLI** talks to tmux directly via `tmux` shell commands.
- The **menu bar app** calls the CLI binary for session operations
  (launch, sync, restart) and uses tmux directly for status checks
  (has-session, list-panes). It also runs the **daemon** — a WebSocket
  server on `ws://127.0.0.1:9399`.
- **Agents and scripts** connect to the daemon over WebSocket and can
  do everything the app and CLI can do: discover projects, launch
  sessions, tile windows, switch layers, and subscribe to real-time
  events.
- All layers share the same session naming convention so they always
  agree on which session belongs to which project.

### Session naming

A session name is `<basename>-<hash>`, where:

- `basename` is the project directory name (non-alphanumeric chars replaced with `-`)
- `hash` is the first 6 hex chars of the SHA-256 of the full absolute path

This guarantees unique session names even if two projects share the
same directory name (e.g. `~/work/app` and `~/personal/app`).

Both the CLI (Node.js `crypto.createHash`) and the app (Swift
`CryptoKit.SHA256`) produce identical hashes.

### Window discovery via title tags

When lattices creates a session, it sets the tmux option:

```
set-titles-string "[lattices:<session-name>] #{pane_title}"
```

This embeds a `[lattices:name]` tag in the terminal window title. The
menu bar app uses this tag to find windows via three fallback paths:

1. **CGWindowList** (needs Screen Recording permission) — fastest,
   reads window names from the window server
2. **Accessibility API** (needs Accessibility permission) — queries
   AXUIElement window titles for the terminal app
3. **AppleScript** — iterates Terminal.app or iTerm2 windows by name

### Space switching via SkyLight

The menu bar app can switch macOS Spaces to reach a session's window.
It uses private SkyLight framework APIs loaded at runtime via `dlopen`:

- `CGSMainConnectionID` — get the connection to the window server
- `CGSGetActiveSpace` — current Space ID
- `CGSCopyManagedDisplaySpaces` — enumerate all Spaces per display
- `SLSCopySpacesForWindows` — find which Space a window is on
- `SLSManagedDisplaySetCurrentSpace` — switch a display to a Space

This is the same approach used by [Loop](https://github.com/MrKai77/Loop)
and other macOS window managers.

### Ensure/prefill restoration

When you run `lattices` (no arguments) and a session already exists:

1. lattices checks the `ensure` / `prefill` flag in `.lattices.json`
2. For each pane, it queries `#{pane_current_command}` via tmux
3. If the pane is running a shell (bash, zsh, fish, sh, dash) — meaning
   the original command has exited — it either:
   - **ensure**: sends the command + Enter (auto-restart)
   - **prefill**: sends the command without Enter (manual restart)
4. Then it attaches to the session as normal

## Agentic architecture

lattices is designed for programmatic control. The daemon API gives
agents the same capabilities as a human using the menu bar app:

- **Discover** — list projects, sessions, windows, and Spaces
- **Launch** — start sessions for any scanned project
- **Arrange** — tile windows to screen positions, move between Spaces
- **Monitor** — subscribe to `windows.changed`, `tmux.changed`, and
  `layer.switched` events for real-time workspace awareness
- **Recover** — sync sessions back to their declared config, restart
  failed panes

An orchestrator agent can set up an entire multi-project workspace in
a few calls:

```js
import { daemonCall } from 'lattices/daemon-client'

await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('session.launch', { path: '/Users/you/dev/api' })

const sessions = await daemonCall('tmux.sessions')
await daemonCall('window.tile', { session: sessions[0].name, position: 'left' })
await daemonCall('window.tile', { session: sessions[1].name, position: 'right' })
```

See the [Daemon API reference](/docs/api) for the full method list,
event shapes, and integration patterns.

## Key shortcuts (inside tmux)

These work when you're inside a tmux session:

| Shortcut       | Action                |
|----------------|-----------------------|
| Ctrl+B  D      | Detach from session   |
| Ctrl+B  X      | Kill current pane     |
| Ctrl+B  Left   | Move to left pane     |
| Ctrl+B  Right  | Move to right pane    |
| Ctrl+B  Up     | Move to pane above    |
| Ctrl+B  Down   | Move to pane below    |
| Ctrl+B  Z      | Zoom pane (toggle)    |
| Ctrl+B  [      | Scroll mode (q exits) |

The prefix `Ctrl+B` means: hold Control, press B, release both,
then press the next key.
