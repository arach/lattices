---
title: Concepts
description: Core ideas, glossary, and architecture of lattices
order: 6
---

## Glossary

| Term | Definition |
|------|------------|
| **Command Palette** | The menu bar app's primary interface (**Cmd+Shift+M**). Searchable list of actions: launch, tile, sync, restart, settings. |
| **Window Tiling** | Snap terminal windows to preset screen positions (halves, quarters, thirds, maximize, center). Works from the CLI (`lattices tile`) or the command palette. |
| **Daemon** | WebSocket server (`ws://127.0.0.1:9399`) inside the menu bar app. Exposes 30 RPC methods and 5 real-time events for programmatic control. See the [API reference](/docs/api). |
| **Agent** | Any program that calls the daemon API autonomously — an AI coding agent, a shell script, a CI pipeline, or a custom tool. |
| **Session** | A persistent tmux workspace that lives in the background. Survives terminal crashes, disconnects, and closing your laptop. One session per project. Requires tmux. |
| **Pane** | A single terminal view inside a session. A typical setup has two panes side by side — Claude Code on the left, dev server on the right. Requires tmux. |
| **Attach / Detach** | Attaching connects your terminal to an existing session. Detaching disconnects but keeps the session alive — your dev server keeps running, Claude keeps thinking. Requires tmux. |
| **Sync / Reconcile** | `lattices sync` brings a running session back in line with its declared config — recreates missing panes, re-applies layout, restores labels, re-runs commands in idle panes. Requires tmux. |
| **Ensure / Prefill** | Two modes for restoring exited commands on reattach. **Ensure** auto-reruns the command. **Prefill** types it but waits for you to press Enter. Set via `.lattices.json`. Requires tmux. |
| **tmux** | Terminal multiplexer (optional). Provides persistent sessions, pane layouts, and command restoration. Install with `brew install tmux` if you want session management. |

## How it works

1. You create a `.lattices.json` file in your project root (or run `lattices init`)
2. The menu bar app discovers the project and adds it to the command palette
3. You can tile windows, switch layers, search via OCR, and use the daemon API
4. With tmux installed, `lattices` also creates persistent terminal sessions:
   - Each pane gets its command (claude, dev server, tests, etc.)
   - The session persists in the background until you kill it
   - You can attach/detach from any terminal at any time
   - If `ensure` is enabled, exited commands auto-restart on reattach

## Architecture

<img src="/architecture.svg" alt="lattices architecture diagram" style="margin: 2rem 0; max-width: 100%;" />

- The menu bar app is the core. It provides the command palette,
  window tiling, OCR, project discovery, and the daemon (a WebSocket
  server on `ws://127.0.0.1:9399`). It works with or without tmux.
- The CLI handles tiling, OCR queries, and (when tmux is installed)
  session management via `tmux` shell commands.
- Agents and scripts connect to the daemon over WebSocket. They can
  do everything the app and CLI can do: discover projects, tile windows,
  switch layers, read on-screen text, and subscribe to real-time events.
- When tmux is installed, the app and CLI can also launch, sync, and
  manage persistent terminal sessions. All layers share the same session
  naming convention so they always agree on which session belongs to
  which project.

### Session naming

A session name is `<basename>-<hash>`, where:

- `basename` is the project directory name (non-alphanumeric chars replaced with `-`)
- `hash` is the first 6 hex chars of the SHA-256 of the full absolute path

This guarantees unique session names even if two projects share the
same directory name (e.g. `~/work/app` and `~/personal/app`).

Both the CLI (Node.js `crypto.createHash`) and the app (Swift
`CryptoKit.SHA256`) produce identical hashes.

### Window discovery via title tags

When lattices creates a tmux session, it sets the tmux option:

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

### Ensure/prefill restoration (requires tmux)

When you run `lattices` (no arguments) and a session already exists:

1. lattices checks the `ensure` / `prefill` flag in `.lattices.json`
2. For each pane, it queries `#{pane_current_command}` via tmux
3. If the pane is running a shell (bash, zsh, fish, sh, dash) — meaning
   the original command has exited — it either:
   - **ensure**: sends the command + Enter (auto-restart)
   - **prefill**: sends the command without Enter (manual restart)
4. Then it attaches to the session as normal

## Agent control

The daemon API gives agents the same control as a human using the
menu bar app. An agent can list projects and windows, launch sessions,
tile windows to screen positions, subscribe to real-time events
(`windows.changed`, `tmux.changed`, `layer.switched`), and sync
sessions back to their declared config.

A typical orchestrator sets up a multi-project workspace in a few
`daemonCall()` invocations. See the [Daemon API reference](/docs/api)
for the full method list and code examples.

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
