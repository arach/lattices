#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$ROOT/app"
DIST_DIR="$ROOT/dist"
RELEASE_REPO="${LATTICES_RELEASE_REPO:-arach/lattices}"
RELEASE_TARGET="${LATTICES_RELEASE_TARGET:-main}"
VERSION="${LATTICES_VERSION:-$(node -p "require(process.argv[1]).version" "$ROOT/package.json" 2>/dev/null || echo '0.1.0')}"
TAG="v${VERSION}"
MODE="dmg"
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: ./tools/release/ship.sh [dmg|bin] [--dry-run]

Build the release asset and upload it to the public GitHub release feed.

Modes:
  dmg   Build/sign/notarize dist/Lattices.dmg and upload it (default)
  bin   Build dist/Lattices-macos-arm64 and upload it
EOF
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: Missing required command: $1" >&2
        exit 1
    fi
}

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY RUN:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

build_binary() {
    local binary asset
    binary="$APP_DIR/.build/release/Lattices"
    asset="$DIST_DIR/Lattices-macos-arm64"

    echo "==> Building release binary (arm64)..."
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY RUN: (cd %q && swift build -c release)\n' "$APP_DIR"
        printf 'DRY RUN: mkdir -p %q && cp %q %q && chmod +x %q\n' "$DIST_DIR" "$binary" "$asset" "$asset"
        return 0
    fi
    (
        cd "$APP_DIR"
        swift build -c release
    )

    mkdir -p "$DIST_DIR"
    cp "$binary" "$asset"
    chmod +x "$asset"
}

while [ $# -gt 0 ]; do
    case "$1" in
        dmg|bin|binary)
            MODE="$1"
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

need_cmd gh

cd "$ROOT"

case "$MODE" in
    dmg)
        ASSET_PATH="$DIST_DIR/Lattices.dmg"
        echo "==> Building DMG release asset..."
        run bash "$SCRIPT_DIR/build-dmg.sh" "$VERSION"
        ;;
    bin|binary)
        need_cmd swift
        ASSET_PATH="$DIST_DIR/Lattices-macos-arm64"
        build_binary
        ;;
esac

if [ "$DRY_RUN" -eq 0 ] && [ ! -f "$ASSET_PATH" ]; then
    echo "Error: Expected asset not found: $ASSET_PATH" >&2
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> DRY RUN: would create or update GitHub release $TAG in $RELEASE_REPO"
elif gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "==> Updating GitHub release $TAG in $RELEASE_REPO..."
    run gh release edit "$TAG" --repo "$RELEASE_REPO" --title "$TAG"
else
    echo "==> Creating GitHub release $TAG in $RELEASE_REPO..."
    run gh release create "$TAG" --repo "$RELEASE_REPO" --target "$RELEASE_TARGET" --title "$TAG" --notes ""
fi

echo "==> Uploading $(basename "$ASSET_PATH")..."
run gh release upload "$TAG" "$ASSET_PATH" --repo "$RELEASE_REPO" --clobber

echo ""
echo "==> Shipped $TAG with $(basename "$ASSET_PATH") to $RELEASE_REPO"
