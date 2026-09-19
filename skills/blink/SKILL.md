---
name: blink
description: Drive Blink spatial notes on macOS. Use when creating, reading, searching, presenting, typing into, or placing floating notes through the blink CLI, or when the user asks for Blink, spatial notes, or a note on the desktop.
compatibility: Requires macOS. The blink CLI writes the same Markdown files Blink.app watches.
metadata:
  author: arach
  homepage: https://lattices.dev/blink
---

# Blink

Blink is spatial notes. Each note is a floating panel. The desktop is the
workspace. Agents drive it with the `blink` CLI, which writes the same
Markdown files the app watches.

When this skill is invoked, run the command. Summarize the result. Do not
narrate the plan first. Do not drive the Blink GUI unless the task needs the
live visual surface.

## Prerequisite

```bash
blink ls --json
```

If that fails, install the CLI and optionally the app:

```bash
npm install -g @arach/blink
blink app install
blink app open
```

Do not invent note ids. Read them from `blink ls --json` or `blink search`.
`blink new` and `blink present` print the id they created or used.

## Choose a verb

Prefer the CLI. The Markdown files are the durable store. The running app
reconciles disk and updates open panels.

| Need | Command |
| --- | --- |
| List notes | `blink ls --json` |
| Read a note | `blink cat <id>` |
| Search | `blink search "<query>" --json` |
| Create | `blink new "title"` or stdin into `blink new --json` |
| Content, look, and place | `blink present <id> "<markdown>" --style … --slot N` |
| Visible typed reveal | `blink type <id> "text"` |
| Quiet whole-body replace | `blink write <id> < file.md` |
| Append | `blink append <id> "text"` |
| Open or move a panel | `blink desk open <id>` / `blink desk move <id>` |
| Delete | `blink rm <id>` |

`present` is the usual write. It get-or-creates by id and changes only the
fields you pass. Omit the text to change presentation alone.

`type` and `append` reveal new text in an open panel. `write` replaces the
body with no animation. All three preserve presentation and unknown
frontmatter.

## Recipes

### Capture a note and place it

```bash
blink present q3-planning $'# Q3 planning\n\nThree bets, one page.' \
  --style focus --slot 6 --json
```

`--slot 1-9` is placement intent for the grid. The device-specific panel
frame is owned by Blink.app.

### Add a visible update

```bash
blink type q3-planning "Shipped the CLI verbs" --json
```

### File a note into a workspace

```bash
blink workspace init "Acme Docs"
blink new --workspace acme-docs "# Q3 Planning"
blink workspace notes acme-docs --json
```

A workspace brand lives in `config.json`. Membership is one
`blink.workspace` key on the note. Do not copy colors or fonts into the
Markdown.

### Open a panel on a display

```bash
blink desk screens --json
blink desk open q3-planning --display 1 --x 980 --y 90 --width 460 --height 260
blink desk focus q3-planning
```

`desk close` closes the panel and keeps the note.

## Paths and sandbox

Default notes directory:

`~/Library/Application Support/Blink/Notes/<id>.md`

Set `BLINK_HOME` to sandbox notes, config, and attachments. The Mac peer
host is disabled when `BLINK_HOME` is set.

`--writer` stamps `blink.lastWriter` and appends a ledger row. Omit it and
the CLI records `cli`. A ledger failure must not fail the save.

## Live docs

Do not copy the full CLI catalog into context. Read it when needed:

1. `blink --help`
2. https://lattices.dev/blink
3. `products/blink/docs/cli.md` in this repository
4. `products/blink/docs/workspaces.md` for workspace brand and membership
