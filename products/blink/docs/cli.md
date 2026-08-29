# The `blink` CLI — agent surface, layer 2

A command-line face over the exact same files and codec the app uses. Writes
are atomic and slug-safe via BlinkCore. The running app picks every change up
**live**: it watches the Notes directory, reconciles disk against memory, and
routes the diff through
the same notifications in-app edits use. Create a note from a script and it's
in the popover a second later; edit an open note's file and the panel updates
in place (unless the user has unsaved edits in flight — then the user wins).

## Where it operates

```
$BLINK_HOME/Notes                                  # when BLINK_HOME is set
~/Library/Application Support/Blink/Notes          # default
```

`BLINK_HOME` is honored by the app and the CLI alike — set it to sandbox a
complete Blink (notes + config) for tests or experiments.

## Build / install

```sh
swift build -c release --product blink
cp .build/release/blink ~/bin/    # or anywhere on PATH
```

## Commands

Commands that expose structured output take `--json` where shown below. Errors
go to stderr with a nonzero exit code.

```sh
blink ls [--limit N] [--json]     # list notes, most recently updated first
blink cat <id> [--json]           # print content (exact bytes); --json adds all metadata
blink new [text ...] [--writer W] [--json]
blink present <id> [text ...] [--style … --slot … --writer W] [--json]
blink append <id> [text ...] [--writer W] [--json]
blink type <id> [text ...] [--writer W] [--json]
blink write <id> [text ...] [--writer W] [--json]
blink search <query> [--json]
blink rm <id> [--writer W] [--json]
blink log <id> [--limit N] [--json]   # append-only edit ledger
blink path [<id>]
blink workspace <subcommand>
blink desk <subcommand>
```

`workspace` is the grouping/branding verb set — see `docs/workspaces.md` for the
full guide:

```sh
blink workspace init <name> [--title T] [brand flags…]   # create (idempotent)
blink workspace ls                                       # list + note counts
blink workspace show <name>                              # definition + effective brand
blink workspace brand <name> [brand flags…]              # mark, palette, type, corners
blink workspace add <name> <id>…                         # put notes in it
blink workspace remove <id>…                             # take notes out
blink workspace notes <name>                             # list member notes
blink workspace rm <name> [--detach]                     # forget the definition
```

`new` and `present` also take `--workspace <name>` so a note can be filed on
creation. Membership is one `blink.workspace:` key in the note's frontmatter;
the brand itself lives in `config.json`, so note markdown stays portable and
free of presentation-only branding. In the running app, the capture popover's
workspace selector filters the log/canvas and recalls only that workspace's
open panels; notes created while a named workspace is active inherit it.

`present` is the compound arrival verb: it sets a note's markdown **and** its
`blink:` presentation (see `notes-representation.md`) in one write, get-or-create
by id. Only the fields you pass change; the rest are preserved. Its options mirror
the `blink:` keys: `--style --sheet --accent --font --font-size --line-height
--tint --tint-read --tint-edit --radius --slot`. `--slot 1–9` is placement intent
for the grid. Omit the text to change presentation alone.

`type` and `write` are the two ways to change a note's body, and they differ only
in *how the open panel reacts*: `type` appends an anchored suffix, so the running
app reveals it character by character (the visible hand); `write` replaces the
whole body, so the panel updates in place with no animation. `append` is the
established sibling of `type` (identical behavior). All three preserve presentation
and foreign frontmatter.

`--writer` stamps `blink.lastWriter` on the note and appends a row to
`$BLINK_HOME/edits.sqlite` (or the default Application Support ledger).
The markdown file stays truth: a ledger failure never fails the save.
Omit `--writer` and the CLI records `cli`. In-app edits record `user`.
`blink log` reads that sidecar even after `rm`; it is not a second note store.


`desk` is the intentionally small live counterpart to the file API. It asks the
running Blink app to realize an existing note as a panel while `PanelManager`
continues to own one-panel-per-note identity, focus, save flushing, and geometry
persistence. Coordinates are display-local AppKit points measured from the
visible top-left corner; omitted frame values preserve the current value.
`--display N` selects a one-based display (`1` is the main display); otherwise
the panel stays on its current display.

```sh
blink desk open standup --display 1 --x 980 --y 90 --width 460 --height 260
blink desk move standup --x 1130 --y 70     # visible lock-and-settle
blink desk focus standup
blink desk close standup                    # closes the panel, keeps the note
blink desk screens --json                   # responsive-script display geometry
```

Examples:

```sh
blink new "grocery run"                    # → grocery-run
printf '# Standup\n\n- ship CLI\n' | blink new --json
blink present q3-planning "# Q3 Planning" --style focus --slot 6   # content + look + place
blink present q3-planning --accent "#9ece6a"   # presentation-only; body untouched
blink append grocery-run "- oat milk"      # types on live if the panel is open
blink type standup "shipped the CLI verbs"     # same visible-hand reveal, phrasebook name
printf '%s\n' '- ship docs' | blink append standup --json
blink write standup < revised-standup.md       # replace the body, no animation
blink cat grocery-run
blink search standup --json | jq '.[0].id'
open "$(blink path grocery-run)"           # hand the file to anything

blink workspace init "Acme Docs"                     # a named, brandable group
blink new --workspace acme-docs "# Q3 Planning"      # file a note into it
blink workspace brand acme-docs --accent "#7aa2f7" --install-mark ~/acme.svg
blink workspace notes acme-docs --json | jq -r '.[].id'
```

## JSON shape

```jsonc
{
  "id": "standup",
  "title": "Standup",
  "tags": [],
  "pinned": false,
  "created": "2026-07-14T19:51:41.934Z",
  "updated": "2026-07-14T19:51:41.934Z",
  "path": "/Users/you/Library/Application Support/Blink/Notes/standup.md",
  "content": "…",             // cat/append --json only
  "extraFrontmatter": []        // cat/append --json only — foreign keys, preserved verbatim
}
```

## Or skip the CLI entirely

The filesystem is the API (layer 1): notes are frontmattered markdown, one
file per note. You may edit them with anything — Blink preserves frontmatter
keys it doesn't own and merges on-disk metadata before every save, so foreign
keys survive. The CLI just adds atomic writes, correct slug assignment, and
structured output for free. Prefer it for *creating* notes (slug uniqueness),
`append` when an agent should add a visible update without replacing the note,
and any scripted workflow. `append` always writes exactly one separating
newline before the supplied text; stdin bytes after that separator are kept as
provided.

Not here yet, by design: `blink link` waits for the `.blink/index.json`
backlink index; MCP waits until conversational, typed interaction is earned.
