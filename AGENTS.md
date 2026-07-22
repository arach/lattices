# lattices

> macOS developer workspace manager — tmux sessions with a native Swift menu bar app for tiling, navigation, and project management

## Critical Context

**IMPORTANT:** Read these rules before making any changes:

- lattices has TWO primary interfaces: a TypeScript CLI (`bin/lattices.ts`) and a native Swift menu bar app (`apps/mac/Sources/`)
- Session names are `<basename>-<sha256-6chars>` — both CLI (Node `crypto`) and app (Swift `CryptoKit`) must produce identical hashes
- The app finds terminal windows via a `[lattices:session-name]` tag embedded in the tmux window title (`set-titles-string`)
- Window navigation falls through CG → AX → AppleScript depending on macOS permissions
- Space switching uses private SkyLight framework APIs loaded via dlopen at runtime
- The daemon runs on ws://127.0.0.1:9399 with 35+ RPC methods and real-time events (localhost only, no auth by design)
- Bare `lattices` (no args) shows a home/status screen — use `lattices start` (alias: `lattices tmux`) to create or attach a session
- `lattices search <q> --deep` and `--all` both request all search sources (index + live terminal inspection)

## Project Structure

| Component | Path | Purpose |
|-----------|------|---------|
| CLI | `bin/lattices.ts` | Published command-line workspace manager |
| App Helper | `bin/lattices-app.ts` | Build, launch, quit, and restart the app |
| Build script | `bin/lattices-build` | App bundle / DMG packaging (wrapped by `scripts/build.sh`) |
| Menu Bar App | `apps/mac/Sources/` | SwiftUI/AppKit app + daemon (`apps/mac/Package.swift`) |
| Swift packages | `swift/` | LatticesTerminalKit + DeckKit (`swift/Package.swift`) |
| Tests | `tests/` | CLI (node:test), dependency-free (bun test), e2e daemon |
| Docs | `docs/` | User + agent documentation |
| Site | `apps/site/` | Vite website, docs, and blog |

## Commands

Package manager is **bun** (Node 18+ also works for the CLI entry points).

```bash
bun link                        # Install CLI locally for development
bun run check                   # TypeScript typecheck + Swift app build
bun run check:types             # tsc --noEmit
bun run check:app               # swift build --package-path apps/mac
bun run test                    # CLI tests + dependency-free tests
bun run test:cli                # node --experimental-strip-types --test tests/cli.test.mjs
bun run test:e2e                # daemon e2e tests (requires running app/daemon)
bun run test:dependencies       # bun test tests/dependency-free.test.ts
swift build --package-path swift   # Swift packages (LatticesTerminalKit, DeckKit)
swift test --package-path swift    # Swift package tests
lattices app build              # Rebuild the menu bar app from source
scripts/build.sh                # Signed + notarized release DMG (--local to skip notarization)
scripts/build.sh package        # npm/package app bundle
```

## Quick Navigation

- Working with **cli**? → Check bin/lattices.ts for CLI commands and session logic
- Working with **app**? → Check apps/mac/Sources/ for Swift menu bar app code
- Working with **config**? → Check docs/config.md for .lattices.json format and CLI reference
- Working with **tiling**? → Check apps/mac/Sources/Core/Desktop/WindowTiler.swift and apps/mac/Sources/Core/Desktop/PlacementSpec.swift
- Working with **palette**? → Check apps/mac/Sources/Core/Actions/PaletteCommand.swift for command palette actions
- Working with **terminal**? → Check apps/mac/Sources/Core/Workspace/Terminal/Terminal.swift for supported terminals and launch logic
- Working with **daemon**? → Check apps/mac/Sources/Core/Daemon/DaemonServer.swift and apps/mac/Sources/Core/Daemon/LatticesApi.swift for WebSocket API
- Working with **api**? → Check docs/api.md for the daemon RPC reference
- Working with **agent docs**? → Check docs/agents.md and apps/site/scripts/agent-docs.mjs for raw markdown, prompt, and context artifacts

## Documentation

Full documentation lives in `docs/` — read these before changing behavior:

- `docs/quickstart.md` — install and first session
- `docs/concepts.md` — architecture, glossary, session naming, ensure/prefill
- `docs/config.md` — `.lattices.json` format, CLI command reference, tile positions
- `docs/app.md` — menu bar app: command palette, tiling, settings, supported terminals
- `docs/layers.md` — workspace layers and tab groups (`~/.lattices/workspace.json`)
- `docs/api.md` — daemon RPC methods, events, wire protocol, agent integration patterns
- `docs/agents.md` — agent-facing documentation and context artifacts
