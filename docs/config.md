---
title: Configuration
description: CLI commands, .lattices.json format, and tile positions
order: 2
---

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
| `lattices ls`                | List active sessions (requires tmux)              |
| `lattices kill [name]`       | Kill a session (defaults to current project)      |
| `lattices sync`              | Reconcile session to match declared config        |
| `lattices restart [pane]`    | Restart a pane's process (by name or index)       |
| `lattices tile <position>`   | Tile the frontmost window to a screen position    |
| `lattices tile family [app] [region]` | Smart-grid the frontmost app family, or a named app |
| `lattices distribute [app] [region]` | Smart-grid visible windows or just one app      |
| `lattices group [id]`        | List tab groups or launch/attach a group          |
| `lattices groups`            | List all tab groups with status                   |
| `lattices tab <group> [tab]` | Switch tab within a group (by label or index)     |
| `lattices app`               | Launch the menu bar companion app                 |
| `lattices app update`        | Download the latest menu bar app and relaunch     |
| `lattices app build`         | Rebuild the menu bar app from source              |
| `lattices app restart`       | Rebuild and relaunch the menu bar app             |
| `lattices layer [name\|index]` | Switch to a workspace layer by name or index      |
| `lattices windows [--json]`  | List all visible windows                          |
| `lattices window assign <wid> <layer>` | Tag a window to a layer                |
| `lattices window map [--json]` | Show all window→layer assignments                |
| `lattices search <query>`      | Search windows by title, app, session, OCR       |
| `lattices search <q> --deep`   | Deep search: index + live terminal inspection    |
| `lattices search <q> --wid`    | Print matching window IDs only (pipeable)        |
| `lattices place <query> [pos]` | Deep search + focus + tile (default: bottom-right)|
| `lattices focus <session>`   | Focus a session's window and switch Spaces        |
| `lattices scan search <query>` | Search indexed screen text                       |
| `lattices diag [limit]`       | Show recent diagnostic entries                   |
| `lattices app`               | Launch the menu bar companion app                 |
| `lattices app update`        | Download the latest menu bar app and relaunch     |
| `lattices app build`         | Rebuild the menu bar app from source              |
| `lattices app restart`       | Rebuild and relaunch the menu bar app             |
| `lattices app quit`          | Stop the menu bar app                             |
| `lattices help`              | Show help                                         |

Aliases: `ls`/`list`, `kill`/`rm`, `sync`/`reconcile`,
`restart`/`respawn`, `tile`/`t`.

## Keyboard remaps

The menu bar app can create a lightweight keyboard layer from
`~/.lattices/keyboard-remaps.json`. The default config is:

```json
{
  "rules": [
    {
      "enabled": true,
      "from": "caps_lock",
      "id": "caps_lock_hyper_escape",
      "toIfAlone": "escape",
      "toIfHeld": "hyper"
    }
  ]
}
```

It is enabled by default and can be turned off from Settings -> General ->
Keyboard remaps. Hold Caps Lock to send Hyper (`Control` + `Option` +
`Shift` + `Command`), or tap Caps Lock alone to send Escape.

## Machine-readable output

### `--json` flag

The `lattices windows` command supports a `--json` flag for structured
output:

```bash
lattices windows --json
```

Returns a JSON array of window objects to stdout, useful for piping
into `jq` or consuming from scripts.

### Daemon responses

All agent API calls return JSON natively. If you need structured data
from lattices, the daemon is easier than parsing stdout. See the
[API reference](/docs/api).

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
| `left-third`   | Left third                  |
| `center-third` | Center third                |
| `right-third`  | Right third                 |
| `center`       | 70% width, 80% height, centered |

Aliases: `left-half`/`left`, `right-half`/`right`, `top-half`/`top`,
`bottom-half`/`bottom`, `max`/`maximize`.

Tiling respects the menu bar and dock. It uses the visible desktop
area, not the full screen.

### Smart app tiling

Use `lattices tile family` when you want lattices to arrange a whole
window family instead of just moving the frontmost window.

Examples:

```bash
lattices tile family
lattices tile family right
lattices tile family iTerm2
lattices tile family "Google Chrome" left
```

- With no app name, `family` means the **frontmost app**. If iTerm is
  frontmost, lattices grids your visible iTerm windows.
- If you pass a region (`left`, `right`, `top`, `bottom`, etc.), the
  smart grid is constrained to that part of the screen.
- `lattices distribute` uses the same smart grid engine, but defaults to
  **all visible windows** instead of the current app family.
