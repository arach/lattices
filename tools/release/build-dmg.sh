#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$ROOT/apps/mac"
BUILD_DIR="$ROOT/dist"
APP_NAME="Lattices.app"
DMG_NAME="Lattices.dmg"
BUNDLE="$BUILD_DIR/$APP_NAME"
VERSION="${1:-$(node -p "require(process.argv[1]).version" "$ROOT/package.json" 2>/dev/null || echo '0.1.0')}"

SKIP_SIGN="${LATTICES_SKIP_SIGN:-0}"
SKIP_NOTARIZE="${LATTICES_SKIP_NOTARIZE:-0}"
NOTARY_PROFILE="${LATTICES_NOTARY_PROFILE:-notarytool-art}"

default_sign_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*\([A-F0-9]\{40\}\)[[:space:]]*"Developer ID Application:[^"]*".*/\1/p' \
        | head -n 1
}

SIGN_IDENTITY="${LATTICES_SIGN_IDENTITY:-$(default_sign_identity || true)}"

if [ "$SKIP_SIGN" != "1" ]; then
    if [ -z "$SIGN_IDENTITY" ]; then
        echo "Error: No Developer ID signing identity found."
        echo "Set LATTICES_SIGN_IDENTITY or run with LATTICES_SKIP_SIGN=1 for a local smoke DMG."
        exit 1
    fi
    echo "    Sign identity: $SIGN_IDENTITY"
fi

echo "==> Building Lattices v$VERSION (release)..."
# Resolve the same declarative feature flags used by the dev and package
# builders. In particular, this enables Hudson Voice when apps/mac/build.json
# declares the voice feature.
eval "$(bun "$ROOT/bin/lattices-build-env.ts" shell)"
cd "$APP_DIR"
# Stream the full build (tee) so CI surfaces real compiler errors; on failure,
# re-print just the error: lines for a quick scan. (Previously `| tail -3`
# swallowed the actual diagnostics, leaving only doc-link footers.)
build_log="$(mktemp)"
if ! swift build -c release 2>&1 | tee "$build_log"; then
    echo "==> Swift build FAILED. Compiler errors:" >&2
    grep -E "error:" "$build_log" >&2 || true
    rm -f "$build_log"
    exit 1
fi
rm -f "$build_log"

echo "==> Creating app bundle..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# Copy binary
cp "$APP_DIR/.build/release/Lattices" "$BUNDLE/Contents/MacOS/Lattices"

# Copy app icon
ICON="$ROOT/assets/AppIcon.icns"
if [ -f "$ICON" ]; then
    cp "$ICON" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

TAP_SOUND="$APP_DIR/Resources/tap.wav"
if [ -f "$TAP_SOUND" ]; then
    cp "$TAP_SOUND" "$BUNDLE/Contents/Resources/tap.wav"
fi

PETS_DIR="$APP_DIR/Resources/Pets"
if [ -d "$PETS_DIR" ]; then
    cp -R "$PETS_DIR" "$BUNDLE/Contents/Resources/Pets"
fi

DECK_BUILDER_RESOURCES="$APP_DIR/Resources/DeckBuilder"
if [ -d "$DECK_BUILDER_RESOURCES" ]; then
    cp -R "$DECK_BUILDER_RESOURCES" "$BUNDLE/Contents/Resources/DeckBuilder"
fi

# Keep privacy and transport declarations in one canonical plist, then inject
# the requested release version. This prevents release-only drift from the dev
# bundle (for example a missing microphone usage description).
cp "$APP_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUNDLE/Contents/Info.plist"

ASSISTANT_KNOWLEDGE="$ROOT/docs/assistant-knowledge.md"
if [ -f "$ASSISTANT_KNOWLEDGE" ]; then
    mkdir -p "$BUNDLE/Contents/Resources/docs"
    cp "$ASSISTANT_KNOWLEDGE" "$BUNDLE/Contents/Resources/docs/assistant-knowledge.md"
fi

echo "    App bundle created at $BUNDLE"

# ── Codesign ──────────────────────────────────────────────
if [ "$SKIP_SIGN" = "1" ]; then
    echo "==> Skipping signing because LATTICES_SKIP_SIGN=1"
else
    echo "==> Signing..."

    codesign --force --options runtime --timestamp \
        --entitlements "$APP_DIR/Lattices.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$BUNDLE"

    echo "    Signed Lattices.app"

    # Verify
    codesign --verify --deep --strict --verbose=2 "$BUNDLE" 2>&1 | tail -3
fi

# ── Create DMG ────────────────────────────────────────────
echo "==> Creating DMG..."
DMG_STAGING=$(mktemp -d)
cp -R "$BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "Lattices" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

rm -rf "$DMG_STAGING"

# Sign the DMG itself
if [ "$SKIP_SIGN" = "1" ]; then
    echo "==> Skipping DMG signing because LATTICES_SKIP_SIGN=1"
else
    codesign --force --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$BUILD_DIR/$DMG_NAME"

    echo "    Signed Lattices.dmg"
fi

# ── Notarize ──────────────────────────────────────────────
if [ "$SKIP_NOTARIZE" = "1" ] || [ "$SKIP_SIGN" = "1" ]; then
    echo "==> Skipping notarization"
else
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
fi

# ── Done ──────────────────────────────────────────────────
echo ""
echo "==> Done: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"
if [ "$SKIP_SIGN" != "1" ]; then
    spctl --assess --type open --context context:primary-signature -v "$BUILD_DIR/$DMG_NAME" 2>&1 || true
fi

echo ""
echo "To ship:"
echo "  ./tools/release/ship.sh"
