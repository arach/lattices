# Blink

Spatial note-taking for macOS: notes are first-class floating glass panels you
arrange on screen. Native Swift/AppKit bones on
[HudsonKit](https://github.com/arach/hudson), web editor surfaces
(CodeMirror 6) in WKWebViews. Triad-only: menubar popover · command palette ·
floating panels — no main window; the desktop is the workspace.

This is **v2**, a from-scratch native rewrite. The original Tauri + React app
remains available at the [`v1-final`](https://github.com/arach/blink/tree/v1-final)
tag.

## Build & run

```sh
swift build                 # app + CLI; requires a sibling ../hudson checkout
(cd web/editor && bun install && bun run build)   # editor bundle (once)
./scripts/run-app.sh --debug --restart            # assemble + launch dist/Blink.app
swift build --product blink                       # notes CLI; see docs/cli.md
swift test                                        # BlinkCore unit tests
```

Set `BLINK_HUDSON_SOURCE=git` to resolve HudsonKit from GitHub instead of the
sibling checkout.

## Layout

- `Sources/BlinkApp` — menubar app: AppDelegate, status item + popover,
  Carbon hotkeys (Hyper+N), AppModel, PanelManager, WebBridge, NotePanel
- `Sources/BlinkCore` — pure Swift: Note model, slug/UUIDv5 identity,
  frontmatter codec, atomic file store, NoteStore actor
- `Sources/BlinkCLI` — agent-friendly CLI over the same notes on disk
- `web/editor` — vanilla CodeMirror 6 bundle hosted by note panels
- `docs/` — [CLI](docs/cli.md) and [configuration](docs/config.md) reference
- `landing/` — marketing site (GitHub Pages deploys `landing/out`)

## Notes on disk

One markdown file per note in `~/Library/Application Support/Blink/Notes/`,
metadata in YAML frontmatter — local-first, human-readable, no side database.
All writes are atomic (temp + fsync + rename); saves flush on panel close and
app quit.

Blink's other agent-first surface is
[`config.json`](docs/config.md): behavior, hotkeys, panel appearance, and editor
theme are file-backed and hot-applied while the app is running.
