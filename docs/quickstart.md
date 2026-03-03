---
title: Quickstart
description: Install lattices and launch your first workspace in 2 minutes
order: 0.5
---

Get from zero to a running workspace in five steps.

## 1. Install tmux

```bash
brew install tmux
```

Skip if you already have it (`tmux -V` to check).

## 2. Install lattices

```bash
npm install -g @arach/lattices
```

Or install from source:

```bash
git clone https://github.com/arach/lattices
cd lattices && npm link
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
