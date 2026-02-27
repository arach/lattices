# lattice

> Developer workspace launcher — Claude Code + dev server in tmux, with a native macOS menu bar app

## Critical Context

**IMPORTANT:** Read these rules before making any changes:

- lattice has TWO interfaces: a Node.js CLI (`bin/lattice.js`) and a native Swift menu bar app (`app/Sources/`)
- Session names are `<basename>-<sha256-6chars>` — both CLI and app must produce identical hashes
- The app finds terminal windows via a `[lattice:session-name]` tag embedded in the tmux window title
- Window navigation falls through CG → AX → AppleScript depending on macOS permissions
- Space switching uses private SkyLight framework APIs loaded via dlopen at runtime

## Project Structure

| Component | Path | Purpose |
|-----------|------|---------|
| Cli | `bin/lattice.js` | |
| App Helper | `bin/lattice-app.js` | |
| Menu Bar App | `app/Sources/` | |
| Website | `www/` | |
| Docs | `docs/` | |

## Quick Navigation

- Working with **cli**? → Check bin/lattice.js for CLI commands and session logic
- Working with **app**? → Check app/Sources/ for Swift menu bar app code
- Working with **config**? → Check docs/config.md for .lattice.json format and CLI reference
- Working with **tiling**? → Check app/Sources/WindowTiler.swift and bin/lattice.js tilePresets
- Working with **palette**? → Check app/Sources/PaletteCommand.swift for command palette actions
- Working with **terminal**? → Check app/Sources/Terminal.swift for supported terminals and launch logic

## Concepts

# Concepts

## What is lattice?

lattice is a developer workspace launcher. It creates pre-configured
terminal layouts for your projects using tmux, so you can go from
"I want to work on X" to a full development environment in one click.

It has two parts:

1. **CLI** (`lattice`) — creates and manages tmux sessions from the terminal
2. **Menu bar app** — a native macOS companion for launching, tiling,
   and navigating sessions with a command palette

## Glossary

### Session
A tmux session is a persistent workspace that lives in the background.
It survives terminal crashes, disconnects, and even closing your laptop.
Think of it as a virtual desktop for a single project.

### Pane
A pane is a single terminal view inside a session. A typical lattice
setup has two panes side by side — one running Claude Code and one
running your dev server. You can have up to four or more.

### Attach / Detach
Attaching connects your terminal window to an existing session.
Detaching disconnects your terminal but keeps the session alive.
Your dev server keeps running, Claude keeps thinking — nothing is lost.

### tmux
tmux (terminal multiplexer) is the engine behind lattice. It manages
sessions, panes, and layouts. lattice configures tmux for you so you
don't need to learn tmux commands — but knowing a few shortcuts helps.

### Multiplexer
A program that lets you run multiple terminal sessions inside a single
window and switch between them. tmux is the most popular one.

### Sync / Reconcile
Sync (`lattice sync`) brings a running session back in line with its
declared config. It recreates missing panes, re-applies the layout,
restores labels, and re-runs commands in idle panes. Useful when a pane
was accidentally killed but you don't want to restart the whole session.

### Ensure / Prefill
Two modes for restoring exited commands when you reattach to a session:

- **Ensure** — automatically re-runs the command (hands-free recovery)
- **Prefill** — types the command into the pane but waits for you to
  press Enter (manual confirmation)

Set via `"ensure": true` or `"prefill": true` in `.lattice.json`.

### Command Palette
The menu bar app's primary interface, opened with **Cmd+Shift+M**.
A searchable list of actions: launch/attach projects, tile windows,
sync sessions, restart panes, open settings.

### Window Tiling
Both the CLI (`lattice tile`) and the menu bar app can snap terminal
windows to preset screen positions (halves, quarters, maximize, center).
Tiling uses AppleScript bounds and respects the menu bar and dock.

## How it works

1. You create a `.lattice.json` file in your project root (or run `lattice init`)
2. lattice reads the config and creates a tmux session with your layout
3. Each pane gets its command (claude, dev server, tests, etc.)
4. The session persists in the background until you kill it
5. You can attach/detach from any terminal at any time
6. If `ensure` is enabled, exited commands auto-restart on reattach

## Architecture

### Three-layer stack

```
┌─────────────────────────────┐
│  Menu bar app (Swift/AppKit)│  ← GUI: command palette, tiling, project list
├─────────────────────────────┤
│  CLI (Node.js)              │  ← lattice, lattice sync, lattice restart ...
├─────────────────────────────┤
│  tmux                       │  ← session/pane lifecycle, layout, persistence
└─────────────────────────────┘
```

- The **CLI** talks to tmux directly via `tmux` shell commands.
- The **menu bar app** calls the CLI binary for session operations
  (launch, sync, restart) and uses tmux directly for status checks
  (has-session, list-panes).
- Both layers share the same session naming convention so they always
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

When lattice creates a session, it sets the tmux option:

```
set-titles-string "[lattice:<session-name>] #{pane_title}"
```

This embeds a `[lattice:name]` tag in the terminal window title. The
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

When you run `lattice` (no arguments) and a session already exists:

1. lattice checks the `ensure` / `prefill` flag in `.lattice.json`
2. For each pane, it queries `#{pane_current_command}` via tmux
3. If the pane is running a shell (bash, zsh, fish, sh, dash) — meaning
   the original command has exited — it either:
   - **ensure**: sends the command + Enter (auto-restart)
   - **prefill**: sends the command without Enter (manual restart)
4. Then it attaches to the session as normal

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

## Config

# Configuration

## .lattice.json

Place a `.lattice.json` file in your project root to define your
workspace layout. lattice reads this file when creating a session.

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

- **ensure** — when you reattach to an existing session, lattice checks
  each pane. If a pane's process has exited and the shell is idle, lattice
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
- `name` is used in the lattice app to show a summary of your layout,
  and as a target for `lattice restart <name>`.

## Layouts

lattice picks a layout based on how many panes you define:

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

If there's no `.lattice.json`, lattice still works. It will:

1. Create a 2-pane layout (60/40 split)
2. Run `claude` in the left pane
3. Auto-detect your dev command from package.json scripts:
   - Looks for: `dev`, `start`, `serve`, `watch` (in that order)
   - Detects package manager: pnpm > bun > yarn > npm

## Creating a config

Run `lattice init` in your project directory to generate a starter
`.lattice.json` based on your project. The generated config includes
`"ensure": true` by default.

## CLI commands

| Command                    | Description                                      |
|----------------------------|--------------------------------------------------|
| `lattice`                   | Create or attach to session for current project   |
| `lattice init`              | Generate .lattice.json config for this project     |
| `lattice ls`                | List active tmux sessions                         |
| `lattice kill [name]`       | Kill a session (defaults to current project)      |
| `lattice sync`              | Reconcile session to match declared config        |
| `lattice restart [pane]`    | Restart a pane's process (by name or index)       |
| `lattice tile <position>`   | Tile the frontmost window to a screen position    |
| `lattice app`               | Launch the menu bar companion app                 |
| `lattice app build`         | Rebuild the menu bar app from source              |
| `lattice app restart`       | Rebuild and relaunch the menu bar app             |
| `lattice app quit`          | Stop the menu bar app                             |
| `lattice help`              | Show help                                         |

Aliases: `ls`/`list`, `kill`/`rm`, `sync`/`reconcile`,
`restart`/`respawn`, `tile`/`t`.

## Recovery

### sync

```
lattice sync
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
lattice restart [target]
```

Kills the process in a specific pane and re-runs its declared command.
The target can be:

- A **pane name** (case-insensitive): `lattice restart server`
- A **0-based index**: `lattice restart 1`
- **Omitted** (defaults to pane 0): `lattice restart`

The restart sequence: send Ctrl-C, wait 0.5s, check if the process
stopped. If it's still running, escalate to SIGKILL on child
processes. Then send the declared command.

## Tile positions

The `lattice tile` command moves the frontmost window to a preset
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

## App

# Menu Bar App

The lattice menu bar app is a native macOS companion that lives in your
menu bar and gives you quick access to all your lattice sessions.

## Installation

```bash
lattice app          # Build (or download) and launch
lattice app build    # Rebuild from source
lattice app restart  # Quit, rebuild, relaunch
lattice app quit     # Stop the app
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

### App commands

| Command           | Description                              |
|-------------------|------------------------------------------|
| Settings          | Open preferences (terminal, scan root)   |
| Diagnostics       | View logs and debug info                 |
| Refresh Projects  | Re-scan for .lattice.json configs         |
| Quit Lattice       | Exit the menu bar app                    |

## Project discovery

The app scans a configurable root directory (up to 3 levels deep)
for `.lattice.json` files. It skips `.git/` and `node_modules/`.

Auto-detection for the scan root checks these paths in order:
`~/dev`, `~/Developer`, `~/projects`, `~/src`.

For each project found, the app reads:
- Pane names and commands from `.lattice.json`
- Dev command and package manager from `package.json`
- Running status by checking `tmux has-session`

## Session management

The app calls the lattice CLI for session operations:

- **Launch** — runs `lattice` in the project directory, which creates
  or reattaches to the session
- **Sync** — runs `lattice sync` to reconcile panes to the config
- **Restart** — runs `lattice restart <pane>` to kill and re-run a
  specific pane's process
- **Detach** — calls `tmux detach-client` directly
- **Kill** — calls `tmux kill-session` directly

## Window tiling

The app can tile terminal windows to preset screen positions via
the command palette. It finds windows by their `[lattice:session-name]`
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
| Scan Root  | Directory to scan for .lattice.json configs (type a path or click Browse) |

**Mode** controls how the app handles session interaction:

- **Learning** — shows tmux keybinding hints when you detach
  (helpful while getting used to tmux)
- **Auto** — detaches sessions automatically (fewer prompts)

### Shortcuts

Shows keyboard shortcut reference:

| Shortcut          | Action              |
|-------------------|----------------------|
| Cmd+Shift+M       | Open command palette |
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

## Diagnostics

The diagnostics panel shows a timestamped log of window navigation
attempts, including which path succeeded or failed. Useful for
debugging Screen Recording / Accessibility permission issues.

---
Generated by [Dewey](https://github.com/arach/dewey) | Last updated: 2026-02-21