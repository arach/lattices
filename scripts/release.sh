#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../app"

echo "Building release binary (arm64)..."
swift build -c release

BINARY=".build/release/LatticeApp"
DEST="../dist/LatticeApp-macos-arm64"

mkdir -p ../dist
cp "$BINARY" "$DEST"
chmod +x "$DEST"

echo ""
echo "Binary: $DEST"
ls -lh "$DEST"
file "$DEST"

VERSION=$(node -p "require('../package.json').version")
echo ""
echo "To release:"
echo "  gh release create v${VERSION} ${DEST} --title \"v${VERSION}\""
