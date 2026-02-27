<picture>
  <img alt="lattice" src="www/public/og.png" />
</picture>

# lattice

Declarative tmux sessions for developers.

One command to create a named tmux session with your tools running. Auto-detects your stack, fully configurable with `.lattice.json`, and a native macOS menu bar app.

## Install

```sh
npm install -g lattice
```

## Quick start

```sh
cd my-project
lattice
```

That's it. lattice creates a tmux session named after your project with Claude Code on the left and your dev server on the right. It detects your package manager and dev command automatically.

## How it works

1. **Run `lattice`** in any project directory
2. A named tmux session is created with configured panes
3. Commands start running in each pane immediately
4. Detach with `Ctrl+b d`, reattach by running `lattice` again
5. Sessions persist in the background until you kill them

## Configuration

Drop a `.lattice.json` in your project root:

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

### Pane options

| Field  | Description                              |
|--------|------------------------------------------|
| `name` | Label for the pane (for your reference)  |
| `cmd`  | Command to run in the pane               |
| `size` | Width % for the first pane (default: 60) |

### Session options

| Field     | Description                                                                 |
|-----------|-----------------------------------------------------------------------------|
| `ensure`  | Auto-restart exited commands on reattach                                    |
| `prefill` | Type exited commands into panes on reattach without running (you hit Enter) |

### Layouts

```
2 panes — side-by-side          3+ panes — main-vertical

┌──────────┬─────────┐         ┌──────────┬─────────┐
│  claude   │ server  │         │  claude   │ server  │
│  (60%)   │ (40%)   │         │  (60%)   ├─────────┤
└──────────┴─────────┘         │          │ tests   │
                                └──────────┴─────────┘
```

## Auto-detection

Without a config file, lattice reads your `package.json` and picks the right command:

- Checks `scripts.dev`, `scripts.start`, `scripts.serve`, `scripts.watch`
- Detects package manager from lock files (pnpm, bun, yarn, npm)
- Falls back to a shell if no dev command is found

## Menu bar app

A macOS companion app for managing sessions without touching the terminal.

```sh
lattice app          # Launch (builds from source or downloads binary)
lattice app build    # Force rebuild from source
lattice app quit     # Stop the menu bar app
```

Features:
- See all projects and their session status at a glance
- Launch, attach, or detach sessions with a click
- **Command palette** (`Cmd+Shift+M`): Raycast-style launcher for all actions — fuzzy search, keyboard navigation, instant access to projects, window tiling, and settings
- Auto-scans your project directories
- Built with SwiftUI, runs natively on macOS

The app tries to compile from source first (requires Xcode CLI tools), falling back to a pre-built arm64 binary from GitHub releases.

## Tab groups

Bundle related projects as tabs within a single terminal window.
Configure in `~/.lattice/workspace.json`:

```json
{
  "name": "my-setup",
  "groups": [
    {
      "id": "talkie",
      "label": "Talkie",
      "tabs": [
        { "path": "/Users/you/dev/talkie-ios", "label": "iOS" },
        { "path": "/Users/you/dev/talkie-web", "label": "Website" },
        { "path": "/Users/you/dev/talkie-api", "label": "API" }
      ]
    }
  ]
}
```

Each tab gets its own tmux window with pane layout from its `.lattice.json`.

```sh
lattice groups            # List groups with status
lattice group talkie      # Launch or attach
lattice tab talkie iOS    # Switch to a tab
```

Groups can also be referenced in [workspace layers](https://lattice.dev/docs/layers) to tile a whole group into a screen position.

## CLI reference

```
lattice                    Create or reattach to a session for the current project
lattice init               Generate a .lattice.json config
lattice ls                 List active tmux sessions
lattice kill [name]        Kill a session (defaults to current project)
lattice group [id]         List tab groups or launch/attach a group
lattice groups             List all tab groups with status
lattice tab <group> [tab]  Switch tab within a group (by label or index)
lattice app                Launch the menu bar companion app
lattice help               Show help
```

## Requirements

- **tmux** — `brew install tmux`
- **Node.js** 18+
- **macOS** (the CLI is macOS-only, the menu bar app requires arm64)

## License

MIT
