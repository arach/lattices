---
name: lattices
description: Drive a macOS developer workspace through Lattices. Use when tiling or placing windows, launching tmux sessions, searching screen text or OCR, switching workspace layers, focusing apps, or calling the local Lattices daemon API.
compatibility: Requires macOS with the Lattices menu bar app running (ws://127.0.0.1:9399).
metadata:
  author: arach
  homepage: https://lattices.dev
---

# Lattices

Lattices is a macOS workspace manager. The menu bar app hosts a local daemon at
`ws://127.0.0.1:9399`. Agents drive it with the `lattices` CLI.

When this skill is invoked, run the command. Summarize the result. Do not
narrate the plan first. Spoken commands belong to the `speech` skill. Native
clicks, capture, and Action-owned Chrome belong to the `action` skill.

## Prerequisite

The daemon must be running:

```bash
lattices daemon status
```

If that fails, start the app with `lattices app` and retry. Do not invent
window IDs, session names, or layer names. Read them from the CLI first.

## Choose a surface

Prefer the CLI. Use `lattices call` only when no dedicated command exists.
Use `daemonCall` from `@arach/lattices` only in scripts.

| Need | Command |
| --- | --- |
| What is in front of the user | `lattices call desktop.snapshot` |
| ASCII map of the current space | `lattices map` |
| Find a window | `lattices search <query> --deep` |
| Place a window | `lattices place <query> <position>` |
| Tile the frontmost window | `lattices tile <position>` |
| Launch or attach this repo | `lattices start` |
| Screen text | `lattices scan` |
| Search screen text | `lattices scan search "<query>"` |
| Switch a layer | `lattices layer <name-or-index>` |
| Raw RPC | `lattices call <method> '<json>'` |
| Method catalog | `lattices call api.schema` |

`--deep` and `--all` both request every search source (index plus live
terminal inspection). Use them when the project name appears in cwd or tab
data rather than the window title.

## Canonical mutations

Use these action identifiers. Legacy names still exist as wrappers.

| Action | Use for |
| --- | --- |
| `window.place` | Place a window or session with a typed placement |
| `layer.activate` | Bring up a workspace layer |
| `space.optimize` | Rebalance windows with an explicit scope and strategy |

`window.tile` is `window.place`. `layer.switch` is `layer.activate` with
`mode=launch`. `layout.distribute` is `space.optimize` with
`scope=visible` and `strategy=balanced`.

Resolve before mutating when the target identity matters:

```bash
lattices call window.resolve '{"target":{"kind":"session","session":"frontend-a1b2c3"},"placement":"left"}'
lattices call actions.execute '{"type":"window.place","target":{"kind":"session","session":"frontend-a1b2c3"},"args":{"placement":"left"},"dryRun":true}'
```

Undo the latest undoable placement with `lattices call actions.undo '{}'`.

## Recipes

### Place a project window

```bash
lattices search frontend --deep
lattices place frontend left
```

Default place position is `bottom-right`. Positions include `left`, `right`,
`top`, `bottom`, `maximize`, `center`, and the four corners.

### Launch two sessions and tile them

```bash
lattices call session.launch '{"path":"/Users/you/dev/frontend"}'
lattices call session.launch '{"path":"/Users/you/dev/api"}'
lattices call tmux.sessions
lattices call window.place '{"session":"frontend-a1b2c3","placement":"left"}'
lattices call window.place '{"session":"api-b4c5d6","placement":"right"}'
```

Session names are `<basename>-<sha256-6chars>`. Read the live name from
`lattices sessions --json` or `tmux.sessions`. Do not guess the hash.

### Read the screen

```bash
lattices scan
lattices scan --full
lattices scan search "error"
lattices scan recent 10
lattices scan deep
```

`scan` is accessibility text. `scan deep` triggers Vision OCR, then read the
fresh snapshot. Results are tagged `AX` or `OCR`. Each window has a `wid` for
`lattices scan history <wid>`.

### Switch a layer

```bash
lattices layer
lattices layer 0
lattices layer web
```

## Scripts

From Node:

```js
import { daemonCall, isDaemonRunning } from '@arach/lattices'

if (!(await isDaemonRunning())) {
  throw new Error('Lattices daemon is not running. Start it with: lattices app')
}

const windows = await daemonCall('windows.list')
```

`scripts/connect.js` prints daemon health, running projects, and session
layers. Run it with `node scripts/connect.js` from this skill directory when
the CLI package is installed.

## Live docs

Do not copy the full RPC catalog into context. Read it when needed:

1. `lattices call api.schema`
2. https://lattices.dev/docs/agents
3. https://lattices.dev/docs/api
4. https://lattices.dev/docs/workspace-map
