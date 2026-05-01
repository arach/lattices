#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP_DIR="$ROOT/app"
BUILD_DIR="$ROOT/dist"
APP_NAME="Lattices.app"
DMG_NAME="Lattices.dmg"
BUNDLE="$BUILD_DIR/$APP_NAME"
VERSION="${1:-$(node -p "require(process.argv[1]).version" "$ROOT/package.json" 2>/dev/null || echo '0.1.0')}"

# Signing — override via environment or use defaults
SIGN_IDENTITY="${LATTICES_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || echo "")}"
TEAM_ID="${LATTICES_TEAM_ID:-}"
NOTARY_PROFILE="${LATTICES_NOTARY_PROFILE:-notarytool-art}"

if [ -z "$SIGN_IDENTITY" ]; then
    echo "Error: No Developer ID signing identity found."
    echo "Set LATTICES_SIGN_IDENTITY or install a Developer ID certificate."
    exit 1
fi
echo "    Sign identity: $SIGN_IDENTITY"

echo "==> Building Lattices v$VERSION (release)..."
cd "$APP_DIR"
swift build -c release 2>&1 | tail -3

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

# Info.plist — based on existing, with version injected
cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Lattices</string>
    <key>CFBundleDisplayName</key>
    <string>Lattices</string>
    <key>CFBundleIdentifier</key>
    <string>com.arach.lattices</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>Lattices</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
</dict>
</plist>
PLIST

echo "    App bundle created at $BUNDLE"

# ── Codesign ──────────────────────────────────────────────
echo "==> Signing..."

codesign --force --options runtime --timestamp \
    --entitlements "$APP_DIR/Lattices.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$BUNDLE"

echo "    Signed Lattices.app"

# Verify
codesign --verify --deep --strict --verbose=2 "$BUNDLE" 2>&1 | tail -3

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
codesign --force --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$BUILD_DIR/$DMG_NAME"

echo "    Signed Lattices.dmg"

# ── Notarize ──────────────────────────────────────────────
echo "==> Submitting for notarization..."
xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$BUILD_DIR/$DMG_NAME"

# ── Done ──────────────────────────────────────────────────
echo ""
echo "==> Done: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"
spctl --assess --type open --context context:primary-signature -v "$BUILD_DIR/$DMG_NAME" 2>&1 || true

echo ""
echo "To ship:"
echo "  ./scripts/ship.sh"
