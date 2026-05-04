---
title: Menu Bar App
description: Command palette, window tiling, and session management
order: 3
---

The lattices menu bar app sits in your menu bar and controls your
workspace from there.

## Installation

```bash
lattices app          # Build (or download) and launch
lattices app update   # Download the latest release and relaunch
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
| Update Lattices   | Download the latest release and relaunch |
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

The app calls the lattices CLI for session operations. Launch runs
`lattices start` in the project directory, Sync runs `lattices sync` to
reconcile panes, and Restart runs `lattices restart <pane>` to kill
and re-run a pane's process. Detach and Kill call `tmux detach-client`
and `tmux kill-session` directly.

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
| Left Third   | Left third                      |
| Center Third | Center third                    |
| Right Third  | Right third                     |
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
Settings > Privacy & Security for all three paths to work.

## Voice commands

> See [Voice Commands](/docs/voice) for the full guide.

Press **Hyper+3** to open the voice command window. Hold **Option** to
speak, release to stop. Lattices transcribes via Vox, matches to an
intent, and executes. Built-in commands: find, show, open, tile, kill, scan.

A Claude Haiku advisor runs in parallel, offering follow-up suggestions
in the AI corner. Configure the model and budget in Settings > AI.

## Settings

Open via the command palette or the gear icon in the main view.
The settings window has five tabs:

### General

| Setting    | Description                                          |
|------------|------------------------------------------------------|
| Terminal   | Which terminal to use (auto-detected from installed) |
| Mode       | `learning` or `auto` (see below)                     |
| Scan Root  | Directory to scan for .lattices.json configs (type a path or click Browse) |
| Updates    | Download the latest release and relaunch the app     |
| Keyboard Remaps | Optional Caps Lock layer that maps hold to Hyper and tap to Escape |

**Mode** controls how the app handles session interaction:

- **Learning** — shows tmux keybinding hints when you detach
  (helpful while getting used to tmux)
- **Auto** — detaches sessions automatically (fewer prompts)

### Keyboard Remaps

**Keyboard remaps** are enabled by default for the laptop-friendly rule:

- hold Caps Lock -> Hyper (`Control` + `Option` + `Shift` + `Command`)
- tap Caps Lock -> Escape

Rules live in `~/.lattices/keyboard-remaps.json`, and the Settings toggle
can turn the layer off. Keyboard remaps require Accessibility permission
because they use a local event tap.

### Companion

Shows the secure local bridge status, Mac bridge fingerprint, supported
capability grants, and paired iPad or iPhone devices. The paired-device
list shows each device fingerprint, last-seen time, and granted
capabilities. You can refresh the list, revoke an individual device, or
forget all trusted companions.

The local companion bridge and trackpad proxy are off by default for
privacy. Turn the bridge on in Settings > Companion, or open
`lattices://companion/enable` to enable the bridge and jump straight to
Companion settings. `lattices://companion/disable` turns it off again.

The trackpad proxy toggle lives here. Paired devices still need the
`input.trackpad` grant before they can send pointer events.

### AI

| Setting              | Default        | Description                              |
|----------------------|----------------|------------------------------------------|
| Claude CLI path      | Auto-detected  | Path to `claude` binary                  |
| Advisor model        | Haiku          | `haiku` (fast) or `sonnet` (smarter)     |
| Budget per session   | $0.50          | Max spend per Claude CLI invocation      |

Shows live session stats: context usage %, session cost, and learned
pattern count.

### Shortcuts

Shows keyboard shortcut reference:

| Shortcut          | Action              |
|-------------------|----------------------|
| Cmd+Shift+M       | Open command palette |
| Hyper+1            | Screen map           |
| Hyper+2            | Window bezel         |
| Hyper+3            | Voice commands       |
| Hyper+4            | Desktop inventory    |
| Hyper+5            | Omni search          |
| Hyper+6            | Cheat sheet          |
| Hyper+8            | Hide/show persistent overlay actors |
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

## Screen OCR

> See [Screen OCR](/docs/ocr) for full details on configuration, scanning,
> search, and agent usage.

The app reads text from visible windows using Apple's Vision framework
and stores results in a local SQLite database with FTS5 full-text search.
Agents can use this to "see" what's on screen.

### How it works

1. Every 60 seconds, the app captures the top visible windows as images
2. A SHA256 hash detects whether the window content has changed
3. Changed windows are processed through `VNRecognizeTextRequest` (fast mode)
4. Results are stored in `~/.lattices/ocr.db` with full-text indexing
5. Entries older than 3 days are automatically purged

### Desktop Inventory integration

The Desktop Inventory view (Hyper+4) uses OCR to make windows searchable
by their content — not just by title or app name. When you type a search
query, windows matching by OCR content show contextual snippets.

### API access

Agents can query OCR data through four API methods:

| Method         | Description                                    |
|----------------|------------------------------------------------|
| `ocr.snapshot` | Current OCR results for all visible windows    |
| `ocr.search`   | Full-text search across history (FTS5 syntax)  |
| `ocr.history`  | Timeline of OCR results for a specific window  |
| `ocr.scan`     | Trigger an immediate scan (bypasses timer)     |

```js
import { daemonCall } from '@lattices/cli'

// Find windows showing error messages
const errors = await daemonCall('ocr.search', { query: 'error OR failed' })

// Read what's currently on screen
const snapshot = await daemonCall('ocr.snapshot')
```

More in the [Agent API reference](/docs/api#ocrsnapshot).

### Requirements

- **Screen Recording** permission — required to capture window images
- Granted via System Settings > Privacy & Security > Screen Recording

## Agent API server

The menu bar app runs a WebSocket server on `ws://127.0.0.1:9399`.
It starts automatically when the app launches and stops when the app
quits.

### Checking status

```bash
lattices daemon status
```

Or programmatically:

```js
import { isDaemonRunning, daemonCall } from '@lattices/cli'

if (await isDaemonRunning()) {
  const status = await daemonCall('daemon.status')
  console.log(status) // { uptime, clientCount, version, windowCount, tmuxSessionCount }
}
```

### What it provides

- 35+ RPC methods for reading windows, sessions, projects, spaces, layers,
  processes, terminals, and OCR. Also launching/killing sessions, tiling
  windows, switching layers, and managing tab groups.
- 5 real-time events (`windows.changed`, `tmux.changed`, `processes.changed`,
  `layer.switched`, `ocr.scanComplete`) broadcast to all connected clients.
- Window tracking that monitors the desktop window list and correlates
  windows to lattices sessions via title tags.
- Space awareness, so it knows which macOS Space each window is on.

### Security

The server binds to localhost only (`127.0.0.1:9399`). Not accessible
from the network. No authentication, so any local process can connect.
This is intentional — it's for local automation, not remote access.

Full method list in the [Agent API reference](/docs/api).

## Diagnostics

The diagnostics panel shows a timestamped log of window navigation
attempts, including which path succeeded or failed. Useful for
debugging Screen Recording / Accessibility permission issues.
