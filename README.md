<p align="center">
  <img src="https://raw.githubusercontent.com/lattices-dev/lattices/main/assets/hero.svg" width="100%" alt="Lattices: workspaces for agents (and you)" />
</p>

<h1 align="center">Lattices</h1>

<p align="center"><strong>Workspaces for agents (and you)</strong><br />
Arrange your windows, move between projects, and give your agents the same desktop controls you use.</p>

<p align="center">
  <a href="https://lattices.dev">Website</a> ·
  <a href="https://lattices.dev/docs/quickstart">Get started</a> ·
  <a href="https://lattices.dev/docs/api">Agent API</a> ·
  <a href="https://github.com/lattices-dev/lattices/releases/latest">Download for Mac</a>
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/@lattices/lattices"><img alt="npm version" src="https://img.shields.io/npm/v/@lattices/lattices.svg" /></a>
  <a href="https://github.com/lattices-dev/lattices/blob/main/LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-informational.svg" /></a>
  <img alt="macOS 26 or later" src="https://img.shields.io/badge/macOS-26%2B-black.svg" />
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/lattices-dev/lattices/main/assets/readme-demo.gif" width="100%" alt="Lattices arranging windows with gesture previews and shared workspace state" />
</p>

Lattices is a native macOS app with a command bar, window tiling, workspace layers, screen search, and persistent terminal sessions. Use hotkeys and mouse gestures yourself, or let an agent inspect and arrange the same workspace through `lats` and the local API.

## Start with your desktop

1. [Download Lattices for Mac](https://github.com/lattices-dev/lattices/releases/latest), open the DMG, and drag Lattices to Applications.
2. Launch Lattices and grant Accessibility access when prompted. Enable Screen Recording for screen capture and OCR.
3. Press **Control+Option+Left** to tile the frontmost window to the left half of your screen. Press **Command+Shift+M** to open the command palette.

The app requires macOS 26 or later. tmux is optional: window management, layers, search, and the agent API work without it.

| Your workspace | What Lattices does |
| --- | --- |
| Windows | Tile halves, thirds, quarters, and grids with hotkeys, gestures, the command bar, or the API. |
| Projects | Group windows into workspace layers and return to a working context. |
| Spaces | Move between macOS desktops with instant switching and a desktop preview. |
| Search | Find windows by title, app, terminal directory, session, and indexed screen text. |
| Terminals | Define panes in `.lattices.json` and reattach to persistent tmux sessions. |
| Agents | Expose the same workspace through a local API and installable skills. |

## Install the command line tools

Install [Bun](https://bun.sh) to run the CLI. You can install the package with npm (Node 18+) or Bun:

```sh
npm install -g @lattices/lattices
lats app
lats
```

`lats app` launches the bundled menu bar app. Bare `lats` shows workspace status. Both `lats` and `lattices` run the same CLI.

```sh
lats search api --deep
lats tile right
lats map
```

The [setup guide](https://lattices.dev/docs/quickstart) covers Homebrew, login startup, permissions, and the one-command installer.

### Existing installations

`@arach/lattices` and `@lattices/cli` remain supported compatibility packages. They receive the same CLI, exports, and bundled app as `@lattices/lattices`. Update using the package name you already installed. From version 0.14.1, `lats app upgrade` also preserves that package name.

The repository moved from `arach/lattices` to `lattices-dev/lattices`. Existing Git remotes and release links redirect to the new location. Your configuration, sessions, and app identity stay the same. See the [migration guide](https://lattices.dev/docs/namespace-migration).

## Keep a terminal session alive

Install tmux (`brew install tmux`), then:

```sh
cd ~/your-project
lats init
lats start
```

`lats init` creates `.lattices.json`. `lats start` creates or reattaches the project's tmux session; `lats tmux` is an alias. Close your terminal and run `lats start` again to return to the session.

```json
{
  "ensure": true,
  "panes": [
    { "name": "shell", "size": 60 },
    { "name": "server", "cmd": "bun dev" }
  ]
}
```

## Give your agents workspace access

Install the family skills:

```sh
npx skills add lattices-dev/lattices --all --global --yes
```

Inspect the live API or call it directly:

```sh
lats daemon status
lats call api.schema
lats call windows.search '{"query":"api"}'
```

For a script, install the package in your project (`npm install @lattices/lattices`):

```js
import { daemonCall, isDaemonRunning } from '@lattices/lattices'

if (!(await isDaemonRunning())) {
  throw new Error('Start Lattices with: lats app')
}

const windows = await daemonCall('windows.search', { query: 'api' })
console.log(windows)
```

The app hosts the API at `ws://127.0.0.1:9399`. It is local-only and has no authentication; any process on your Mac can connect. Read the [API reference](https://lattices.dev/docs/api) and [agent guide](https://lattices.dev/docs/agents) for methods, events, and permissions.

## The Lattices family

| Product | What it adds |
| --- | --- |
| **[Lattices](https://lattices.dev)** | A programmable workspace: windows, projects, screen search, and terminals. |
| **[Action](https://lattices.dev/action)** | Computer use for agents: observe apps, operate browser surfaces, and record what happened. |
| **[Blink](https://lattices.dev/blink)** | Spatial notes: editable notes that live in floating windows on your desktop. |
| **[Speech](https://lattices.dev/speech)** | Spoken agent output with queued playback and a readalong HUD. |

Action and Blink are separate apps with their own installation and runtime lifecycles. Their source lives in this repository. [Explore the family](https://lattices.dev/family).

## Build and contribute

```sh
git clone https://github.com/lattices-dev/lattices.git
cd lattices
bun install
bun link
bun run check
bun run test
```

The native app uses Swift 6.2 / Xcode 26+. See [AGENTS.md](https://github.com/lattices-dev/lattices/blob/main/AGENTS.md) for component boundaries and build instructions.

| Source | Purpose |
| --- | --- |
| `apps/mac` | SwiftUI/AppKit app and local daemon |
| `bin` | CLI, app helper, and API client |
| `swift` | LatticesTerminalKit and DeckKit |
| `products` | Companion products |
| `skills` | Agent skills |
| `apps/site` | Website and documentation |

## Documentation

[Quickstart](https://lattices.dev/docs/quickstart) · [App and shortcuts](https://lattices.dev/docs/app) · [Configuration](https://lattices.dev/docs/config) · [Layers](https://lattices.dev/docs/layers) · [Screen search](https://lattices.dev/docs/ocr) · [API](https://lattices.dev/docs/api)

## License

[MIT](https://github.com/lattices-dev/lattices/blob/main/LICENSE)
