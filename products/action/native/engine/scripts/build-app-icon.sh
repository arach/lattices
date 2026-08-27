#!/bin/zsh
#
# Regenerates assets/brand/Action.icns from the mark geometry in
# CoreSources/ActionBrandMark.swift. Run this after changing the mark, then
# commit the result — build-app.sh copies the .icns, it does not build it, so
# an ordinary app build stays fast and offline.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
GEOMETRY="$ROOT_DIR/native/engine/CoreSources/ActionBrandMark.swift"
RENDERER="$SCRIPT_DIR/render-app-icon.swift"
BRAND_DIR="$ROOT_DIR/assets/brand"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$BRAND_DIR"

swiftc -O -parse-as-library \
  "$GEOMETRY" "$RENDERER" \
  -o "$WORK_DIR/render-app-icon" >&2

"$WORK_DIR/render-app-icon" "$WORK_DIR/Action.iconset" "$BRAND_DIR" >&2

iconutil --convert icns "$WORK_DIR/Action.iconset" --output "$BRAND_DIR/Action.icns"

printf '%s\n' "$BRAND_DIR/Action.icns"
