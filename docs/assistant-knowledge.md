---
type: Assistant Knowledge Base
title: Lattices — Assistant Knowledge
description: Orientation + capability map the in-app Workspace Assistant uses to explain Lattices and point to the right feature or doc
audience: assistant
---

> You are reading the Workspace Assistant's knowledge base. It summarizes what
> Lattices can do and links to the deeper docs. Treat the **structured context**
> in your prompt (current settings, file paths, CLI commands) as ground truth for
> *this user's* configuration; treat this file as ground truth for *how Lattices
> works*. When a question goes deeper than this summary, name the relevant doc
> (see [References](#references)) instead of guessing.

## What Lattices is

Lattices is an **agentic window manager for macOS** — a programmable workspace
that pairs a native menu bar app with managed tmux sessions and a scriptable
agent API. Three layers, one product:

1. **Programmable workspace** — a CLI and a WebSocket agent API (`ws://127.0.0.1:9399`,
   35+ methods, real-time events) that let scripts and AI agents observe and drive
   the desktop the same way a person does.
2. **Smart layout manager** — the menu bar app tracks every window across all
   monitors: tiling, switchable layers, snap zones, and screen-text indexing.
3. **Managed tmux sessions** — declare a dev environment in `.lattices.json`;
   Lattices builds it, runs it, and keeps it alive across reboots.

Requirements: macOS 26+, Node 18+; tmux only for session management.
See [Overview](/docs/overview) and [Concepts](/docs/concepts).

## Capability map

Each area below is a one-paragraph summary plus the doc to cite for detail.

### Window tiling & placement
Snap windows to preset positions — halves, quarters, thirds, maximize, center —
from the command palette or `lattices tile <position>`. There is also a grid
placement primitive (`grid:CxR:c,r`) surfaced through an overlay and a command
bar. → [Tiling reference](/docs/tiling-reference), positions in [Configuration](/docs/config).

### Workspace layers & tab groups
Group projects into named **layers** you can switch between, and tab-group related
windows. `workspace.json` layers launch/focus/tile projects. Studio layers are
rule-backed live window sets persisted in `~/.lattices/layers.json`; their clauses
support app/title/session exact, substring, regex, Space, visibility, and exclusion
matches. → [Layers](/docs/layers).

### Command palette & menu bar app
The palette (**Cmd+Shift+M**) is the app's primary surface: launch projects, tile,
sync, restart, open settings — all searchable. → [Menu Bar App](/docs/app).

### tmux sessions (`.lattices.json`)
Declare panes, commands, and layout per project. `lattices start` builds/attaches a
persistent session named `<basename>-<hash>`; `lattices sync` reconciles a running
session to its config. **Ensure** re-runs exited commands on reattach; **prefill**
types them and waits. → [Concepts](/docs/concepts), [Configuration](/docs/config).

### Screen OCR & search
The app reads on-screen text via the Accessibility API (~60s) and Apple Vision OCR
on background windows (~2h), indexing everything with FTS5. Search across titles,
app names, session tags, and OCR with `lattices search <query>` (add `--deep` to
inspect terminal tabs by cwd). → [Screen OCR & Search](/docs/ocr).

### Voice commands
Natural-language voice control for window management ("put the browser on the
right", "switch to the backend layer"). → [Voice Commands](/docs/voice).

### Mouse gestures
Hold a mouse button, draw a direction or shape, release — runs the matched action.
Configured via `mouseGestures.enabled` plus `~/.lattices/mouse-shortcuts.json`.
→ [Mouse Gestures](/docs/mouse-gestures).

### Agent API & CLI
Agents connect over WebSocket and get the same control as a person: list
windows/projects, launch sessions, tile, switch layers, read screen text, and
subscribe to events (`windows.changed`, `tmux.changed`, `layer.switched`).
→ [Agent Guide](/docs/agents), [Agent API](/docs/api).

### Project twins
Pi-backed project "twins" for mediated, persistent agent execution scoped to a
project. → [Project Twins](/docs/twins).

## Key shortcuts

| Shortcut | Action |
|----------|--------|
| **Cmd+Shift+M** | Open the command palette |
| `lattices tile <position>` | Tile the focused window (CLI) |
| `lattices layer [name\|index]` | Switch workspace layer (CLI) |
| **Ctrl+B** then `D` / `Z` / arrows | tmux: detach / zoom / move pane (inside a session) |

Tiling and grid hotkeys are user-configurable — for the live set, point the user to
Settings or the [Tiling reference](/docs/tiling-reference) rather than asserting one.

## CLI quick reference

`lattices` · `lattices init` · `lattices sync` · `lattices start` ·
`lattices restart [pane]` · `lattices tile <position>` · `lattices group [id]` ·
`lattices layer [name|index]` · `lattices windows --json` ·
`lattices search <query> [--deep] [--json] [--wid]` · `lattices place <query> [position]` ·
`lattices app restart`. Full flags: [Configuration](/docs/config).

## Config & file locations

- **Per project:** `.lattices.json` in the project root (panes, commands, layout, ensure/prefill).
- **User config (`~/.lattices/`):** `workspace.json`, `layers.json`, `mouse-shortcuts.json`,
  `snap-zones.json`, `clusters.json`, `ocr.db`, `lattices.log`.
- **Defaults domain:** `dev.lattices.app` (read/write app settings via `defaults`).

The exact current values and paths for *this* machine arrive in your structured
context — prefer those over the generic paths above when answering.

## References

| Topic | Doc |
|-------|-----|
| What it is / who it's for | [Overview](/docs/overview) |
| Install & first run | [Quickstart](/docs/quickstart) |
| Architecture, glossary, internals | [Concepts](/docs/concepts) |
| `.lattices.json`, CLI, tile positions | [Configuration](/docs/config) |
| Command palette, tiling, sessions | [Menu Bar App](/docs/app) |
| Tiling & grid placement | [Tiling reference](/docs/tiling-reference) |
| Layers & tab groups | [Layers](/docs/layers) |
| Screen OCR & full-text search | [Screen OCR & Search](/docs/ocr) |
| Voice control | [Voice Commands](/docs/voice) |
| Mouse gestures | [Mouse Gestures](/docs/mouse-gestures) |
| Agent contracts (voice/CLI/daemon) | [Agent Guide](/docs/agents) |
| WebSocket RPC method reference | [Agent API](/docs/api) |
| Project twins | [Project Twins](/docs/twins) |
