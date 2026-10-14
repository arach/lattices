#!/bin/zsh
#
# Regenerates assets/brand/Action.icns, and the 512 and 1024 px PNGs beside
# it, with the site's brand exporter. The mark's source of truth is ActionMark
# in apps/site/src/components/ActionMark.tsx, and the exporter renders the
# whole Action kit from it. Run this after changing the mark, then commit the
# result — build-app.sh copies the .icns, it does not build it, so an ordinary
# app build stays fast and offline.
#
# CoreSources/ActionBrandMark.swift ports the same geometry for the menu bar
# and the in-app chip. It does not draw the icon, so keep its numbers in step
# with the component by hand.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
REPO_DIR=$(cd "$ROOT_DIR/../.." && pwd)

# The exporter's dependencies (react-dom, sharp) resolve from apps/site.
(cd "$REPO_DIR/apps/site" && bun scripts/export-brand.tsx action) >&2

printf '%s\n' "$ROOT_DIR/assets/brand/Action.icns"
