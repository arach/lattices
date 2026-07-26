#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/LatticesCompanion.xcodeproj"
SCHEME="LatticesCompanion"
BUNDLE_ID="com.arach.lattices.companion.ios"
CONFIGURATION="${LATS_SCREENSHOT_CONFIGURATION:-Debug}"
OUTPUT_ROOT="${LATS_SCREENSHOT_OUTPUT_DIR:-$ROOT/.artifacts/app-store-screenshots}"
RAW_DIR="$OUTPUT_ROOT/raw-ipad"
MARKETING_DIR="$ROOT/marketing/app-store/ipad-pro-129"
SIM_NAME="${LATS_SCREENSHOT_SIM_NAME:-Lats Deck App Store iPad}"
DEVICE_TYPE="${LATS_SCREENSHOT_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB}"
RUNTIME_ID="${LATS_SCREENSHOT_RUNTIME:-}"
ASC_BIN="${LATS_ASC_BIN:-asc}"

mkdir -p "$HOME/Library/Caches/codex-builds"
if [[ -n "${LATS_SCREENSHOT_DERIVED_DATA:-}" ]]; then
  DERIVED_DATA="$LATS_SCREENSHOT_DERIVED_DATA"
  CLEAN_DERIVED_DATA=0
else
  DERIVED_DATA="$(mktemp -d "$HOME/Library/Caches/codex-builds/lats-ios-screenshots.XXXXXXXX")"
  CLEAN_DERIVED_DATA=1
fi

cleanup() {
  if [[ "$CLEAN_DERIVED_DATA" == "1" ]]; then
    rm -rf "$DERIVED_DATA"
  fi
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_runtime() {
  if [[ -n "$RUNTIME_ID" ]]; then
    echo "$RUNTIME_ID"
    return
  fi

  xcrun simctl list runtimes available | awk '
    /iOS / {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/) print $i
      }
    }
  ' | sort -V | tail -n 1
}

ensure_simulator() {
  local existing
  existing="$(xcrun simctl list devices available | awk -v name="$SIM_NAME" '
    index($0, name " (") {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^\([0-9A-Fa-f-]+\)$/) {
          gsub(/[()]/, "", $i)
          print $i
          exit
        }
      }
    }
  ')"

  if [[ -n "$existing" ]]; then
    echo "$existing"
  else
    xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID"
  fi
}

capture() {
  local scene="$1"
  local filename="$2"
  shift 2

  xcrun simctl launch --terminate-running-process "$SIM_UDID" "$BUNDLE_ID" \
    -AppleLanguages '(en-US)' \
    -AppleLocale en_US \
    "$@" >/dev/null
  sleep 2
  xcrun simctl io "$SIM_UDID" screenshot "$RAW_DIR/$filename" >/dev/null
}

require_cmd xcodegen
require_cmd xcodebuild
require_cmd xcrun
require_cmd python3
require_cmd "$ASC_BIN"

RUNTIME_ID="$(resolve_runtime)"
if [[ -z "$RUNTIME_ID" ]]; then
  echo "No available iOS Simulator runtime found" >&2
  exit 1
fi

mkdir -p "$RAW_DIR" "$MARKETING_DIR"
rm -f "$RAW_DIR"/*.png "$MARKETING_DIR"/*.png

echo "Generating the Xcode project"
xcodegen generate --spec "$ROOT/project.yml"

echo "Building Lats Deck for iPad Simulator"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_DATA" \
  SDKROOT=iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/LatticesCompanion.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build output not found at $APP_PATH" >&2
  exit 1
fi

SIM_UDID="$(ensure_simulator)"
xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_UDID" -b
xcrun simctl ui "$SIM_UDID" appearance dark >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIM_UDID" "$APP_PATH"

echo "Capturing deterministic product scenes"
capture home 01-home.png --app-store-home
capture command 02-command.png --app-store-deck=command
capture windows 03-windows.png --app-store-deck=windows
capture dev 04-dev.png --app-store-deck=dev
capture voice 05-voice.png --app-store-deck=voice

echo "Rendering App Store creative"
python3 "$ROOT/marketing/app-store/render.py"

echo "Validating App Store dimensions"
"$ASC_BIN" screenshots validate \
  --path "$MARKETING_DIR" \
  --device-type IPAD_PRO_3GEN_129

echo "Raw screenshots: $RAW_DIR"
echo "App Store exports: $MARKETING_DIR"
