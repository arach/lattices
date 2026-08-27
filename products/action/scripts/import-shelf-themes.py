#!/usr/bin/env python3
"""
Turn workspace palettes into Action themes.

Reads the theme shelf (`~/dev/themes/themes.json`, a scan of every project's own
palette source) and writes one Action theme file per entry that maps cleanly.

## What "maps cleanly" means

Action states every colour as a light/dark pair, so a shelf entry needs *both*
appearances with at least a ground and an ink. That is the whole admission
criterion, and it is why Talkie's seven and arach.dev's seven are not here:
each of those themes commits to one appearance, and synthesising the other side
would be inventing a palette and putting someone else's name on it.

## What is taken

Everything the palette states: the grounds, the ink ramp, the lines, the status
colours, and — this is the part worth explaining — **the accent**.

The first version of this script pinned every ported theme to Action's coral,
reasoning that coral means "this Mac is being driven right now" and a signal
should not move. That was a misreading of Action's own note, which says the
coral is identical *in light and dark* so a live drive reads the same in either
appearance. That invariant is about appearance, not about theme choice, and it
still holds: an accent here is one value used by both sides.

Pinning it across themes was wrong for a reason the numbers make plain. Coral
sits 15–19 ΔE from the failure red — perceptually the same colour. On Action's
warm paper the ground carries it and the eye reads brand warmth. Drop the same
coral on neutral charcoal and every accented thing on the screen reads as an
alarm. An accent is chosen *against* a ground; carrying one between grounds is
not a transplant, it is a mismatch.

So each theme keeps its own accent, and `ActionThemeValidator` now warns when a
theme accent is too close to its own failure colour.

Review is also left alone. It is deliberately a cool neutral sheet — warm paper
behind a screen recording fights the thing being reviewed — and that reasoning
does not stop being true because the rest of the app went warm.
"""

import argparse
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_SHELF = Path.home() / "dev" / "themes" / "themes.json"

# Shelf token -> Action surface slot. Only slots whose meaning genuinely matches;
# anything absent is left to Action's derivation rather than guessed at.
SLOTS = {
    "surface": "panel",
    "chrome": "band",
    "muted": "inkSecondary",
    "dim": "inkMeta",
    "border": "edge",
    "hairline": "rule",
}

STATUS = {"ok": "ok", "warn": "running", "error": "failed"}

# Families worth offering in Action. Scout and Linea are the two operator-tool
# palettes in the workspace with both appearances fully stated.
FAMILIES = {"Scout", "Linea"}


def duo(theme, token):
    """A light/dark pair for one shelf token, or None if either side is missing."""
    light = theme["modes"].get("light", {}).get(token)
    dark = theme["modes"].get("dark", {}).get(token)
    if not light or not dark:
        return None
    return light if light == dark else {"light": light, "dark": dark}


def convert(theme):
    ground = duo(theme, "bg")
    ink = duo(theme, "ink")
    if not ground or not ink:
        return None, "needs a ground and an ink in both appearances"

    # Scout states its accent on a separate axis rather than inside a preset,
    # and defaults that axis to the indigo — so that is what a Scout preset
    # lends, the same colour the app itself opens with.
    accent = duo(theme, "accent")
    if accent is None:
        axis = theme.get("extra", {}).get("accentAxis") or {}
        accent = axis.get("Indigo") or next(iter(axis.values()), None)
    if accent is None:
        return None, "has no accent, and inheriting Action's would collide with the failure red"

    tokens = {}
    for shelf_token, slot in SLOTS.items():
        value = duo(theme, shelf_token)
        if value:
            tokens[slot] = value

    seed = {"ground": ground, "ink": ink, "accent": accent}

    surface = {"seed": seed}
    if tokens:
        surface["tokens"] = tokens

    status = {}
    for shelf_token, slot in STATUS.items():
        value = duo(theme, shelf_token)
        if value:
            status[slot] = value

    # Chrome and field share the ground. In Action's own theme they already do —
    # the launcher canvas and Home's page are the same value — and a port that
    # only moved Home would leave most of what you actually look at unchanged.
    spec = {
        "id": theme["id"].replace(".", "-"),
        "name": theme["name"],
        "author": theme["project"],
        "summary": theme.get("blurb") or f"Ported from {theme['project']}.",
        "extends": "action",
        "surfaces": {"chrome": surface, "field": json.loads(json.dumps(surface))},
    }
    if status:
        spec["status"] = status
    return spec, None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shelf", type=Path, default=DEFAULT_SHELF)
    parser.add_argument("--out", type=Path, default=REPO / "themes")
    args = parser.parse_args()

    if not args.shelf.exists():
        raise SystemExit(f"no shelf at {args.shelf} — run its scan.py first")

    registry = json.loads(args.shelf.read_text())
    args.out.mkdir(parents=True, exist_ok=True)

    written, skipped = [], []
    for theme in registry["themes"]:
        if theme["family"] not in FAMILIES:
            continue
        spec, why = convert(theme)
        if spec is None:
            skipped.append((theme["id"], why))
            continue
        path = args.out / f"{spec['id']}.json"
        path.write_text(json.dumps(spec, indent=2) + "\n")
        written.append(spec["id"])

    for name in sorted(written):
        print(f"  wrote {name}.json")
    for name, why in skipped:
        print(f"  skipped {name}: {why}")
    print(f"{len(written)} themes → {args.out}")


if __name__ == "__main__":
    main()
