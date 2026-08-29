<div align="center">

# Blink

### Put notes where your work is.

Native floating notes for macOS, with an agent-first CLI over the same local Markdown files.

[![npm](https://img.shields.io/npm/v/%40arach%2Fblink?style=flat-square&color=38bdf8&label=npm)](https://www.npmjs.com/package/@arach/blink)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple&logoColor=white)](https://blink.arach.dev)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-native-111827?style=flat-square)](https://github.com/arach/blink/releases)
[![MIT](https://img.shields.io/badge/license-MIT-111827?style=flat-square)](https://github.com/arach/blink/blob/main/LICENSE)

</div>

<p align="center">
  <a href="https://blink.arach.dev">
    <img src="https://raw.githubusercontent.com/arach/blink/main/landing/public/hero-desk.png" width="900" alt="A borderless Blink note floating over the macOS desktop" />
  </a>
</p>

<p align="center"><sub>A real Blink note on the desktop: native dark glass, edge-to-edge Markdown, exactly where you left it.</sub></p>

## Zero to a spatial note

```sh
npm install -g @arach/blink  # install the CLI + app installer command
blink app install            # fetch + install Blink.app in /Applications
blink app open               # launch the installed menubar app

# Create content, presentation, and placement in one atomic write.
blink present q3-plan $'# Q3 plan\n\nShip something people love.' \
  --slot 6 --accent '#7dd3fc'
```

The note is immediately available to Blink. If the app is open, it appears and
updates live; otherwise it is waiting in the same place the next time Blink
launches.

## Why Blink

| Principle | What it means |
|---|---|
| **Spatial by default** | Notes are borderless floating panels with per-note position, size, style, and grid placement. |
| **Made for agents** | Predictable verbs, JSON output, stdin support, and one command for content + presentation + placement. |
| **Local-first** | One human-readable Markdown file per note. No side database and no cloud account. |
| **Native where it counts** | Swift/AppKit panels, signed native CLI, global hotkeys, and a tiny Node shim for npm. |

## Two commands. One workspace.

### `blink` — write from anywhere

```sh
blink ls                                         # recent notes
blink new "grocery run"                          # create
blink cat q3-plan                                # read clean Markdown
blink search "launch"                            # search titles + content
blink present q3-plan "# Q3" --style focus       # content + look
blink type q3-plan "One more thing…"              # visible typed reveal
blink write q3-plan < revised.md                  # quiet replacement
blink rm grocery-run                             # delete
```

Every mutation uses Blink's atomic file store. The running app reconciles
external writes and reflects them across the menubar, palette, and open panels.

### `blink app` — manage the macOS app

```sh
blink app install   # fetch, validate, and install/reinstall the newest Blink 2
blink app update    # explicitly refresh the installed app
blink app open      # launch the installed menubar app
blink app path      # print /Applications/Blink.app
```

The shorter `blink-app` command remains available as a compatibility alias.
Both paths accept only a signed Blink 2 DMG, validate its bundle identity, stage
the replacement in `/Applications`, and preserve the previous app if the swap
fails.

## An API made of files

```text
you or your agent
       │
       ▼
  blink present ──────► ~/Library/Application Support/Blink/Notes/q3-plan.md
                                      │
                                      ▼ live reconcile
                          menubar · palette · floating panel
```

Notes carry their own metadata in YAML frontmatter, so presentation travels
with the content:

```md
---
id: q3-plan
blink:
  style: focus
  accent: "#7dd3fc"
  slot: 6
---
# Q3 plan

Ship something people love.
```

Set `BLINK_HOME` to isolate a workspace for testing or automation. Add `--json`
when another program needs structured output.

## Small package. Native core.

- **Zero runtime dependencies** and **no install lifecycle scripts**.
- The signed arm64 Swift CLI ships inside the tarball—there is no binary fetch
  when you run `blink`.
- The macOS app is distributed separately as a signed and notarized DMG.
- Requires macOS 14+, Apple Silicon, and Node.js 18+ for the npm shims.

---

<p align="center">
  <a href="https://blink.arach.dev">Website</a> ·
  <a href="https://github.com/arach/blink/blob/main/docs/cli.md">CLI reference</a> ·
  <a href="https://github.com/arach/blink/blob/main/docs/config.md">Configuration</a> ·
  <a href="https://github.com/arach/blink/releases">Releases</a> ·
  <a href="https://github.com/arach/blink/issues">Issues</a>
</p>

<p align="center"><sub>macOS spatial notes for humans and the agents working beside them.</sub></p>
