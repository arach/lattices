---
title: Overview
description: What lattices is and who it's for
order: 0
---

lattices is a workspace control plane for macOS. It manages persistent
terminal sessions, tiles and organizes your windows, and indexes the text
on your screen — all controllable from the CLI or a 30-method daemon API.

## The problem

I kept losing track of windows. Terminal here, dev server there, browser
somewhere on the second monitor, three other projects buried under it all.
Every morning I'd rebuild the same layout. Half my context-switching was
just hunting for the right window.

AI agents have it worse. They're stuck inside a single shell with no way
to see what's on screen, arrange windows, or jump between projects.

## The solution

lattices addresses both sides with three layers:

### Persistent terminal sessions

Declare your dev environment in a `.lattices.json`: which panes, which
commands, what layout. lattices builds it, runs it, and keeps it alive.
Close your laptop, reboot, come back a week later — your editor, dev
server, and test runner are exactly where you left them. No manual setup,
no remembering what was running.

### Window tiling and awareness

A native menu bar app tracks every window across all your monitors. Tile
with hotkeys, organize into switchable layers, snap to grids. It reads
your windows too — extracting text from UI elements every 60 seconds and
running Vision OCR on background windows every 2 hours. Everything is
searchable.

### A programmable desktop

The CLI and daemon API expose everything: query what's on screen, search
window text, tile layouts, manage sessions. Claude Code skills, MCP servers,
or your own scripts can drive your desktop the same way you do. Your
workspace becomes infrastructure you can observe and control programmatically.

## What's included

| Component | Description |
|-----------|-------------|
| **CLI** | The `lattices` command. Tile windows, manage sessions, scan screen text, control the workspace from your terminal |
| **Menu bar app** | Native macOS companion. Command palette, window tiling, project discovery, screen text indexing |
| **Daemon API** | WebSocket server on `ws://127.0.0.1:9399`. 30 methods, 5 real-time events |
| **Screen scanner** | Reads text from visible windows using Accessibility API (60s) and Apple Vision OCR (2h), indexes with FTS5 |
| **Node.js client** | Zero-dependency `daemonCall()` helper for scripting |

## Example

```bash
cd ~/my-project && lattices
```

Agents get the same control programmatically:

```js
import { daemonCall } from '@arach/lattices/daemon-client'
await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('window.tile', { session: 'frontend-a1b2c3', position: 'left' })
```

## Who it's for

- Developers who juggle multiple projects and want faster window management
- People building AI agents that need to observe and control the desktop
- Power users who work across multiple macOS Spaces
- Anyone who wants persistent, auto-configured terminal sessions

## Requirements

- macOS 13.0+
- Node.js 18+

### Dev dependencies

- Swift 5.9+ — only to build the menu bar app from source
- tmux — needed for persistent terminal sessions (`brew install tmux`)

## Next steps

- [Quickstart](/docs/quickstart): install and run your first session in 2 minutes
- [Configuration](/docs/config): `.lattices.json` format and CLI commands
- [Screen scanning](/docs/ocr): AX text extraction, Vision OCR, and full-text search
- [Concepts](/docs/concepts): architecture, glossary, and how it all works
- [Daemon API](/docs/api): RPC method reference for agents and scripts
