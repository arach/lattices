#!/usr/bin/env bash
# Lattices release build helper.
#
# Dev build/run is intentionally in ./scripts/run.sh, matching the Talkie split.
# This script is for package/release artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
Lattices build helper

Usage:
  ./scripts/build.sh                 Build signed + notarized release DMG
  ./scripts/build.sh --local         Build local signed DMG, skip notarization
  ./scripts/build.sh package         Build the npm/package app bundle
  ./scripts/build.sh where           Show canonical app paths and bundle ids

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
        "$ROOT/bin/lattices-build" dist:local "$@"
        ;;
    dist)
        shift || true
        "$ROOT/bin/lattices-build" dist "$@"
        ;;
    *)
        "$ROOT/bin/lattices-build" "$@"
        ;;
esac
