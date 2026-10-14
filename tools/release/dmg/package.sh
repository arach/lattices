#!/bin/bash
set -euo pipefail

# Package an existing bundle, without rebuilding, signing, or launching it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUNDLE="${1:?Usage: package.sh /path/Lattices.app /path/output.dmg}"
OUTPUT="${2:?Specify an output DMG}"
[[ -d "$BUNDLE/Contents" ]] || { echo "Invalid app bundle: $BUNDLE" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "Install the packaging dependency: brew install create-dmg" >&2; exit 1; }
[[ ! -e "$OUTPUT" ]] || { echo "Output already exists: $OUTPUT" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/source" "$(dirname "$OUTPUT")"
ditto "$BUNDLE" "$WORK/source/Lattices.app"
swift "$SCRIPT_DIR/render-background.swift" "$WORK/background.png"
create-dmg \
    --volname "Lattices" \
    --volicon "$ROOT/assets/AppIcon.icns" \
    --background "$WORK/background.png" \
    --window-pos 240 160 \
    --window-size 680 520 \
    --icon-size 96 \
    --text-size 13 \
    --icon "Lattices.app" 190 235 \
    --hide-extension "Lattices.app" \
    --app-drop-link 490 235 \
    --no-internet-enable \
    "$OUTPUT" "$WORK/source"
