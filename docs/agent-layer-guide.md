# Agent Guide: Generating Layers

How to create and manage Lattices workspace layers programmatically. This guide is for AI agents (Claude Code, etc.) that want to generate layers from high-level user descriptions.

## Quick Reference

```bash
# See what's on screen
lattices windows --json

# Create a layer with tiling
lattices layer create "Design" --json '[
  {"app": "Figma", "tile": "left"},
  {"app": "Google Chrome", "title": "Tailwind", "tile": "right"}
]'

# Snapshot current windows as a layer
lattices layer snap "my-context"

# List / switch / delete session layers
lattices layer session
lattices layer session "Design"
lattices layer delete "Design"
lattices layer clear
```

## How It Works

There are two kinds of layers:

| Type | Storage | Requires restart? | How to create |
|------|---------|-------------------|---------------|
| **Config layers** | `~/.lattices/workspace.json` | Yes (or refresh) | Edit JSON file |
| **Session layers** | In-memory (daemon) | No | CLI or daemon API |

**Session layers are what you want.** They're created via TypeScript CLI commands, take effect immediately, and don't require restarting anything.

## Step-by-Step: Generating a Layer

### 1. Discover what's available

```bash
lattices windows --json
```

Returns an array of window objects:
```json
[
  {
    "wid": 1234,
    "app": "iTerm2",
    "title": "lattices — zsh",
    "latticesSession": "lattices-abc123",
    "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
    "spaceIds": [1]
  },
  {
    "wid": 5678,
    "app": "Google Chrome",
    "title": "GitHub - arach/lattices",
    "frame": { "x": 960, "y": 25, "w": 960, "h": 1050 },
    "spaceIds": [1]
  }
]
```

Key fields for matching:
- `wid` — unique window ID (most precise)
- `app` — application name
- `title` — window title (use for disambiguation when multiple windows of same app)
- `latticesSession` — tmux session name (for terminal windows)

### 2. Decide on a layout

Pick tile positions based on how many windows and what makes sense:

| Windows | Good layout | Tile values |
|---------|-------------|-------------|
| 2 | Side by side | `left`, `right` |
| 2 | Stacked | `top`, `bottom` |
| 3 | Main + sidebar | `left` (60%), `top-right`, `bottom-right` |
| 3 | Columns | `left-third`, `center-third`, `right-third` |
| 4 | Quadrants | `top-left`, `top-right`, `bottom-left`, `bottom-right` |
| 1 | Focused | `maximize` or `center` |

Full position reference:
- **Halves**: `left`, `right`, `top`, `bottom`
- **Quarters**: `top-left`, `top-right`, `bottom-left`, `bottom-right`
- **Thirds**: `left-third`, `center-third`, `right-third`
- **Sixths**: `top-left-third`, `top-center-third`, `top-right-third`, `bottom-left-third`, `bottom-center-third`, `bottom-right-third`
- **Fourths**: `first-fourth`, `second-fourth`, `third-fourth`, `last-fourth`
- **Special**: `maximize`, `center`
- **Custom grid**: `grid:CxR:C,R` (e.g. `grid:5x3:2,1`)

### 3. Create the layer

**Option A: By window ID (most reliable)**
```bash
lattices layer create "Coding" --json '[
  {"wid": 1234, "tile": "left"},
  {"wid": 5678, "tile": "right"}
]'
```

**Option B: By app name (survives window recreation)**
```bash
lattices layer create "Research" --json '[
  {"app": "Google Chrome", "title": "docs", "tile": "left"},
  {"app": "Notes", "tile": "right"}
]'
```

**Option C: Simple wid list (no tiling)**
```bash
lattices layer create "Focus" wid:1234 wid:5678
```

**Option D: Snapshot everything visible**
```bash
lattices layer snap "Current Context"
```

### 4. Switch between layers

```bash
lattices layer session          # list all session layers
lattices layer session "Coding" # switch to "Coding"
lattices layer session 0        # switch by index
```

## Daemon API (Advanced)

For finer control, use raw daemon calls:

```bash
# Create layer with window IDs
lattices call session.layers.create '{"name":"Coding","windowIds":[1234,5678]}'

# Create layer with app references
lattices call session.layers.create '{"name":"Design","windows":[{"app":"Figma"},{"app":"Google Chrome","contentHint":"Tailwind"}]}'

# Tile a specific window
lattices call window.place '{"wid":1234,"placement":"left"}'

# Switch layer
lattices call session.layers.switch '{"name":"Coding"}'

# List session layers
lattices call session.layers.list

# Delete
lattices call session.layers.delete '{"name":"old-layer"}'
```

## Composing Layers from Intent

When a user says something high-level, here's how to think about it:

### "Make me a coding layer"
1. Find terminal windows (iTerm2, Terminal, Warp, etc.)
2. Find browser windows with dev-related titles (GitHub, docs, localhost)
3. Main editor/terminal on `left`, reference material on `right`

### "Set up a design layer"
1. Find design tools (Figma, Sketch, Adobe XD)
2. Find browser windows with design references
3. Design tool `left` (or `maximize`), references `right`

### "Create a writing layer"
1. Find text editors, notes apps (Notes, Obsidian, iA Writer, VS Code with .md)
2. Find research/reference windows
3. Writing app `left` or `center`, references `right`

### "Give me a communication layer"
1. Find messaging apps (Slack, Discord, Messages)
2. Find email (Mail, Gmail in browser)
3. Arrange by priority — primary tool `left`, secondary `right`

### "Split my work into layers by project"
1. Group windows by project (match on title keywords, session names, or app)
2. Create one layer per project group
3. Use the 3-window layout pattern: main `left`, support `top-right`, `bottom-right`

## App Grouping Heuristics

When deciding which windows go together:

| Category | Common apps | Goes well with |
|----------|-------------|----------------|
| **Code** | iTerm2, Terminal, VS Code, Xcode | Chrome (docs/GitHub), Simulator |
| **Design** | Figma, Sketch, Pixelmator | Chrome (design systems), Preview |
| **Writing** | Notes, Obsidian, iA Writer | Chrome (research), Preview |
| **Communication** | Slack, Discord, Messages, Mail | Calendar, Notes |
| **Media** | Spotify, Music, Podcasts | (background, no tile needed) |
| **Reference** | Chrome, Safari, Preview, Finder | (depends on content) |

Browser windows are chameleons — use `title` matching to assign them to the right layer based on their content.

## Tips

- Prefer `wid` when the windows are already open — it's unambiguous.
- Use `app` + `title` when you want the layer to survive window restarts.
- Don't put more than 4-5 windows in a single layer — it gets cramped.
- Background apps (music, etc.) usually don't need to be in any layer.
- The `snap` command is great for "save what I have now" scenarios.
- Session layers are ephemeral — they live until the daemon restarts. For permanent layers, edit `~/.lattices/workspace.json`.
- You can create multiple layers in sequence, then switch between them with `lattices layer session <name>`.
