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

**Explore the companion apps:** [Action](products/action/README.md) · [Blink](products/blink/README.md) · [Speech / Voice](products/voice/README.md)

## Start with your desktop

1. [Download Lattices for Mac](https://github.com/lattices-dev/lattices/releases/latest), open the DMG, and drag Lattices to Applications.
2. Launch Lattices and grant Accessibility access when prompted. Enable Screen Recording for screen capture and OCR.
3. Press **Control+Option+Left** to tile the frontmost window to the left half of your screen. Press **Control+Option+Space** to open the command bar.

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

The npm package is macOS-only. For a Hyprland machine, use the [Linux host](#linux-host).

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

## Linux host

The [Linux host](packages/host-linux/README.md) exposes a Hyprland desktop to other Lattices machines over Tailscale. A Mac can inspect, place, and visit its windows through the same API envelope (`{id, method, params}`). The host listens on its tailnet IPv4 address and `127.0.0.1`, port 9399. Non-loopback clients must pair; loopback is trusted. The visit bridge uses port 5287.

Install Bun and Tailscale, then run these commands inside a Hyprland session. Visiting also requires Quickshell for the cursor overlay and `wtype` for keyboard input.

```sh
bun install --cwd packages/host-linux --ignore-scripts --omit optional
bun packages/host-linux/src/main.ts
```

For tray controls and systemd user units:

```sh
bun packages/host-linux/scripts/install-tray.ts
systemctl --user enable --now lattices-host
```

The tray installer enables the tray. The second command also enables the host at login. Keep the checkout in place because the units use its paths.

From a Mac with `lats` installed:

```sh
lats hosts add archie archie
lats --host archie pair              # approve the code on archie
lats --host archie call host.describe
lats --host archie call windows.place '{"app":"firefox","placement":"left"}'
```

Pairing requests the `act` scope by default. Use `--read-only` or `--drive` to request a different scope. Wider access requires a new approval. `lats hosts` lists configured hosts; `lats hosts --discover` probes your online tailnet devices. See the [host README](packages/host-linux/README.md) for capabilities and pairing controls.

## Machines

Open **Workspace → Machines** to arrange this Mac's displays and paired machines. Drag a machine against a display to choose the edge where your pointer crosses. Moving a local display creates a draft: **Apply** starts a 15-second trial, **Keep** accepts it, and **Revert** restores the previous arrangement. Opening Machines does not arm a visit.

A visit lends this Mac's mouse and keyboard to a paired machine. Pair the visit bridge, choose an edge, then arm crossing:

```sh
lats visit pair archie               # bridge defaults to archie:5287; approve there
lats visit side archie left
lats visit on
lats visit archie                    # enter immediately
```

The host draws a labelled visitor cursor while the Mac pointer stays parked. Return through the entry edge, press **Control+Option+Command+Home**, or run `lats visit end` to finish. `lats home` also returns the pointer to the center of the Mac's main display. A disconnected or unresponsive visit ends automatically.

```sh
lats visit off                      # disarm edge crossing
lats visit status
lats visit screens
lats elsewhere 2 archie             # this display shows the paired machine
lats here 2
lats visit host on                  # explicitly allow visits to this Mac
lats visit host off
lats machines                      # local machine, configured hosts, and visit pairings
lats @archie call windows.list      # API call on a configured host
lats bring dell                     # bring other displays' windows to this display
lats bring --undo
lats main dell                      # try a different main display for 15 seconds
lats main dell --keep
```

Visit pairing and API host configuration are separate. `lats @<host>` forwards daemon commands to a configured address; it does not make a Mac's loopback daemon remotely reachable. Read the [visit guide](docs/visit.md) for placement, receiving visits, and arrangement recovery.

## Keyboard

These are the default bindings. Hyper means Control+Option+Shift+Command.

| Shortcut | Action |
| --- | --- |
| **Control+Left / Right** | Switch Spaces instantly |
| **Control+Option+arrows** | Tile the frontmost window to a half |
| **Control+Option+1–9** | Place the window in a cell of the 3×3 matrix |
| **Control+Option+Shift+1 / 2 / 3** | Tile thirds |
| **Control+Option+Space** | Open the command bar |
| **Command+Option+1–9** | Aim a workspace layer; release to switch. Slot 5 shows the current layer |
| **Hyper+1** | Workspace home |
| **Hyper+L** | Overview |

Voice Command is rebindable and has no default shortcut. Hold Option while the command bar has keyboard focus to speak. See [App and shortcuts](https://lattices.dev/docs/app) for the remaining bindings.

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

You can also expose the CLI as a stdio MCP server:

```sh
lats mcp
lats mcp --list
lats mcp --print-config claude       # also: codex or kimi
```

Use the installed `lattices` binary with arguments `["mcp"]` in agent configuration. The `browser` and `hosts` toolsets can be selected with `--toolsets`. See the [MCP guide](docs/mcp.md).

## The Lattices family

Each product has its own app, README, and source directory. Start here:

| Product | What it adds |
| --- | --- |
| **[Lattices](https://lattices.dev)** | A programmable workspace: windows, projects, screen search, and terminals. |
| **[Action](products/action/README.md)** | Computer use for agents: observe apps, operate browser surfaces, and record what happened. |
| **[Blink](products/blink/README.md)** | Spatial notes: editable notes that live in floating windows on your desktop. |
| **[Speech / Voice](products/voice/README.md)** | Spoken agent output with queued playback and a readalong HUD. |

Action, Blink, and Voice have independent installation and runtime lifecycles. Their source lives together under [`products/`](products/). [Explore the family](https://lattices.dev/family).

## Build and contribute

```sh
git clone https://github.com/lattices-dev/lattices.git
cd lattices
bun install
bun link
bun run check
bun run test
bun run linux:app # Linux desktop app (Bun + Quickshell)
```

The native app uses Swift 6.2 / Xcode 26+. See [AGENTS.md](https://github.com/lattices-dev/lattices/blob/main/AGENTS.md) for component boundaries and build instructions.

| Source | Purpose |
| --- | --- |
| `apps/mac` | SwiftUI/AppKit app and local daemon |
| `bin` | CLI, app helper, API client, and MCP server |
| `packages/host-linux` | Hyprland host, visit bridge, and tray |
| `swift` | LatticesTerminalKit and DeckKit |
| `products` | Companion products |
| `skills` | Agent skills |
| `apps/site` | Website and documentation |

## Documentation

[Quickstart](https://lattices.dev/docs/quickstart) · [App and shortcuts](https://lattices.dev/docs/app) · [Configuration](https://lattices.dev/docs/config) · [Layers](https://lattices.dev/docs/layers) · [Screen search](https://lattices.dev/docs/ocr) · [API](https://lattices.dev/docs/api) · [Visits](docs/visit.md) · [Linux host](packages/host-linux/README.md)

## License

[MIT](https://github.com/lattices-dev/lattices/blob/main/LICENSE)

Linux setup: [apps/linux/README.md](apps/linux/README.md).
