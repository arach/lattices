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
- The split button arranges members inside the group's configured tile; press
  it again to collapse the windows back into their shared slot
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
Hyperspace, select two or more windows, then right-click any selected window
and choose **Create Tab Group from N Windows**. The same action appears when
you multi-select windows in the Hyper-3 sidebar and right-click. **⌘T** remains
the Hyperspace keyboard shortcut. Lattices immediately
stacks those existing terminal, browser, editor, or other app windows in
the top-left and shows their switcher in the HUD.

Use a tab button to bring that member forward. Use the split button to arrange
the members side by side inside the space reserved for the group, then press it
again to collapse back to the shared slot. Hyperspace shows active stacks in
the **Groupings** shelf at the bottom-right; Hyper-3 keeps the same groups in
its bottom-right Groupings strip. The pin button restores or hides
the movable floating tab tools; × on the floating tools hides them without
destroying the group. Ungroup is a separate minus action. Live stacks are
runtime-only; use the configured groups above when the group should return
after Lattices restarts.

The Workspace Assistant understands the same selection. With windows still
selected, say **“stack these as tabs”** or **“add these up.”** Agents can use
the `tabStacks.*` daemon methods described in the Agent API.

## Layers

Layers let you group projects into switchable contexts. Define up to
eight layers and switch between them. A switch puts away what the new
layer doesn't use, then brings its windows to the front and tiles them.
Layers work like virtual desktops, without macOS Spaces: see
[Putting windows away](#putting-windows-away).

All tmux sessions stay alive across switches. Nothing is detached,
killed or closed. Layers only control which windows are showing.

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

When this layer is launched, Lattices starts or focuses the "vox"
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
| `layers[].layout` | string?  | Lay the windows out: `auto`, `columns` or `master-stack` (see [Layouts](#layouts)) |
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

### Layouts

Instead of a `tile` per entry, a layer can lay its windows out itself:

```json
{
  "id": "web",
  "label": "Web",
  "layout": "auto",
  "projects": [
    { "app": "Ghostty", "title": "mini: web" },
    { "app": "Cursor", "title": "web" },
    { "app": "Google Chrome", "title": "localhost" }
  ]
}
```

| `layout`       | Arrangement |
|----------------|-------------|
| `auto`         | Lanes by app: terminals and chat on the left, editors and design tools in the middle, browsers and everything else on the right. On an ultrawide (21:9 or wider) each lane is a column, 30/40/30 with all three, and stacks its windows. On a standard display the editor, or else the first window, takes the left half and the rest stack on the right. |
| `columns`      | Equal columns in entry order, up to four on an ultrawide and three otherwise. The leftmost columns stack any extra windows. |
| `master-stack` | The first window takes the left 62%; the rest stack on the right. |

A lone window sits centred at half width on an ultrawide and fills a
standard display. More than three windows in a lane or column form a
grid two wide.

The layout applies on the main display, to the layer's windows on the
desktop it's showing, whenever you switch to the layer or choose it
again. Every window an entry matches takes part, frontmost first, and
the layer's first window ends up in front. Entries with their own
`tile` or `display` keep their place.

### Switching layers

Four ways to switch:

| Method               | How                                      |
|----------------------|------------------------------------------|
| **Hotkey**           | Cmd+Option+1–9 pick a slot of the [layer pad](#layer-bezel); Cmd+Option+5 shows the layer you're on; Cmd+Option+arrows move across the pad and stop at its edges |
| **Layer bar**        | Click a layer pill in the menu bar panel |
| **Command palette**  | Search "Switch to Layer" in Cmd+Shift+M  |
| **CLI**              | `lattices layer <name\|index>`           |

Every one of them switches the same way:

1. Everything the layer doesn't use is **put away** (see below)
2. The layer's windows are **raised**, matched by `app` / `title` / `url`
3. A layer with a `layout` **lays out** its windows

Choosing the layer you're on again gathers its windows back up.

Two extras go further, and are always asked for by name:

- **Tile** also moves windows with a `tile` value to that position:
  `lattices layer <name> --tile`, or `mode: "tile"` in the API.
- **Launch** first starts the projects that aren't running, then tiles:
  `lattices layer <name> --launch`, **Launch Layer** in the command
  bar, `l` in command mode, or `mode: "launch"`.

The app remembers which layer was last active across restarts.

### Putting windows away

A switch clears the main display before it raises the new layer:

- **Hidden apps.** An app with nothing in the new layer is hidden, as
  if you pressed ⌘H.
- **Parked windows.** The other windows of an app the layer does use
  (a second Ghostty or Chrome window, say) are parked: moved into the
  display's bottom-right corner, where macOS leaves a sliver showing.
  An app that also has windows on another display or desktop is parked
  rather than hidden, so those windows stay where they are.
  Some apps (TextEdit and other standard Cocoa windows) won't let a
  window go off-screen; theirs stay where they are and keep showing.
- **Scenes.** Each layer remembers what else it had showing, beyond its
  own entries, and brings it back when you return. A window you open
  while a layer is up comes back with that layer.

Only the main display and the desktop it's showing take part. Other
displays are left alone, and a switch never reaches onto another
desktop or takes you there: a layer window on another desktop stays
put. Re-tiling the active layer leaves the rest of the screen alone.
Everything happens at the switch; nothing runs in the background.

### Show All

Parked windows go back where they were when Lattices quits. Their
frames are saved in `~/.lattices/layer-stage.json`, so after a crash
the next launch puts them back. To bring everything back without
quitting:

| Where                | How                                           |
|----------------------|-----------------------------------------------|
| **Command bar**      | Show All Windows, listed with the layers while anything is put away |
| **Menu bar panel**   | Right-click a layer chip → Show All Windows   |
| **CLI**              | `lattices layer reveal` (or `show-all`)       |
| **API**              | `layers.reveal`                               |

Show All puts back every parked window and unhides every app a switch
hid. Apps you hid yourself stay hidden. A window parked on a desktop
that isn't showing can only move once that desktop is showing, so run
Show All again from there. It also brings back any window sitting in
the park corner that Lattices lost track of, centred on the main screen.

⌘\` can land on a parked window: in Ghostty, a parked terminal. It
stays in the corner until you switch layers or use Show All.

### Named layer switching

You can switch layers by name from the CLI:

```bash
lattices layer hudson           # Switch to the layer named "hudson"
lattices layer 0                # Switch to the first layer (by index)
lattices layer hudson --launch  # Start what isn't running, then tile
```

This is useful for scripting — you don't need to know the index,
just the layer's `id` or `label`.

### Adding and removing windows

Any window can join a layer without editing `workspace.json` by hand.
It's saved there as an entry of its app and its title, so it comes back
after a restart; while it lives, it stays in the layer when its title
changes.

```bash
lattices layer add wid:1234 --to web       # default: the active layer
lattices layer remove wid:1234 --from web
```

⌘⌥T adds the front window to the layer you're on. In the ⌘⌥Space
preview, a digit sends the picked window to the layer in that slot and
Delete takes it out. Hyperspace's layer piles and ⌘L write the same
layers. A window held by an entry that matches other windows too (a bare
app, a project) can't be taken out on its own; edit that entry instead.

### Layer bezel

When you switch layers, a 3×3 grid flashes in the upper middle of the
screen, numbered like Cmd+Option+1–9. Layers fill the eight slots round
the middle in order: 1, 2, 3, 4, then 6, 7, 8, 9, so a ninth layer has no
slot. The new layer's slot is lit, its name sits underneath, and slots
without a layer stay dim. The middle slot holds the Lattices pointer,
which turns to aim at the new layer's slot.

Under the name, the layer's apps are listed, one row each. A switch only
brings windows on the desktop the main display is showing, so an app
whose windows are elsewhere says where: Desktop 2, Left display, Full
screen. A running app without the layer's window says No window, and an
entry with nothing running says Not open.

Cmd+Option+arrows move to the nearest layer that way on the pad, hopping
the middle: from 4, right goes to 6. At the pad's edge, Cmd+Option+5 or
a slot without a layer, the grid shows the layer you're on.

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

The `layer.switch` call switches as ⌘⌥ does: it puts away what the
target layer doesn't use, brings its windows forward, and applies the
layer's `layout`. Entry `tile` placements need `mode: "tile"`, and
`mode: "launch"` also opens what isn't running. Its `index`
counts layers in list order from 0, not pad slots. A
`layer.switched` event is broadcast to all connected clients.
`layers.list` also reports what switches have put away, under `stage`,
and `layers.reveal` brings it all back.

More methods in the [Agent API reference](/docs/api).

## Entry rules

An entry finds its windows by `app` and `title`. For a sharper rule, give
it a `match` clause instead; the layer holds a window when any of its
entries matches it. Inside one clause, every field given must match, and
every clause in `not` must fail.

```json
{
  "id": "review",
  "label": "Review",
  "projects": [
    {
      "match": {
        "appEquals": "Google Chrome",
        "titleRegex": "(GitHub|Pull Request)",
        "not": [{ "titleContains": "Actions" }]
      }
    },
    { "match": { "sessionContains": "lattices" } }
  ]
}
```

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

Hyperspace's layer piles write these clauses; Screen Map scopes its canvas
to a layer's windows. `~/.lattices/layers.json`, the old Studio layer file,
is no longer read.

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
  Refresh Projects in the command bar, or restart the app, to pick up
  changes.
- The `tile` field is optional. Omit it if you just want the window
  focused without repositioning.
- Tab groups and standalone projects can coexist in the same workspace.
  Use groups for related project families, standalone paths for
  individual projects.
