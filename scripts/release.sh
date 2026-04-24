#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP_DIR="$ROOT/app"
DIST_DIR="$ROOT/dist"
BINARY="$APP_DIR/.build/release/Lattices"
DEST="$DIST_DIR/Lattices-macos-arm64"
VERSION="$(node -p "require(process.argv[1]).version" "$ROOT/package.json" 2>/dev/null || echo '0.1.0')"

echo "Building release binary (arm64)..."
(
    cd "$APP_DIR"
    swift build -c release
)

mkdir -p "$DIST_DIR"
cp "$BINARY" "$DEST"
chmod +x "$DEST"

echo ""
echo "Binary: $DEST"
ls -lh "$DEST"
file "$DEST"

echo ""
echo "To ship:"
echo "  ./scripts/ship.sh bin"
