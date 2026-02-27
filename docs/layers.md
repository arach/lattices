---
title: Workspace Layers & Tab Groups
description: Group projects into switchable layers and tabbed groups
order: 4
---

# Workspace Layers & Tab Groups

Two ways to organize related projects in `~/.lattice/workspace.json`:

- **Layers** — switchable contexts that focus and tile windows
- **Tab groups** — related projects as tabs within a single terminal window

Both features are configured in the same workspace config and
work together.

## Tab Groups

Tab groups let you bundle related projects as tabs (tmux windows)
within a single tmux session. This is useful when you have a family
of projects — like an iOS app, macOS app, website, and API — that
you think of as one logical unit.

### Configuration

Add `groups` to `~/.lattice/workspace.json`:

```json
{
  "name": "my-setup",
  "groups": [
    {
      "id": "talkie",
      "label": "Talkie",
      "tabs": [
        { "path": "/Users/you/dev/talkie-ios", "label": "iOS" },
        { "path": "/Users/you/dev/talkie-macos", "label": "macOS" },
        { "path": "/Users/you/dev/talkie-web", "label": "Website" },
        { "path": "/Users/you/dev/talkie-api", "label": "API" }
      ]
    }
  ]
}
```

Each tab's pane layout comes from its own `.lattice.json` — no changes
to per-project configs.

### How it works

- **Session naming**: `lattice-group-<id>` (e.g. `lattice-group-talkie`)
- **tmux mapping**: 1 group = 1 tmux session, each tab = 1 tmux window,
  each window has its own panes from that project's `.lattice.json`
- **Independent launch still works**: `cd talkie-ios && lattice` creates
  its own standalone session as before

### Tab group fields

| Field          | Type     | Description                          |
|----------------|----------|--------------------------------------|
| `id`           | string   | Unique identifier for the group      |
| `label`        | string   | Display name shown in the UI         |
| `tabs`         | array    | List of tab definitions              |
| `tabs[].path`  | string   | Absolute path to project directory   |
| `tabs[].label` | string?  | Tab name (defaults to directory name) |

### CLI commands

```bash
lattice groups             # List all groups with status
lattice group <id>         # Launch or attach to a group
lattice tab <group> [tab]  # Switch tab by label or index
```

Examples:

```bash
lattice group talkie       # Launch all Talkie tabs
lattice tab talkie iOS     # Switch to the iOS tab
lattice tab talkie 0       # Switch to first tab (by index)
```

### Menu bar app

Tab groups appear above the project list in the menu bar panel.
Each group row shows:

- Status indicator (running/stopped)
- Tab count badge
- Expand/collapse to see individual tabs
- Launch/Attach and Kill buttons
- Per-tab "Go" buttons to switch and focus a specific tab

The command palette also includes group commands:

| Command                    | Description                            |
|----------------------------|----------------------------------------|
| Launch *group*             | Start the group session                |
| Attach *group*             | Focus the running group session        |
| *Group*: *Tab*             | Switch to a specific tab in a group    |
| Kill *group* Group         | Terminate the group session            |

## Layers

Layers let you group projects into switchable contexts. Instead of
juggling six terminal windows at once, define two or three layers and
switch between them instantly — the target layer's windows come to the
front and tile into position, while the previous layer's windows fall
behind.

All tmux sessions stay alive across switches. Nothing is detached or
killed — layers only control which windows are focused.

### Configuration

Add `layers` to `~/.lattice/workspace.json`:

```json
{
  "name": "my-setup",
  "layers": [
    {
      "id": "web",
      "label": "Web",
      "projects": [
        { "path": "/Users/you/dev/frontend", "tile": "left" },
        { "path": "/Users/you/dev/api", "tile": "right" }
      ]
    },
    {
      "id": "mobile",
      "label": "Mobile",
      "projects": [
        { "path": "/Users/you/dev/ios-app", "tile": "left" },
        { "path": "/Users/you/dev/backend", "tile": "right" }
      ]
    }
  ]
}
```

### Using groups in layers

Layer projects can reference a tab group instead of a single path.
This lets you tile a whole group into a screen position:

```json
{
  "name": "my-setup",
  "groups": [
    {
      "id": "talkie",
      "label": "Talkie",
      "tabs": [
        { "path": "/Users/you/dev/talkie-ios", "label": "iOS" },
        { "path": "/Users/you/dev/talkie-web", "label": "Website" }
      ]
    }
  ],
  "layers": [
    {
      "id": "main",
      "label": "Main",
      "projects": [
        { "group": "talkie", "tile": "top-left" },
        { "path": "/Users/you/dev/design-system", "tile": "right" }
      ]
    }
  ]
}
```

When switching to this layer, lattice launches (or focuses) the
"talkie" group session and tiles it to the top-left quarter, alongside
the design-system project on the right.

### Layer fields

| Field             | Type     | Description                              |
|-------------------|----------|------------------------------------------|
| `name`            | string   | Workspace name (for your reference)      |
| `layers`          | array    | List of layer definitions                |
| `layers[].id`     | string   | Unique identifier (e.g. `"web"`)         |
| `layers[].label`  | string   | Display name shown in the UI             |
| `layers[].projects` | array  | Projects in this layer                   |
| `projects[].path` | string?  | Absolute path to project directory       |
| `projects[].group`| string?  | Group ID (alternative to `path`)         |
| `projects[].tile` | string?  | Tile position (optional, see below)      |

Each project entry must have either `path` or `group`, not both.

### Tile values

Any tile position from the [config reference](/docs/config#tile-positions)
works: `left`, `right`, `top-left`, `top-right`, `bottom-left`,
`bottom-right`, `maximize`, `center`.

### Switching layers

Three ways to switch:

| Method               | How                                      |
|----------------------|------------------------------------------|
| **Hotkey**           | Cmd+Option+1, Cmd+Option+2, Cmd+Option+3... |
| **Layer bar**        | Click a layer pill in the menu bar panel |
| **Command palette**  | Search "Switch to Layer" in Cmd+Shift+M  |

When you switch to a layer:

1. Each project's terminal window is **raised and focused**
2. If a project isn't running yet, it gets **launched** automatically
3. Windows with a `tile` value are **tiled** to that position
4. The previous layer's windows stay open behind the new ones

The app remembers which layer was last active across restarts.

### Programmatic switching

Agents and scripts can switch layers via the daemon API:

```js
import { daemonCall } from 'lattice/daemon-client'

// List available layers
const { layers, active } = await daemonCall('layers.list')
console.log(`Active: ${layers[active].label}`)

// Switch to a layer by index
await daemonCall('layer.switch', { index: 0 })
```

The `layer.switch` call focuses and tiles all windows in the target
layer, just like the hotkey or command palette. A `layer.switched`
event is broadcast to all connected clients.

See the [Daemon API reference](/docs/api) for more methods.

### Layer bar

When a workspace config is loaded, a layer bar appears between the
header and search field in the menu bar panel:

```
 lattice  2 sessions              [↔] [⟳]
┌────────────────────────────────────────┐
│  ● Web          ○ Mobile               │
│  ⌥1             ⌥2                     │
└────────────────────────────────────────┘
 Search projects...
```

- Active layer: filled green dot
- Inactive layers: dim outline dot
- Hotkey hints shown below each label

## Layout examples

### Single project

```json
{
  "projects": [
    { "path": "/Users/you/dev/talkie" }
  ]
}
```

No `tile` — just focuses the window wherever it is.

### Two-project split

```json
{
  "projects": [
    { "path": "/Users/you/dev/app", "tile": "left" },
    { "path": "/Users/you/dev/api", "tile": "right" }
  ]
}
```

### Group + project

```json
{
  "projects": [
    { "group": "talkie", "tile": "left" },
    { "path": "/Users/you/dev/api", "tile": "right" }
  ]
}
```

### Four quadrants

```json
{
  "projects": [
    { "path": "/Users/you/dev/frontend", "tile": "top-left" },
    { "path": "/Users/you/dev/backend", "tile": "top-right" },
    { "path": "/Users/you/dev/mobile", "tile": "bottom-left" },
    { "path": "/Users/you/dev/infra", "tile": "bottom-right" }
  ]
}
```

## Tips

- Projects don't need a `.lattice.json` config to be in a layer — any
  directory path works. If the project has a config, lattice uses it; if
  not, it opens a plain terminal in that directory.
- You can have up to 9 layers (Cmd+Option+1 through Cmd+Option+9).
- Edit `workspace.json` by hand — the app re-reads it on launch. Use
  the Refresh Projects button or restart the app to pick up changes.
- The `tile` field is optional. Omit it if you just want the window
  focused without repositioning.
- Tab groups and standalone projects can coexist in the same workspace.
  Use groups for related project families, standalone paths for
  individual projects.
