#!/usr/bin/env bash
# Lattices release build helper.
#
# Dev build/run is intentionally in ./run.sh, matching the Talkie split.
# This script is for package/release artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    cat <<'EOF'
Lattices build helper

Usage:
  ./build.sh                 Build signed + notarized release DMG
  ./build.sh --local         Build local signed DMG, skip notarization
  ./build.sh package         Build the npm/package app bundle
  ./build.sh where           Show canonical app paths and bundle ids

Canonical app identities:
  dev      ~/Applications/dev/Lattices/Lattices.app  dev.lattices.app.dev
  release  /Applications/Lattices.app                dev.lattices.app
EOF
}

cmd="${1:-dist}"

case "$cmd" in
    -h|--help|help)
        usage
        ;;
    --local|local|dist:local)
        shift || true
        "$SCRIPT_DIR/bin/lattices-build" dist:local "$@"
        ;;
    dist)
        shift || true
        "$SCRIPT_DIR/bin/lattices-build" dist "$@"
        ;;
    *)
        "$SCRIPT_DIR/bin/lattices-build" "$@"
        ;;
esac
