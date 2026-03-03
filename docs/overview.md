---
title: Overview
description: What lattices is and who it's for
order: 0
---

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
