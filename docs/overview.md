---
title: Overview
description: What lattices is and who it's for
order: 0
---

lattices is a macOS developer workspace manager. A native menu bar app
handles window tiling, project navigation, on-screen OCR, and optionally
tmux-powered terminal sessions. Your AI coding agents can use it too.

## The problem

I kept losing track of windows. Terminal here, dev server there, browser
somewhere on the second monitor, three other projects buried under it all.
Every morning I'd rebuild the same layout. Half my context-switching was
just hunting for the right window.

AI agents have it worse. They're stuck inside a single shell with no way
to see what's on screen, arrange windows, or jump between projects.

## The solution

lattices fixes both sides:

- The menu bar app tiles windows, navigates projects, and manages
  workspace layers through a command palette. Add tmux if you want
  persistent terminal sessions with auto-layout.
- The daemon API exposes 30 RPC methods over WebSocket. Agents can
  discover projects, tile windows, switch layers, read on-screen text
  via OCR, and launch sessions programmatically.

## What's included

| Component | Description |
|-----------|-------------|
| **CLI** | The `lattices` command. Tile windows, manage sessions, control the workspace from your terminal |
| **Menu bar app** | Native macOS companion. Command palette, window tiling, project discovery |
| **Daemon API** | WebSocket server on `ws://127.0.0.1:9399`. 30 methods, 5 real-time events |
| **OCR engine** | Reads text from visible windows using Apple Vision, indexes it with FTS5 |
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
- People building AI agents that need to control the desktop
- Power users who work across multiple macOS Spaces
- tmux users who want persistent, auto-configured terminal sessions

## Requirements

- macOS 13.0+
- Node.js 18+

### Dev dependencies

- Swift 5.9+ — only to build the menu bar app from source
- tmux — needed for persistent terminal sessions (`brew install tmux`)

## Next steps

- [Quickstart](/docs/quickstart): install and run your first session in 2 minutes
- [Configuration](/docs/config): `.lattices.json` format and CLI commands
- [Screen OCR](/docs/ocr): Vision-powered screen reading and full-text search
- [Concepts](/docs/concepts): architecture, glossary, and how it all works
- [Daemon API](/docs/api): RPC method reference for agents and scripts
