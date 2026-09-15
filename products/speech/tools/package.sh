#!/bin/bash
# Build a local artifact only. Never install, launch or publish it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${SPEECH_BUILD_CONFIGURATION:-release}"
OUTPUT="${SPEECH_ARTIFACT_DIR:-$ROOT/.artifacts}"
IDENTITY="${SPEECH_SIGN_IDENTITY:--}"
swift build --package-path "$ROOT" -c "$CONFIG"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"
mkdir -p "$OUTPUT"
STAGE="$(mktemp -d "$OUTPUT/.speech-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Speech.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Speech" "$APP/Contents/MacOS/Speech"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
# Vox SpeechEngineResources resolves packaged resources from Contents/Resources.
for RESOURCE in "$BIN_DIR"/*.bundle; do
    [ -d "$RESOURCE" ] || continue
    cp -R "$RESOURCE" "$APP/Contents/Resources/"
done
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
if [ "${SPEECH_DISTRIBUTABLE:-0}" = "1" ]; then
    bash "$ROOT/../../tools/release/verify-companion-signature.sh" "$APP"
fi
DEST="$OUTPUT/Speech.app"
if [ -e "$DEST" ]; then echo "Artifact already exists: $DEST" >&2; exit 1; fi
mv "$APP" "$DEST"
if [ "${SPEECH_CREATE_DMG:-0}" = "1" ]; then
    hdiutil create -volname Speech -srcfolder "$DEST" -ov -format UDZO "$OUTPUT/Speech.dmg"
fi
printf 'Built %s\n' "$DEST"
