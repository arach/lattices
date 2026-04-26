#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$ROOT"
PROJECT="$PROJECT_DIR/LatticesCompanion.xcodeproj"
SCHEME="LatticesCompanion"
DERIVED_DATA="$PROJECT_DIR/.derived-data"
DEVICE_CACHE="$PROJECT_DIR/.device-id.local"
BUNDLE_ID="com.arach.lattices.companion.ios"

resolve_device_id() {
  if [[ -n "${LATTICES_DEVICE_ID:-}" ]]; then
    echo "$LATTICES_DEVICE_ID"
    return
  fi

  if [[ -f "$DEVICE_CACHE" ]]; then
    cat "$DEVICE_CACHE"
    return
  fi

  xcrun xcdevice list | ruby -rjson -e '
    devices = JSON.parse(STDIN.read)
    ios = devices.select { |d|
      !d["simulator"] &&
      d["platform"] == "com.apple.platform.iphoneos" &&
      d["available"]
    }
    preferred = ios.find { |d| d["name"].to_s.downcase.include?("ipad") } || ios.first
    abort("No connected iPhone or iPad device found.") unless preferred
    puts preferred["identifier"]
  '
}

echo "Generating Xcode project"
xcodegen generate --spec "$PROJECT_DIR/project.yml"

DEVICE_ID="$(resolve_device_id)"
echo "$DEVICE_ID" > "$DEVICE_CACHE"

echo "Building for device $DEVICE_ID"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "id=$DEVICE_ID" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/LatticesCompanion.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Installing on device"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Launching app"
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID"

echo "Installed and launched on $DEVICE_ID"
