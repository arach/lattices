#!/bin/bash
set -euo pipefail

# Action for Mac - DMG Build Script
# Builds a release Action.app, signs it with Developer ID, creates a Finder-style
# drag-to-Applications DMG, and notarizes it unless SKIP_NOTARIZE=1.
#
# Usage:
#   Installer/build.sh
#   Installer/build.sh --version 0.1.0 --build 12
#   SKIP_NOTARIZE=1 Installer/build.sh
#
# Environment variables:
#   VERSION=0.1.0
#   BUILD_NUMBER=12
#   ACTION_DEVELOPER_ID_APP="Developer ID Application: Name (TEAMID)"
#   ACTION_NOTARY_PROFILE=notarytool
#   SKIP_NOTARIZE=1
#   SKIP_DMG_LAYOUT=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$SCRIPT_DIR/resources"
STAGING_DIR="$SCRIPT_DIR/staging"
DMG_NAME="Action-for-Mac"
OUTPUT_DMG="$SCRIPT_DIR/$DMG_NAME.dmg"
TEMP_DMG="$SCRIPT_DIR/$DMG_NAME-temp.dmg"
MOUNT_DIR="/Volumes/$DMG_NAME"
BACKGROUND_SVG="$RESOURCES_DIR/dmg-background.svg"
BACKGROUND_PNG="$STAGING_DIR/dmg-background.png"

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
DEVELOPER_ID_APP="${ACTION_DEVELOPER_ID_APP:-Developer ID Application: Arach Tchoupani (2U83JFPW66)}"
SIGNING_IDENTITY=""
NOTARY_PROFILE="${ACTION_NOTARY_PROFILE:-notarytool}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_DMG_LAYOUT="${SKIP_DMG_LAYOUT:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(awk -F'"' '/"version"[[:space:]]*:/ {print $4; exit}' "$ROOT_DIR/package.json")"
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
fi

cleanup() {
  if mount | grep -q "on $MOUNT_DIR "; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  rm -f "$TEMP_DMG"
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

resolve_signing_identity() {
  local requested="$1"

  if [[ "$requested" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    echo "$requested"
    return
  fi

  security find-identity -v -p codesigning | awk -v name="\"$requested\"" 'index($0, name) {print $2; exit}'
}

render_background() {
  mkdir -p "$STAGING_DIR"

  if [[ ! -f "$BACKGROUND_SVG" ]]; then
    return 1
  fi

  sips -s format png "$BACKGROUND_SVG" --out "$BACKGROUND_PNG" >/dev/null
}

echo "======================================================"
echo "        Action for Mac - DMG Builder"
echo "        Version: $VERSION ($BUILD_NUMBER)"
echo "======================================================"
echo ""

require_tool security
require_tool codesign
require_tool hdiutil
require_tool xcrun
require_tool sips

echo "Verifying signing identity..."
SIGNING_IDENTITY="$(resolve_signing_identity "$DEVELOPER_ID_APP")"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Developer ID Application certificate not found:" >&2
  echo "  $DEVELOPER_ID_APP" >&2
  echo "" >&2
  echo "Set ACTION_DEVELOPER_ID_APP to the exact certificate name if needed." >&2
  exit 1
fi
echo "Signing identity verified: $SIGNING_IDENTITY"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "Checking notarization profile..."
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Notary profile is not available: $NOTARY_PROFILE" >&2
    echo "Create it with:" >&2
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id YOU@example.com --team-id TEAMID" >&2
    exit 1
  fi
  echo "Notarization profile verified"
fi

trap cleanup EXIT

echo ""
echo "Cleaning previous installer artifacts..."
rm -rf "$STAGING_DIR"
rm -f "$OUTPUT_DMG" "$TEMP_DMG"
mkdir -p "$STAGING_DIR/Applications"

echo ""
echo "Building release Action.app..."
APP_DIR="$(
  ACTION_BUILD_CONFIGURATION=release \
  ACTION_CODESIGN_IDENTITY="$SIGNING_IDENTITY" \
  ACTION_CODESIGN_HARDENED_RUNTIME=1 \
  ACTION_CODESIGN_TIMESTAMP=1 \
  ACTION_VERSION="$VERSION" \
  ACTION_BUILD_NUMBER="$BUILD_NUMBER" \
  "$ROOT_DIR/native/engine/scripts/build-app.sh"
)"

APP_STAGE="$STAGING_DIR/Applications/Action.app"
echo "Staging Action.app..."
ditto "$APP_DIR" "$APP_STAGE"

echo "Verifying staged app signature..."
codesign --verify --deep --strict "$APP_STAGE"

echo ""
echo "Creating DMG..."
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true

APP_SIZE_KB="$(du -sk "$APP_STAGE" | awk '{print $1}')"
DMG_SIZE_MB="$((APP_SIZE_KB / 1024 + 80))"
if [[ "$DMG_SIZE_MB" -lt 140 ]]; then
  DMG_SIZE_MB=140
fi

hdiutil create -size "${DMG_SIZE_MB}m" -fs HFS+ -volname "$DMG_NAME" "$TEMP_DMG" -ov -quiet
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -quiet

echo "Copying Action.app..."
ditto "$APP_STAGE" "$MOUNT_DIR/Action.app"

echo "Creating Applications alias..."
if ! osascript -e 'tell application "Finder" to make alias file to folder "Applications" of startup disk at POSIX file "'"$MOUNT_DIR"'"' >/dev/null 2>&1; then
  ln -s /Applications "$MOUNT_DIR/Applications"
fi

BACKGROUND_READY=0
if render_background; then
  mkdir -p "$MOUNT_DIR/.background"
  cp "$BACKGROUND_PNG" "$MOUNT_DIR/.background/background.png"
  BACKGROUND_READY=1
fi

if [[ "$SKIP_DMG_LAYOUT" != "1" ]]; then
  echo "Setting Finder layout..."
  if [[ "$BACKGROUND_READY" == "1" ]]; then
    osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Action-for-Mac"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 920, 460}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set background picture of theViewOptions to file ".background:background.png"
        set text size of theViewOptions to 10
        set label position of theViewOptions to right
        delay 1
        set position of item "Action.app" of container window to {145, 225}
        set position of item "Applications" of container window to {395, 225}
        update without registering applications
        delay 1
        close
        open
        delay 1
        close
    end tell
end tell
APPLESCRIPT
  else
    osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Action-for-Mac"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 920, 460}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set text size of theViewOptions to 10
        set label position of theViewOptions to right
        delay 1
        set position of item "Action.app" of container window to {145, 225}
        set position of item "Applications" of container window to {395, 225}
        update without registering applications
        delay 1
        close
        open
        delay 1
        close
    end tell
end tell
APPLESCRIPT
  fi
fi

sync
sleep 1
hdiutil detach "$MOUNT_DIR" -quiet

echo "Compressing DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" -ov -quiet
rm -f "$TEMP_DMG"

echo "Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$OUTPUT_DMG"
codesign --verify --verbose "$OUTPUT_DMG"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo ""
  echo "Skipping notarization because SKIP_NOTARIZE=1"
else
  echo ""
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$OUTPUT_DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$OUTPUT_DMG"
  xcrun stapler validate "$OUTPUT_DMG"

  RELEASE_DIR="$SCRIPT_DIR/releases/$VERSION"
  mkdir -p "$RELEASE_DIR"
  cp "$OUTPUT_DMG" "$RELEASE_DIR/"
fi

echo ""
echo "Verifying Gatekeeper assessment..."
if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  spctl --assess --type open --context context:primary-signature -vv "$OUTPUT_DMG" || true
else
  spctl --assess --type open --context context:primary-signature -vv "$OUTPUT_DMG"
fi

echo ""
echo "======================================================"
echo "        BUILD COMPLETE"
echo "======================================================"
ls -lh "$OUTPUT_DMG"
echo ""
echo "To test installation:"
echo "  open '$OUTPUT_DMG'"
