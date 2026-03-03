# lattices

> macOS developer workspace manager — tmux sessions with a native menu bar app for tiling, navigation, and project management

## Critical Context

**IMPORTANT:** Read these rules before making any changes:

- lattices has TWO interfaces: a Node.js CLI (`bin/lattices.js`) and a native Swift menu bar app (`app/Sources/`)
- Session names are `<basename>-<sha256-6chars>` — both CLI and app must produce identical hashes
- The app finds terminal windows via a `[lattices:session-name]` tag embedded in the tmux window title
- Window navigation falls through CG → AX → AppleScript depending on macOS permissions
- Space switching uses private SkyLight framework APIs loaded via dlopen at runtime
- The daemon runs on ws://127.0.0.1:9399 with 20 RPC methods and 3 real-time events

## Project Structure

| Component | Path | Purpose |
|-----------|------|---------|
| Cli | `bin/lattices.js` | |
| App Helper | `bin/lattices-app.js` | |
| Menu Bar App | `app/Sources/` | |
| Docs | `docs/` | |
| Docs Site | `docs-site/` | |
| Marketing Site | `site/` | |

## Quick Navigation

- Working with **cli**? → Check bin/lattices.js for CLI commands and session logic
- Working with **app**? → Check app/Sources/ for Swift menu bar app code
- Working with **config**? → Check docs/config.md for .lattices.json format and CLI reference
- Working with **tiling**? → Check app/Sources/WindowTiler.swift and bin/lattices.js tilePresets
- Working with **palette**? → Check app/Sources/PaletteCommand.swift for command palette actions
- Working with **terminal**? → Check app/Sources/Terminal.swift for supported terminals and launch logic
- Working with **daemon**? → Check app/Sources/DaemonServer.swift and app/Sources/LatticesApi.swift for WebSocket API
- Working with **api**? → Check docs/api.md for the full 20-method RPC reference

## Quickstart

> Install lattices and launch your first workspace in 2 minutes

# Quickstart

Get from zero to a running workspace in five steps.

## 1. Install tmux

```bash
brew install tmux
```

Skip if you already have it (`tmux -V` to check).

## 2. Install lattices

```bash
# Clone and link
git clone https://github.com/arach/lattices
cd lattices
bun link
```

Verify: `lattices help` should print usage info.

## 3. Launch a workspace

```bash
cd ~/your-project
lattices
```

This creates a tmux session with two panes side by side:
- Left pane (60%): `claude` (AI coding agent)
- Right pane (40%): your dev command (auto-detected from `package.json`)

No config file needed — lattices auto-detects your package manager
and dev script.

## 4. Customize with .lattices.json

For more control, add a config to your project:

```bash
lattices init
```

This generates a `.lattices.json` like:

```json
{
  "ensure": true,
  "panes": [
    { "name": "claude", "cmd": "claude", "size": 60 },
    { "name": "server", "cmd": "bun dev" }
  ]
}
```

Edit it to match your workflow, then run `lattices` again to apply.

## 5. Launch the menu bar app

```bash
lattices app
```

This builds (or downloads) and launches the native macOS companion.
Open the command palette with **Cmd+Shift+M** to search and launch
any project, tile windows, or switch workspace layers.

## What's next

- [Concepts](/docs/concepts) — understand sessions, panes, and the architecture
- [Configuration](/docs/config) — full `.lattices.json` reference and CLI commands
- [Menu Bar App](/docs/app) — command palette, tiling, and settings
- [Daemon API](/docs/api) — programmatic control for agents and scripts
- [Layers & Groups](/docs/layers) — organize projects into switchable contexts

## Concepts

> Core ideas, glossary, and architecture of lattices

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

## Configuration

> CLI commands, .lattices.json format, and tile positions

# Configuration

## .lattices.json

Place a `.lattices.json` file in your project root to define your
workspace layout. lattices reads this file when creating a session.

### Minimal example

```json
{
  "panes": [
    { "name": "claude", "cmd": "claude" },
    { "name": "server", "cmd": "pnpm dev" }
  ]
}
```

### Full example

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

## Config fields

| Field    | Type    | Required | Description                                          |
|----------|---------|----------|------------------------------------------------------|
| panes    | array   | no       | List of pane definitions (see below)                 |
| ensure   | boolean | no       | Auto-restart exited commands on reattach              |
| prefill  | boolean | no       | Type exited commands into idle panes on reattach (you hit Enter) |

`ensure` and `prefill` are mutually exclusive. If both are set,
`ensure` takes priority.

- **ensure** — when you reattach to an existing session, lattices checks
  each pane. If a pane's process has exited and the shell is idle, lattices
  automatically re-runs its declared command.
- **prefill** — same check, but the command is typed into the pane
  without pressing Enter. You review and hit Enter yourself.

## Pane fields

| Field  | Type   | Required | Description                         |
|--------|--------|----------|-------------------------------------|
| name   | string | no       | Label for the pane (shown in app)   |
| cmd    | string | no       | Command to run when pane opens      |
| size   | number | no       | Width % for the first pane (1-99)   |

- `size` only applies to the **first pane**. It sets the width of the
  main pane as a percentage. Default is 60.
- `cmd` can be any shell command. If omitted, the pane opens a shell.
- `name` is used in the lattices app to show a summary of your layout,
  and as a target for `lattices restart <name>`.

## Layouts

lattices picks a layout based on how many panes you define:

### 2 panes — side by side

```
┌──────────┬─────────┐
│  claude  │ server  │
│  (60%)   │ (40%)   │
└──────────┴─────────┘
```

Horizontal split. First pane on the left, second on the right.

### 3+ panes — main-vertical

```
┌──────────┬─────────┐
│  claude  │ server  │
│  (60%)   ├─────────┤
│          │ tests   │
└──────────┴─────────┘
```

First pane takes the left side. Remaining panes stack vertically
on the right.

### 4 panes

```
┌──────────┬─────────┐
│  claude  │ server  │
│  (60%)   ├─────────┤
│          │ tests   │
│          ├─────────┤
│          │ logs    │
└──────────┴─────────┘
```

## Auto-detection (no config)

If there's no `.lattices.json`, lattices still works. It will:

1. Create a 2-pane layout (60/40 split)
2. Run `claude` in the left pane
3. Auto-detect your dev command from package.json scripts:
   - Looks for: `dev`, `start`, `serve`, `watch` (in that order)
   - Detects package manager: pnpm > bun > yarn > npm

## Creating a config

Run `lattices init` in your project directory to generate a starter
`.lattices.json` based on your project. The generated config includes
`"ensure": true` by default.

## CLI commands

| Command                    | Description                                      |
|----------------------------|--------------------------------------------------|
| `lattices`                   | Create or attach to session for current project   |
| `lattices init`              | Generate .lattices.json config for this project     |
| `lattices ls`                | List active tmux sessions                         |
| `lattices kill [name]`       | Kill a session (defaults to current project)      |
| `lattices sync`              | Reconcile session to match declared config        |
| `lattices restart [pane]`    | Restart a pane's process (by name or index)       |
| `lattices tile <position>`   | Tile the frontmost window to a screen position    |
| `lattices group [id]`        | List tab groups or launch/attach a group          |
| `lattices groups`            | List all tab groups with status                   |
| `lattices tab <group> [tab]` | Switch tab within a group (by label or index)     |
| `lattices app`               | Launch the menu bar companion app                 |
| `lattices app build`         | Rebuild the menu bar app from source              |
| `lattices app restart`       | Rebuild and relaunch the menu bar app             |
| `lattices app quit`          | Stop the menu bar app                             |
| `lattices help`              | Show help                                         |

Aliases: `ls`/`list`, `kill`/`rm`, `sync`/`reconcile`,
`restart`/`respawn`, `tile`/`t`.

## Machine-readable output

### `--json` flag

The `lattices windows` command supports a `--json` flag for structured
output:

```bash
lattices windows --json
```

Returns a JSON array of window objects to stdout — useful for piping
into `jq` or consuming from scripts.

### Daemon responses

All daemon API calls return JSON natively. If you need structured data
from lattices, the daemon is the best path — no flags needed, no stdout
parsing. See the [API reference](/docs/api).

### Exit codes

| Code | Meaning                                     |
|------|---------------------------------------------|
| `0`  | Success                                     |
| `1`  | General error (missing args, bad config)    |
| `2`  | Session not found                           |

## Recovery

### sync

```
lattices sync
```

Reconciles a running session to match the declared config:

1. Counts actual panes vs declared panes
2. Recreates any missing panes
3. Re-applies the layout (main-vertical with correct width)
4. Restores pane labels
5. Re-runs declared commands in any idle panes

Use when a pane was killed and you want to get back to the declared
state without killing the whole session.

### restart

```
lattices restart [target]
```

Kills the process in a specific pane and re-runs its declared command.
The target can be:

- A **pane name** (case-insensitive): `lattices restart server`
- A **0-based index**: `lattices restart 1`
- **Omitted** (defaults to pane 0): `lattices restart`

The restart sequence: send Ctrl-C, wait 0.5s, check if the process
stopped. If it's still running, escalate to SIGKILL on child
processes. Then send the declared command.

## Tile positions

The `lattices tile` command moves the frontmost window to a preset
screen position. Available positions:

| Position       | Area                        |
|----------------|-----------------------------|
| `left`         | Left half                   |
| `right`        | Right half                  |
| `top`          | Top half                    |
| `bottom`       | Bottom half                 |
| `top-left`     | Top-left quarter            |
| `top-right`    | Top-right quarter           |
| `bottom-left`  | Bottom-left quarter         |
| `bottom-right` | Bottom-right quarter        |
| `maximize`     | Full screen (visible area)  |
| `center`       | 70% width, 80% height, centered |

Aliases: `left-half`/`left`, `right-half`/`right`, `top-half`/`top`,
`bottom-half`/`bottom`, `max`/`maximize`.

Tiling respects the menu bar and dock — it uses the visible desktop
area, not the full screen.

## Menu Bar App

> Command palette, window tiling, and session management

# Menu Bar App

The lattices menu bar app is a native macOS companion that lives in your
menu bar and gives you quick access to all your lattices sessions.

## Installation

```bash
lattices app          # Build (or download) and launch
lattices app build    # Rebuild from source
lattices app restart  # Quit, rebuild, relaunch
lattices app quit     # Stop the app
```

The first run builds from source if Swift is available, otherwise
downloads a pre-built binary from GitHub releases.

## Command palette

Press **Cmd+Shift+M** from anywhere to open the command palette.
It's a searchable list of every action the app can perform, with
fuzzy matching on titles and subtitles.

### Project commands

| Command                       | Description                              |
|-------------------------------|------------------------------------------|
| Launch *project*              | Create a new session and open terminal   |
| Attach *project*              | Focus or open the running session        |
| Sync *project*                | Reconcile session to declared config     |
| Restart *pane* in *project*   | Kill and re-run a specific pane's command |

### Window commands

Available for running sessions:

| Command                       | Description                              |
|-------------------------------|------------------------------------------|
| Go to *project*               | Focus the terminal window (switches Spaces if needed) |
| Tile *project* Left           | Snap window to left half                 |
| Tile *project* Right          | Snap window to right half                |
| Maximize *project*            | Expand window to fill screen             |
| Detach *project*              | Disconnect clients, keep session alive   |
| Kill *project*                | Terminate the tmux session               |

### Tab group commands

Available when `groups` are configured in `~/.lattices/workspace.json`
(see [Tab Groups](/docs/layers#tab-groups)):

| Command                     | Description                              |
|-----------------------------|------------------------------------------|
| Launch *group*              | Start the group session (all tabs)       |
| Attach *group*              | Focus the running group session          |
| *Group*: *Tab*              | Switch to a specific tab within a group  |
| Kill *group* Group          | Terminate the group session              |

### Layer commands

Available when `layers` are configured in `~/.lattices/workspace.json`
(see [Layers](/docs/layers#layers)):

| Command                     | Description                              |
|-----------------------------|------------------------------------------|
| Switch to Layer: *label*    | Focus and tile the layer's project windows |

### App commands

| Command           | Description                              |
|-------------------|------------------------------------------|
| Settings          | Open preferences (terminal, scan root)   |
| Diagnostics       | View logs and debug info                 |
| Refresh Projects  | Re-scan for .lattices.json configs        |
| Quit Lattices      | Exit the menu bar app                    |

## Project discovery

The app scans a configurable root directory (up to 3 levels deep)
for `.lattices.json` files. It skips `.git/` and `node_modules/`.

Auto-detection for the scan root checks these paths in order:
`~/dev`, `~/Developer`, `~/projects`, `~/src`.

For each project found, the app reads:
- Pane names and commands from `.lattices.json`
- Dev command and package manager from `package.json`
- Running status by checking `tmux has-session`

## Session management

The app calls the lattices CLI for session operations:

- **Launch** — runs `lattices` in the project directory, which creates
  or reattaches to the session
- **Sync** — runs `lattices sync` to reconcile panes to the config
- **Restart** — runs `lattices restart <pane>` to kill and re-run a
  specific pane's process
- **Detach** — calls `tmux detach-client` directly
- **Kill** — calls `tmux kill-session` directly

## Window tiling

The app can tile terminal windows to preset screen positions via
the command palette. It finds windows by their `[lattices:session-name]`
title tag.

For Terminal.app and iTerm2, tiling uses AppleScript to set window
bounds by matching the title tag. For other terminals, it tiles the
frontmost window.

### Tile positions (app)

| Position     | Area                            |
|--------------|---------------------------------|
| Left         | Left half                       |
| Right        | Right half                      |
| Top Left     | Top-left quarter                |
| Top Right    | Top-right quarter               |
| Bottom Left  | Bottom-left quarter             |
| Bottom Right | Bottom-right quarter            |
| Maximize     | Full visible screen             |
| Center       | 70% width, 80% height, centered |

## Space navigation

"Go to" commands can switch macOS Spaces to reach a window on a
different desktop. The app uses a three-path fallback:

1. **CGWindowList** (needs Screen Recording) — looks up the window
   by title tag, finds its Space via SkyLight, switches to it, then
   raises the window
2. **Accessibility API** (needs Accessibility) — finds the window
   via AXUIElement, raises it, and activates the app
3. **AppleScript** — iterates windows by name for Terminal/iTerm2,
   or bare-activates for other terminals

When a window is found and focused, the app flashes a green border
highlight around it for ~1 second so you can spot it immediately.

Grant Screen Recording and Accessibility permissions in System
Settings > Privacy & Security for the best experience.

## Settings

Open via the command palette or the gear icon in the main view.
The settings window has three tabs:

### General

| Setting    | Description                                          |
|------------|------------------------------------------------------|
| Terminal   | Which terminal to use (auto-detected from installed) |
| Mode       | `learning` or `auto` (see below)                     |
| Scan Root  | Directory to scan for .lattices.json configs (type a path or click Browse) |

**Mode** controls how the app handles session interaction:

- **Learning** — shows tmux keybinding hints when you detach
  (helpful while getting used to tmux)
- **Auto** — detaches sessions automatically (fewer prompts)

### Shortcuts

Shows keyboard shortcut reference:

| Shortcut          | Action              |
|-------------------|----------------------|
| Cmd+Shift+M       | Open command palette |
| Cmd+Option+1/2/3  | Switch workspace layer |
| Ctrl+B  D         | Detach from session  |
| Ctrl+B  X         | Kill current pane    |
| Ctrl+B  Left/Right| Move between panes   |
| Ctrl+B  Z         | Zoom pane (toggle)   |
| Ctrl+B  [         | Scroll mode          |

### Docs

Embedded quick reference with glossary, "how it works" steps, and
links to open the full `config.md` and `concepts.md` docs.

## Supported terminals

| Terminal     | Launch | Focus/Attach | Tile by tag |
|--------------|--------|--------------|-------------|
| Terminal.app | yes    | yes          | yes         |
| iTerm2       | yes    | yes          | yes         |
| Warp         | yes    | activate     | frontmost   |
| Ghostty      | yes    | activate     | frontmost   |
| Kitty        | yes    | activate     | frontmost   |
| Alacritty    | yes    | activate     | frontmost   |

"yes" means full AppleScript-based window matching by title tag.
"activate" means the app is brought to front but a specific window
can't be targeted. "frontmost" means tiling applies to whatever
window is in front.

## Daemon

The menu bar app runs a WebSocket daemon on `ws://127.0.0.1:9399`.
It starts automatically when the app launches and stops when the app
quits.

### Checking status

```bash
lattices daemon status
```

Or programmatically:

```js
import { isDaemonRunning, daemonCall } from 'lattices/daemon-client'

if (await isDaemonRunning()) {
  const status = await daemonCall('daemon.status')
  console.log(status) // { uptime, clientCount, version, windowCount, tmuxSessionCount }
}
```

### What it provides

- **20 RPC methods** — read windows, sessions, projects, spaces, layers;
  launch/kill/sync sessions; tile/focus/move windows; switch layers;
  manage tab groups
- **3 real-time events** — `windows.changed`, `tmux.changed`,
  `layer.switched` — broadcast to all connected clients
- **Window tracking** — the daemon monitors the desktop window list
  and correlates windows to lattices sessions via title tags
- **Space awareness** — knows which macOS Space each window is on

### Security

The daemon binds to **localhost only** (`127.0.0.1:9399`). It is not
accessible from the network. There is no authentication — any process
on the same machine can connect. This is intentional: the daemon is
designed for local automation, not remote access.

See the [Daemon API reference](/docs/api) for the full method list.

## Diagnostics

The diagnostics panel shows a timestamped log of window navigation
attempts, including which path succeeded or failed. Useful for
debugging Screen Recording / Accessibility permission issues.

## Workspace Layers & Tab Groups

> Group projects into switchable layers and tabbed groups

# Workspace Layers & Tab Groups

Two ways to organize related projects in `~/.lattices/workspace.json`:

- **Layers** — switchable contexts that focus and tile windows
- **Tab groups** — related projects as tabs within a single terminal window

Both features are configured in the same workspace config and
work together.

## Tab Groups

Tab groups let you bundle related projects as tabs (tmux windows)
within a single tmux session. This is useful when you have a family
of projects — like an iOS app, macOS app, website, and API — that
you think of as one logical unit.

### Configuration

Add `groups` to `~/.lattices/workspace.json`:

```json
{
  "name": "my-setup",
  "groups": [
    {
      "id": "talkie",
      "label": "Talkie",
      "tabs": [
        { "path": "/Users/you/dev/talkie-ios", "label": "iOS" },
        { "path": "/Users/you/dev/talkie-macos", "label": "macOS" },
        { "path": "/Users/you/dev/talkie-web", "label": "Website" },
        { "path": "/Users/you/dev/talkie-api", "label": "API" }
      ]
    }
  ]
}
```

Each tab's pane layout comes from its own `.lattices.json` — no changes
to per-project configs.

### How it works

- **Session naming**: `lattices-group-<id>` (e.g. `lattices-group-talkie`)
- **tmux mapping**: 1 group = 1 tmux session, each tab = 1 tmux window,
  each window has its own panes from that project's `.lattices.json`
- **Independent launch still works**: `cd talkie-ios && lattices` creates
  its own standalone session as before

### Tab group fields

| Field          | Type     | Description                          |
|----------------|----------|--------------------------------------|
| `id`           | string   | Unique identifier for the group      |
| `label`        | string   | Display name shown in the UI         |
| `tabs`         | array    | List of tab definitions              |
| `tabs[].path`  | string   | Absolute path to project directory   |
| `tabs[].label` | string?  | Tab name (defaults to directory name) |

### CLI commands

```bash
lattices groups             # List all groups with status
lattices group <id>         # Launch or attach to a group
lattices tab <group> [tab]  # Switch tab by label or index
```

Examples:

```bash
lattices group talkie       # Launch all Talkie tabs
lattices tab talkie iOS     # Switch to the iOS tab
lattices tab talkie 0       # Switch to first tab (by index)
```

### Menu bar app

Tab groups appear above the project list in the menu bar panel.
Each group row shows:

- Status indicator (running/stopped)
- Tab count badge
- Expand/collapse to see individual tabs
- Launch/Attach and Kill buttons
- Per-tab "Go" buttons to switch and focus a specific tab

The command palette also includes group commands:

| Command                    | Description                            |
|----------------------------|----------------------------------------|
| Launch *group*             | Start the group session                |
| Attach *group*             | Focus the running group session        |
| *Group*: *Tab*             | Switch to a specific tab in a group    |
| Kill *group* Group         | Terminate the group session            |

## Layers

Layers let you group projects into switchable contexts. Instead of
juggling six terminal windows at once, define two or three layers and
switch between them instantly — the target layer's windows come to the
front and tile into position, while the previous layer's windows fall
behind.

All tmux sessions stay alive across switches. Nothing is detached or
killed — layers only control which windows are focused.

### Configuration

Add `layers` to `~/.lattices/workspace.json`:

```json
{
  "name": "my-setup",
  "layers": [
    {
      "id": "web",
      "label": "Web",
      "projects": [
        { "path": "/Users/you/dev/frontend", "tile": "left" },
        { "path": "/Users/you/dev/api", "tile": "right" }
      ]
    },
    {
      "id": "mobile",
      "label": "Mobile",
      "projects": [
        { "path": "/Users/you/dev/ios-app", "tile": "left" },
        { "path": "/Users/you/dev/backend", "tile": "right" }
      ]
    }
  ]
}
```

### Using groups in layers

Layer projects can reference a tab group instead of a single path.
This lets you tile a whole group into a screen position:

```json
{
  "name": "my-setup",
  "groups": [
    {
      "id": "talkie",
      "label": "Talkie",
      "tabs": [
        { "path": "/Users/you/dev/talkie-ios", "label": "iOS" },
        { "path": "/Users/you/dev/talkie-web", "label": "Website" }
      ]
    }
  ],
  "layers": [
    {
      "id": "main",
      "label": "Main",
      "projects": [
        { "group": "talkie", "tile": "top-left" },
        { "path": "/Users/you/dev/design-system", "tile": "right" }
      ]
    }
  ]
}
```

When switching to this layer, lattices launches (or focuses) the
"talkie" group session and tiles it to the top-left quarter, alongside
the design-system project on the right.

### Layer fields

| Field             | Type     | Description                              |
|-------------------|----------|------------------------------------------|
| `name`            | string   | Workspace name (for your reference)      |
| `layers`          | array    | List of layer definitions                |
| `layers[].id`     | string   | Unique identifier (e.g. `"web"`)         |
| `layers[].label`  | string   | Display name shown in the UI             |
| `layers[].projects` | array  | Projects in this layer                   |
| `projects[].path` | string?  | Absolute path to project directory       |
| `projects[].group`| string?  | Group ID (alternative to `path`)         |
| `projects[].tile` | string?  | Tile position (optional, see below)      |

Each project entry must have either `path` or `group`, not both.

### Tile values

Any tile position from the [config reference](/docs/config#tile-positions)
works: `left`, `right`, `top-left`, `top-right`, `bottom-left`,
`bottom-right`, `maximize`, `center`.

### Switching layers

Three ways to switch:

| Method               | How                                      |
|----------------------|------------------------------------------|
| **Hotkey**           | Cmd+Option+1, Cmd+Option+2, Cmd+Option+3... |
| **Layer bar**        | Click a layer pill in the menu bar panel |
| **Command palette**  | Search "Switch to Layer" in Cmd+Shift+M  |

When you switch to a layer:

1. Each project's terminal window is **raised and focused**
2. If a project isn't running yet, it gets **launched** automatically
3. Windows with a `tile` value are **tiled** to that position
4. The previous layer's windows stay open behind the new ones

The app remembers which layer was last active across restarts.

### Programmatic switching

Agents and scripts can switch layers via the daemon API:

```js
import { daemonCall } from 'lattices/daemon-client'

// List available layers
const { layers, active } = await daemonCall('layers.list')
console.log(`Active: ${layers[active].label}`)

// Switch to a layer by index
await daemonCall('layer.switch', { index: 0 })
```

The `layer.switch` call focuses and tiles all windows in the target
layer, just like the hotkey or command palette. A `layer.switched`
event is broadcast to all connected clients.

See the [Daemon API reference](/docs/api) for more methods.

### Layer bar

When a workspace config is loaded, a layer bar appears between the
header and search field in the menu bar panel:

```
 lattices  2 sessions              [↔] [⟳]
┌────────────────────────────────────────┐
│  ● Web          ○ Mobile               │
│  ⌥1             ⌥2                     │
└────────────────────────────────────────┘
 Search projects...
```

- Active layer: filled green dot
- Inactive layers: dim outline dot
- Hotkey hints shown below each label

## Layout examples

### Single project

```json
{
  "projects": [
    { "path": "/Users/you/dev/talkie" }
  ]
}
```

No `tile` — just focuses the window wherever it is.

### Two-project split

```json
{
  "projects": [
    { "path": "/Users/you/dev/app", "tile": "left" },
    { "path": "/Users/you/dev/api", "tile": "right" }
  ]
}
```

### Group + project

```json
{
  "projects": [
    { "group": "talkie", "tile": "left" },
    { "path": "/Users/you/dev/api", "tile": "right" }
  ]
}
```

### Four quadrants

```json
{
  "projects": [
    { "path": "/Users/you/dev/frontend", "tile": "top-left" },
    { "path": "/Users/you/dev/backend", "tile": "top-right" },
    { "path": "/Users/you/dev/mobile", "tile": "bottom-left" },
    { "path": "/Users/you/dev/infra", "tile": "bottom-right" }
  ]
}
```

## Tips

- Projects don't need a `.lattices.json` config to be in a layer — any
  directory path works. If the project has a config, lattices uses it; if
  not, it opens a plain terminal in that directory.
- You can have up to 9 layers (Cmd+Option+1 through Cmd+Option+9).
- Edit `workspace.json` by hand — the app re-reads it on launch. Use
  the Refresh Projects button or restart the app to pick up changes.
- The `tile` field is optional. Omit it if you just want the window
  focused without repositioning.
- Tab groups and standalone projects can coexist in the same workspace.
  Use groups for related project families, standalone paths for
  individual projects.

## Daemon API

> WebSocket API reference for programmatic control of lattices

# Daemon API

The lattices menu bar app runs a WebSocket daemon on `ws://127.0.0.1:9399`.
It exposes 20 RPC methods and 3 real-time events — everything the app
can do, agents and scripts can do too.

## Who this is for

- **AI coding agents** that need to discover projects, launch sessions,
  tile windows, and switch contexts without human interaction
- **Scripts and automation** — CI, dotfile bootstraps, workspace setup
- **Custom tools** — build your own launcher, dashboard, or orchestrator

> New to lattices? Start with the [Overview](/docs/overview) and
> [Quickstart](/docs/quickstart). For the `.lattices.json` config format
> and CLI commands, see [Configuration](/docs/config). For architecture
> details, see [Concepts](/docs/concepts).

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
import { daemonCall } from 'lattices/daemon-client'

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

## Node.js client

lattices ships a zero-dependency WebSocket client that works with
Node.js 18+. It handles connection, framing, and request/response
matching internally.

### `daemonCall(method, params?, timeoutMs?)`

Send an RPC call and await the response.

```js
import { daemonCall } from 'lattices/daemon-client'

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
import { isDaemonRunning } from 'lattices/daemon-client'

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
`bottom-left`, `bottom-right`, `maximize`, `center`

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

### `projects.scan`

Trigger a re-scan of the project directory. Useful after cloning a new
repo or adding a `.lattices.json` config.

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
import { daemonCall } from 'lattices/daemon-client'
\```
```

### Multi-agent orchestration

An orchestrator agent can set up the full workspace for sub-agents:

```js
import { daemonCall } from 'lattices/daemon-client'

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
    const latticesWindows = msg.data.windows.filter(w => w.latticesSession)
    console.log('Lattices windows:', latticesWindows.length)
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
import { isDaemonRunning, daemonCall } from 'lattices/daemon-client'

if (!(await isDaemonRunning())) {
  console.error('lattices daemon is not running — start it with: lattices app')
  process.exit(1)
}

const status = await daemonCall('daemon.status')
console.log(`Daemon up for ${Math.round(status.uptime)}s, tracking ${status.windowCount} windows`)
```

## Overview

> What lattices is and who it's for

# Overview

lattices is a macOS developer workspace manager. It pairs tmux sessions
with a native menu bar app to give you — and your AI coding agents —
full control over terminal layouts, window tiling, and project navigation.

## The problem

Modern development means juggling multiple terminal windows: a coding
agent in one, a dev server in another, tests in a third. Setting this up
every morning is tedious. AI agents can't do it at all — they're trapped
inside a single shell with no way to manage windows or switch contexts.

## The solution

lattices solves both sides:

- **For you** — run `lattices` in any project to get a pre-configured
  tmux session. Use the menu bar app to launch, tile, and navigate
  sessions with a command palette.
- **For agents** — the daemon API exposes 20 RPC methods over WebSocket.
  Agents can discover projects, launch sessions, tile windows, and
  switch workspace layers programmatically.

## What's included

| Component | Description |
|-----------|-------------|
| **CLI** (`lattices`) | Create, manage, and tile tmux sessions from the terminal |
| **Menu bar app** | Native macOS companion with command palette, tiling, and project discovery |
| **Daemon API** | WebSocket server on `ws://127.0.0.1:9399` — 20 methods, 3 real-time events |
| **Node.js client** | Zero-dependency `daemonCall()` helper for scripting |

## Quick taste

```bash
# Launch a workspace (auto-detects your project)
cd ~/my-project && lattices

# Or give agents programmatic control
```

```js
import { daemonCall } from 'lattices/daemon-client'

await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('window.tile', { session: 'frontend-a1b2c3', position: 'left' })
```

## Who it's for

- **Developers** who use tmux and want faster project switching
- **AI agent builders** who need their agents to control the workspace
- **Power users** who manage multiple projects across macOS Spaces

## Requirements

- macOS 13.0+
- tmux (`brew install tmux`)
- Node.js 18+
- Swift 5.9+ (only needed to build the menu bar app from source)

## Next steps

- [Quickstart](/docs/quickstart) — install and run your first session in 2 minutes
- [Concepts](/docs/concepts) — architecture, glossary, and how it all works
- [Configuration](/docs/config) — `.lattices.json` format and CLI commands
- [Daemon API](/docs/api) — full RPC method reference for agents and scripts

---
Generated by [Dewey](https://github.com/arach/dewey) | Last updated: 2026-03-03