---
title: Workspace Layers & Tab Groups
description: Group projects into switchable layers and tabbed groups
order: 4
---

Two ways to organize related projects in `~/.lattices/workspace.json`:

- **Layers** — switchable contexts that focus and tile windows
- **Tab groups** — related projects as tabs within a single terminal window

Both features are configured in the same workspace config and
work together.

## Tab Groups

Tab groups let you bundle related work into one Lattices tab stack.
A tab can be a terminal project or a native application window such as
Chrome, an editor, Notes, or a design tool. This is useful when several
windows belong to one topic and should share one screen position.

### Configuration

Add `groups` to `~/.lattices/workspace.json`:

```json
{
  "name": "my-setup",
  "groups": [
    {
      "id": "vox",
      "label": "Vox",
      "tabs": [
        { "path": "/Users/you/dev/vox", "label": "Terminal" },
        { "app": "Google Chrome", "title": "Vox", "url": "https://github.com/example/vox", "label": "Web" },
        { "app": "Visual Studio Code", "title": "vox", "launch": "Visual Studio Code", "label": "Editor" }
      ]
    }
  ]
}
```

Project tabs get their pane layout from their own `.lattices.json`.
App tabs are matched by app name and optional window-title substring.
`url` or `launch` tells Lattices how to open a missing app tab.

### How it works

- Each project tab keeps its normal `<basename>-<hash>` tmux session
- Native app tabs are tracked by `app` and optional `title`
- When a layer references the group with a `tile`, all matched windows
  collapse into that slot as a cross-app tab stack
- The HUD shows a Lattices tab strip for the active layer's first group
- The grid button fans the group out across the display; press it again
  to collapse the windows back into their shared slot
- You can still launch projects independently: `cd vox-ios && lattices start`
  creates its own standalone session as before

### Tab group fields

| Field          | Type     | Description                          |
|----------------|----------|--------------------------------------|
| `id`           | string   | Unique identifier for the group      |
| `label`        | string   | Display name shown in the UI         |
| `tabs`         | array    | List of tab definitions              |
| `tabs[].path`  | string?  | Absolute path for a terminal project tab |
| `tabs[].app`   | string?  | Application name for a native app tab |
| `tabs[].title` | string?  | Window-title substring used to select the right app window |
| `tabs[].url`   | string?  | URL to open when an app tab is missing |
| `tabs[].launch`| string?  | Application name passed to `open -a` when missing |
| `tabs[].label` | string?  | Tab name (defaults to directory or app name) |

Each tab needs either `path` or `app`.

### CLI commands

```bash
lattices groups             # List all groups with status
lattices group <id>         # Launch or attach to a group
lattices tab <group> [tab]  # Switch tab by label or index
```

Examples:

```bash
lattices group vox       # Launch all Vox terminal and app tabs
lattices tab vox Editor  # Open the editor tab
lattices tab vox 0       # Switch to first tab (by index)
```

### Menu bar app

Tab groups appear above the project list in the menu bar panel.
Each group row shows:

- Status indicator (running/stopped)
- Tab count badge
- Expand/collapse to see individual tabs
- Launch/Attach and Kill buttons
- Per-tab "Go" buttons to switch and focus a specific tab
- A grid/collapse button for changing between stack and overview

The command palette also includes group commands:

| Command                    | Description                            |
|----------------------------|----------------------------------------|
| Launch *group*             | Start the group session                |
| Attach *group*             | Focus the running group session        |
| *Group*: *Tab*             | Switch to a specific tab in a group    |
| Kill *group* Group         | Terminate the group session            |

### Live tab stacks

You do not need to edit `workspace.json` for an ad-hoc group. Open
Hyperspace, select two or more windows, and press **⌘T** (or choose
**Stack N as Tabs** from a selected window's menu). Lattices immediately
stacks those existing terminal, browser, editor, or other app windows in
the top-left and shows their switcher in the HUD.

Use a tab button to bring that member forward. Use the grid button to fan
the group out, then press it again to collapse back to the shared slot.
The × button ungroups the windows without closing them. Live stacks are
runtime-only; use the configured groups above when the group should return
after Lattices restarts.

The Workspace Assistant understands the same selection. With windows still
selected, say **“stack these as tabs”** or **“add these up.”** Agents can use
the `tabStacks.*` daemon methods described in the Agent API.

## Layers

Layers let you group projects into switchable contexts. Define two or
three layers and switch between them. The target layer's windows come
to the front and tile into position; the previous layer's windows fall
behind.

All tmux sessions stay alive across switches. Nothing is detached or
killed. Layers only control which windows are focused.

### Configuration

Add `layers` to `~/.lattices/workspace.json`:

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

### App windows in layers

Layers aren't limited to terminal sessions. You can include any
application window by using the `app`, `title`, `url`, and `launch`
fields instead of `path`:

```json
{
  "name": "hudson",
  "layers": [
    {
      "id": "main",
      "label": "Main",
      "projects": [
        { "app": "Google Chrome", "title": "GitHub", "tile": "left" },
        { "app": "Vox", "tile": "top-right", "launch": "open -a Vox" },
        { "path": "/Users/you/dev/frontend", "tile": "bottom-right" }
      ]
    },
    {
      "id": "docs",
      "label": "Docs",
      "projects": [
        { "app": "Google Chrome", "url": "https://docs.example.com", "tile": "left" },
        { "app": "Notes", "title": "Sprint Notes", "tile": "right" }
      ]
    }
  ]
}
```

When switching to a layer, lattices matches windows by `app` name and
optionally filters by `title` substring or `url` prefix. If `launch`
is provided and no matching window is found, the command is executed
to open the app.

### Using groups in layers

Layer projects can reference a tab group instead of a single path.
This lets you tile a whole group into a screen position:

```json
{
  "name": "my-setup",
  "groups": [
    {
      "id": "vox",
      "label": "Vox",
      "tabs": [
        { "path": "/Users/you/dev/vox-ios", "label": "iOS" },
        { "path": "/Users/you/dev/vox-web", "label": "Website" }
      ]
    }
  ],
  "layers": [
    {
      "id": "main",
      "label": "Main",
      "projects": [
        { "group": "vox", "tile": "top-left" },
        { "path": "/Users/you/dev/design-system", "tile": "right" }
      ]
    }
  ]
}
```

When switching to this layer, Lattices launches or focuses the "vox"
group and stacks all of its terminal and app windows in the top-left
quarter, alongside the design-system project on the right. Use the HUD
tab strip to change the visible member, or its grid button to fan out
the whole topic.

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
| `projects[].app`  | string?  | Application name (for non-terminal windows) |
| `projects[].title`| string?  | Window title substring to match          |
| `projects[].url`  | string?  | URL prefix to match (browser windows)    |
| `projects[].launch`| string? | Shell command to launch the app if not found |
| `projects[].tile` | string?  | Tile position (optional, see below)      |

Each project entry must have either `path`, `group`, or `app` — pick one.

### Tile values

Any tile position from the [config reference](/docs/config#tile-positions)
works: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`,
`bottom-left`, `bottom-right`, `left-third`, `center-third`,
`right-third`, `maximize`, `center`.

### Switching layers

Four ways to switch:

| Method               | How                                      |
|----------------------|------------------------------------------|
| **Hotkey**           | Cmd+Option+1, Cmd+Option+2, Cmd+Option+3... |
| **Layer bar**        | Click a layer pill in the menu bar panel |
| **Command palette**  | Search "Switch to Layer" in Cmd+Shift+M  |
| **CLI**              | `lattices layer <name\|index>`           |

When you switch to a layer:

1. Each project's window is **raised and focused**
2. App windows are matched by `app` / `title` / `url`
3. If a project isn't running yet, it gets **launched** automatically
4. Windows with a `tile` value are **tiled** to that position
5. The previous layer's windows stay open behind the new ones

The app remembers which layer was last active across restarts.

### Named layer switching

You can switch layers by name from the CLI:

```bash
lattices layer hudson     # Switch to the layer named "hudson"
lattices layer 0          # Switch to the first layer (by index)
```

This is useful for scripting — you don't need to know the index,
just the layer's `id` or `label`.

### Window tagging

You can manually assign any window to a layer, even if it's not
declared in `workspace.json`. This is useful for ad-hoc windows
that you want to move with a layer:

```bash
lattices window assign <wid> <layer>   # Tag a window to a layer
lattices window map                    # Show all window→layer assignments
```

Tagged windows behave like declared ones — they're raised and tiled
when their layer activates. Remove a tag by reassigning or with:

```bash
# Via the agent API
await daemonCall('window.removeLayer', { wid: 1234 })
```

### Layer bezel

When you switch layers via hotkey, a translucent HUD pill appears
briefly at the top of the screen showing the new layer's name.
This provides instant visual feedback without interrupting your flow.

### Programmatic switching

Agents and scripts can switch layers via the agent API:

```js
import { daemonCall } from '@lattices/cli'

// List available layers
const { layers, active } = await daemonCall('layers.list')
console.log(`Active: ${layers[active].label}`)

// Switch to a layer by index
await daemonCall('layer.switch', { index: 0 })

// Switch to a layer by name
await daemonCall('layer.switch', { name: 'hudson' })
```

The `layer.switch` call focuses and tiles all windows in the target
layer, just like the hotkey or command palette. A `layer.switched`
event is broadcast to all connected clients.

More methods in the [Agent API reference](/docs/api).

## Rule-backed Studio layers

Studio layers are live window rules stored in `~/.lattices/layers.json`.
They are separate from `workspace.json` launch-and-tile layers: Studio
layers do not launch projects. They resolve matching desktop windows,
then recall or scope those windows in Studio and Screen Map.

Each layer has a `match` array. A window joins the layer when it matches
any clause in that array. Inside one clause, every present positive field
must match, and every clause in `not` must fail.

```json
[
  {
    "id": "review",
    "name": "Review",
    "match": [
      {
        "appEquals": "Google Chrome",
        "titleRegex": "(GitHub|Pull Request)",
        "not": [
          { "titleContains": "Actions" }
        ]
      },
      {
        "sessionContains": "lattices",
        "isOnScreen": true
      }
    ]
  }
]
```

Supported clause fields:

| Field | Match |
|-------|-------|
| `app` | App name contains this string |
| `appEquals` | App name exactly equals this string |
| `appRegex` | App name matches this regular expression |
| `titleContains` | Window title contains this string |
| `titleEquals` | Window title exactly equals this string |
| `titleRegex` | Window title matches this regular expression |
| `session` | Parsed lattices tmux session exactly equals this string |
| `sessionContains` | Parsed lattices tmux session contains this string |
| `isOnScreen` | Window is, or is not, visible on the current Space |
| `spaceId` | Window belongs to this macOS Space id |
| `not` | Exclusion clauses; any match rejects the window |

`app` and `titleContains` are the original substring fields, so older
`layers.json` files continue to work. New layers created from plucked
windows use `appEquals` by default to avoid accidental substring matches.

### Layer bar

When a workspace config is loaded, a layer bar appears between the
header and search field in the menu bar panel:

```
 lattices  2 sessions              [↔] [⟳]
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
    { "path": "/Users/you/dev/vox" }
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

### Mixed: apps + terminals

```json
{
  "projects": [
    { "app": "Google Chrome", "title": "GitHub", "tile": "left" },
    { "path": "/Users/you/dev/api", "tile": "right" }
  ]
}
```

### Group + project

```json
{
  "projects": [
    { "group": "vox", "tile": "left" },
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

- Projects don't need a `.lattices.json` config to be in a layer — any
  directory path works. If the project has a config, lattices uses it; if
  not, it opens a plain terminal in that directory.
- App windows don't need any config at all — just specify `app` and
  optionally `title` or `url` to match the right window.
- You can have up to 9 layers (Cmd+Option+1 through Cmd+Option+9).
- Edit `workspace.json` by hand — the app re-reads it on launch. Use
  the Refresh Projects button or restart the app to pick up changes.
- The `tile` field is optional. Omit it if you just want the window
  focused without repositioning.
- Tab groups and standalone projects can coexist in the same workspace.
  Use groups for related project families, standalone paths for
  individual projects.
