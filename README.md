

![lattices](https://lattices.dev/og.png)

# lattices

**Turn your Mac into a workspace you can drive — by hand, by voice, or by agent.**

Menu bar app + CLI + local WebSocket daemon. Tile windows, keep terminal
sessions alive, search what's on screen, and switch whole project contexts
in one keystroke.

**[lattices.dev](https://lattices.dev)** · [Docs](https://lattices.dev/docs/overview) · [Download app](https://github.com/arach/lattices/releases/latest)

## Product family

**Lattices** organizes and drives the workspace.

**[Action](https://lattices.dev/action)** is the focused computer-use product for
observing a Mac surface, acting on explicit targets, recording the run, and
verifying what changed. It lives in [`products/action`](products/action).

**[Blink](https://lattices.dev/blink)** is spatial notes: each note is a floating
panel, and the desktop is the workspace. It lives in
[`products/blink`](products/blink).

Action and Blink remain separately signed apps. Do not fold them into the
Lattices menu bar process.

## What you can do

**Spin up a project in seconds** — `lattices start` opens a tmux layout from
`.lattices.json` (or auto-detects your dev server). Sessions survive reboots.

**Tile anything, instantly** — snap windows to halves, quarters, and grids from
the command palette (`Cmd+Shift+M`), hotkeys, or `lattices place myapp left`.

**Find windows by what they contain** — search titles, apps, terminal cwd, tmux
session tags, and OCR text: `lattices search vox --deep`.

**Switch whole workspaces** — layers tile multiple projects at once
(`Cmd+Option+1/2/3`). Tab groups bundle related repos into one session.

**Read the screen** — continuous UI text + periodic Vision OCR, searchable from
CLI or API: `lattices scan search "error"`.

**Talk to your desktop** — voice commands for tile, focus, search, and launch
(beta, via the menu bar app).

**Give agents the keys** — 35+ daemon RPC methods on `ws://127.0.0.1:9399`.
Launch sessions, tile windows, switch layers, subscribe to live events.

## Install

```sh
npm install -g @arach/lattices
```

Also on npm as `@lattices/cli`. macOS only. Requires Node 18+ or Bun. Optional: `brew install tmux` for
persistent sessions; [download the app](https://github.com/arach/lattices/releases/latest)
for palette, layers, and voice.

## Try it

```sh
lattices app          # menu bar companion (daemon + palette)
lattices start        # tmux workspace for this repo
lattices search api --deep
lattices place frontend left
```

## Agent skills

This repository is the skills.sh catalog for the Lattices product family.

| Skill | Product | Use it for |
| --- | --- | --- |
| [`lattices`](skills/lattices/SKILL.md) | Lattices | Tile windows, launch sessions, search the screen |
| [`action`](skills/action/SKILL.md) | Action | Observe, resolve, act, and record on macOS |
| [`speech`](skills/speech/SKILL.md) | Lattices | Spoken commands and voice intents |
| [`blink`](skills/blink/SKILL.md) | Blink | Create, place, and edit spatial notes |

Install every skill globally:

```sh
npx skills add arach/lattices --all --global --yes
```

Install one skill:

```sh
npx skills add arach/lattices --skill lattices --global --yes
npx skills add arach/lattices --skill action --global --yes
npx skills add arach/lattices --skill speech --global --yes
npx skills add arach/lattices --skill blink --global --yes
```

List without installing:

```sh
npx skills add arach/lattices --list
```

Action Browser remains a standalone plugin, `action-browser@action`.
See [products/action](products/action).

## For agents & scripts

```js
import { daemonCall } from '@arach/lattices/daemon-client'

await daemonCall('session.launch', { path: '/Users/you/dev/api' })
await daemonCall('window.place', { session: 'api-a1b2c3', placement: 'right' })
const hits = await daemonCall('windows.search', { query: 'myproject' })
```

Full API: [lattices.dev/docs/api](https://lattices.dev/docs/api)

## More

`lattices help` for the full CLI · [layers & groups](https://lattices.dev/docs/layers) · [voice](https://lattices.dev/docs/voice)

MIT
