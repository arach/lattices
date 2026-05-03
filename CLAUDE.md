# CLAUDE.md

## Project Overview

Lattices is a macOS developer workspace manager that pairs tmux sessions with a native menu bar app for tiling, navigation, and project management.

## Structure
- **CLI**: `bin/lattices.ts` (TypeScript, Bun/Node-compatible runtime) — main CLI entry point
- **App helper**: `bin/lattices-app.ts` — build/launch/quit/restart the menu bar app
- **Swift menu bar app**: `app/Sources/` — native macOS app (SwiftUI + AppKit)
- **Docs**: `docs/` — documentation source files

## Build Commands

### Swift App
```bash
cd app && swift build -c release
```

### CLI
```bash
bun bin/lattices.ts help
```

### App Lifecycle
```bash
bun bin/lattices-app.ts build    # Build the Swift app
bun bin/lattices-app.ts restart  # Quit + rebuild + relaunch
bun bin/lattices-app.ts quit     # Quit the running app
```

## Key Technical Details
- **Platform**: macOS 26.0+
- **Swift Version**: 5.9+
- **App Type**: Menu bar application (LSUIElement)
- **Config**: `~/.lattices/` for user config, `.lattices.json` per project
- **Bundle ID**: `com.arach.lattices`
- **tmux tags**: `[lattices:session-name]` in window titles

## Search Architecture

The CLI has a tiered search system for finding windows across the desktop:

### `lattices search <query>` — Index search
Calls the daemon's `windows.search` API. Searches window titles, app names, session tags, and OCR content. Fast — uses already-indexed data. Returns scored results (title/session: 3, app: 2, ocr: 1).

### `lattices search <query> --deep` — Deep search
Starts with index search, then **inspects** candidates live using terminal process data (`terminals.search`). Discovers windows the index missed (e.g. an iTerm window where 4/4 tabs have `~/dev/vox` in their cwd but "vox" doesn't appear in the window title). Each matching tab adds score weight, so terminal windows with many matching tabs rank highest.

### `lattices place <query> [position]` — Search + act
Runs deep search, takes the top result, focuses it by wid, and tiles it to a position. Default position: `bottom-right`.

### Daemon search APIs (used by the CLI)
- **`windows.search`** — title, app, session tag, OCR content. Returns window objects with `matchSource` and `ocrSnippet`.
- **`terminals.search`** — terminal tab/process data: cwd, tab titles, tmux sessions, running commands, hasClaude flag. Returns per-tab entries with `windowId`.
- **`ocr.search`** — FTS5 full-text search across all OCR history. Separate from `windows.search`.

### Search tips for agents
- Use `lattices search <query>` first. If the results are clear, act on them.
- Use `--deep` when looking for terminal windows by project name, since project names often only appear in cwd/tab data, not window titles.
- Use `--json` for programmatic consumption, `--wid` to pipe into other commands.
- `lattices call windows.search '{"query":"..."}' ` for raw API access.
