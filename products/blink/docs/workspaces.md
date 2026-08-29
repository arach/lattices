# Notes Workspaces — the agent-facing guide

> A **workspace** is a named group of notes plus the brand they render under.
> One command creates it, one command brands it, and the notes inside stay
> plain, portable Markdown. Companion to `cli.md` (the full CLI),
> `config.json` (`docs/config.md`), and `notes-representation.md` Appendix A.

## The one thing to understand

A workspace is two halves, kept deliberately apart:

| Half | Lives in | Holds |
|---|---|---|
| **Definition** | `config.json` → `workspaces.<name>` | title + brand (mark, palette, typography, corners) |
| **Membership** | each note's frontmatter → `blink.workspace` | one name. Nothing else. |

That split is the whole design. The brand is edited in exactly one place, and a
note carries a workspace *name* — never a color, a font, or an asset path. So a
branded note is still a boring `.md` file that works in Obsidian, git, or
`grep`, five years after Blink is uninstalled.

```markdown
---
id: q3-planning
created: 2026-07-25T22:39:44.042Z
updated: 2026-07-25T22:39:44.042Z
tags: []
pinned: false
blink:
  workspace: acme-docs
---
# Q3 Planning
```

That is the entire on-disk cost of belonging to a fully branded workspace.

## Quick start

```sh
blink workspace init "Acme Docs" --title "Acme Documentation"
blink new --workspace acme-docs "# Q3 Planning"
blink new --workspace acme-docs "# Onboarding"

blink workspace brand acme-docs \
  --background "#0b0d0c" --text "#f2f4ef" --accent "#7aa2f7" \
  --title-font "Inter, system-ui" --radius 6 \
  --install-mark ~/brand/acme.svg

blink workspace notes acme-docs      # what's in here
```

The running app picks all of it up live — it watches both the notes directory
and `config.json`, so a brand change re-themes open panels without a restart.

## Commands

```sh
blink workspace init <name> [--title T] [brand flags…]   # create (idempotent)
blink workspace ls                                       # list + note counts
blink workspace show <name>                              # definition + effective brand
blink workspace brand <name> [brand flags…]              # set/adjust the brand
blink workspace add <name> <id>…                         # put notes in it
blink workspace remove <id>…                             # take notes out
blink workspace notes <name>                             # list member notes
blink workspace rm <name> [--detach]                     # forget the definition
```

Plus membership on the note verbs you already use:

```sh
blink new --workspace <name> "# Title"
blink present <id> --workspace <name> [--style … --slot …]
```

Every command takes `--json`. Errors go to stderr with a non-zero exit code.

Names are normalized to slugs, so `"Acme Docs"` and `acme-docs` address the same
workspace and you can pass whichever you have.

## Defining a brand

A brand is a **treatment** — the same generic, reusable preset `styles` uses, so
there is one presentation vocabulary in Blink, not two. Every field is optional;
what you don't set is inherited.

| Group | Flags |
|---|---|
| Surface | `--sheet --background --radius --tint --tint-read --tint-edit` |
| Typography | `--font --mono --title-font --font-size --line-height` |
| Palette | `--text --text-strong --text-muted --dim --border --accent --accent-dim --code-background --code-text --caret --selection` |
| Identity | `--mark` (reference) · `--install-mark` (copy in) |
| Bulk | `--brand-from <file.json>` · `--style <name>` · `--clear <field>` |

`brand` is a partial overlay, so adjusting one color never restates the rest:

```sh
blink workspace brand acme-docs --accent "#9ece6a"     # only the accent moves
blink workspace brand acme-docs --clear mark           # back to inheriting
```

To define a whole brand in one call, hand it a JSON file:

```sh
cat > acme-brand.json <<'JSON'
{
  "background": "#0b0d0c",
  "text": "#f2f4ef",
  "accent": "#7aa2f7",
  "border": "rgba(239,244,237,.09)",
  "titleFont": "Inter, system-ui",
  "radius": 6
}
JSON
blink workspace brand acme-docs --brand-from acme-brand.json
```

### Sharing a house style

`--style <name>` names an entry in `config.json` → `styles` to use as the brand's
base, with the workspace's own brand overlaid on top. Several workspaces can
then share one house style and differ only where they mean to:

```sh
blink workspace brand acme-docs   --style terminal --accent "#7aa2f7"
blink workspace brand acme-alerts --style terminal --accent "#f7768e"
```

`blink workspace show <name> --json` reports both the stored `brand` and the
`effectiveBrand` (base + overlay, already composed) so an agent never has to
recompute the merge itself.

## Brand assets, safely

Blink renders marks **only** from inside `$BLINK_HOME/attachments`. That is a
containment boundary, not a convention: absolute paths, `../` traversal, and
symlinks pointing out of the directory are all refused, so a bad brand value
becomes an absent mark rather than an arbitrary file read.

Two ways to set one, and the first is the one to reach for:

```sh
# Install: copies the asset into attachments/marks/<workspace>.<ext> and
# records the relative path for you. Validates type and size (≤2 MB).
blink workspace brand acme-docs --install-mark ~/brand/acme.svg

# Reference: for an asset already inside the attachments directory.
blink workspace brand acme-docs --mark marks/acme.svg
```

Supported: `svg png jpg jpeg gif webp pdf tiff`. The mark renders at 20px in the
panel's top-left chrome and yields that spot to the close control on hover;
marked panels get a slightly wider content gutter so the identity never collides
with the first heading.

`show` tells you whether a mark actually resolves — a mark recorded but missing
from disk is flagged rather than silently ignored:

```sh
blink workspace show acme-docs --json | jq '.mark'
# { "path": "marks/acme.svg", "resolved": "/…/attachments/marks/acme.svg", "installed": true }
```

## How a note's look is decided

Least specific first, so **later wins**:

```
config defaults ← workspace brand ← blink.style ← loose blink: keys
```

A note inherits its workspace's identity for free; a per-note `style` still
overrides the brand; a loose `blink:` key beats both. The brand is a default,
never a cage.

```sh
blink present exception --workspace acme-docs --accent "#f7768e"
# ↑ Acme's brand, except this one note runs a red accent.
```

## Defaults and compatibility

- **Unbranded is the default.** A Blink with no workspaces behaves exactly as it
  did before this feature existed. A workspace with no brand is valid and
  renders with Blink's defaults.
- **Unknown names never fail.** A note pointing at a workspace or style that
  isn't defined renders unbranded — it always opens.
- **Existing notes and configs are untouched.** `blink.workspace` is a new,
  optional key in the `blink:` block; `workspaces` is a new, optional config key.
  Notes without them are unaffected, and `blink.style` keeps working exactly as
  before.
- **Your config is not rewritten.** `blink workspace` parses `config.json` as
  generic JSON, replaces only the `workspaces` key, and writes everything else
  back verbatim — including keys this build has never heard of. A config it
  cannot parse is refused, never overwritten.
- **Forgetting a workspace costs a look, never a note.** `blink workspace rm`
  removes the definition only; member notes keep their content and simply render
  unbranded. Add `--detach` to also clear membership from each member note.

## Durable group, live desktop

`blink workspace` manages *durable* state — the files and the config. The
running app owns the live plane: choose a workspace from the capture popover to
filter its log and canvas and recall only that workspace's already-open panels.
Panels in other workspaces are hidden, never closed, so their pending text,
exact frames, and session membership survive the switch. New notes inherit the
active named workspace; **All notes** and **Unfiled** create unfiled notes.

The file-backed `workspace` verbs do not mutate live panels. The `desk`
companion sends acknowledged open, move, focus, and close requests to the
running Blink instance with the same `BLINK_HOME`. An agent can inspect a group
and explicitly present the notes it wants on that live desktop:

```sh
blink workspace notes acme-docs --json \
  | jq -r '.[].id' \
  | while read -r id; do blink desk open "$id"; done
```
