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
SIGN_IDENTITY="${LATTICES_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || echo "")}"
NOTARY_PROFILE="${LATTICES_NOTARY_PROFILE:-notarytool-art}"

if [ "$SKIP_SIGN" != "1" ]; then
    if [ -z "$SIGN_IDENTITY" ]; then
        echo "Error: No Developer ID signing identity found."
        echo "Set LATTICES_SIGN_IDENTITY or run with LATTICES_SKIP_SIGN=1 for a local smoke DMG."
        exit 1
    fi
    echo "    Sign identity: $SIGN_IDENTITY"
fi

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

TAP_SOUND="$APP_DIR/Resources/tap.wav"
if [ -f "$TAP_SOUND" ]; then
    cp "$TAP_SOUND" "$BUNDLE/Contents/Resources/tap.wav"
fi

PETS_DIR="$APP_DIR/Resources/Pets"
if [ -d "$PETS_DIR" ]; then
    cp -R "$PETS_DIR" "$BUNDLE/Contents/Resources/Pets"
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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.arach.lattices</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>lattices</string>
            </array>
        </dict>
    </array>
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
