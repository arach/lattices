#!/bin/zsh
#
# Regenerates assets/AppIcon.icns and assets/AppIcon.svg with the site's brand
# exporter. The mark's source of truth is BlinkMark in
# apps/site/src/components/blink/BlinkMark.tsx, and the exporter renders the
# whole Blink kit from it. Run this after changing the mark, then commit the
# result — run-app.sh and the release build copy the .icns, they do not build
# it.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_DIR=$(cd "$ROOT_DIR/../.." && pwd)

# The exporter's dependencies (react-dom, sharp) resolve from apps/site.
(cd "$REPO_DIR/apps/site" && bun scripts/export-brand.tsx blink) >&2

printf '%s\n' "$ROOT_DIR/assets/AppIcon.icns"
