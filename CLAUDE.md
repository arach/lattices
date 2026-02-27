# CLAUDE.md

## Project Overview

Lattice is a macOS developer workspace manager that pairs tmux sessions with a native menu bar app for tiling, navigation, and project management.

## Structure
- **CLI**: `bin/lattice.js` (Node.js ES modules) — main CLI entry point
- **App helper**: `bin/lattice-app.js` — build/launch/quit/restart the menu bar app
- **Swift menu bar app**: `app/Sources/` — native macOS app (SwiftUI + AppKit)
- **Docs**: `docs/` — documentation source files

## Build Commands

### Swift App
```bash
cd app && swift build -c release
```

### CLI
```bash
node bin/lattice.js help
```

### App Lifecycle
```bash
node bin/lattice-app.js build    # Build the Swift app
node bin/lattice-app.js restart  # Quit + rebuild + relaunch
node bin/lattice-app.js quit     # Quit the running app
```

## Key Technical Details
- **Platform**: macOS 13.0+
- **Swift Version**: 5.9+
- **App Type**: Menu bar application (LSUIElement)
- **Config**: `~/.lattice/` for user config, `.lattice.json` per project
- **Bundle ID**: `com.arach.lattice`
- **tmux tags**: `[lattice:session-name]` in window titles
