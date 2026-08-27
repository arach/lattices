#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_DIR="$ROOT_DIR/native/dist/Action.app"
PLIST_PATH="$APP_DIR/Contents/Info.plist"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Action.app has not been built yet: $APP_DIR" >&2
  exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST_PATH")
signature=$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)

if [[ "$bundle_id" != "dev.action.Action" ]]; then
  echo "Unexpected bundle id: $bundle_id" >&2
  exit 1
fi

if ! grep -q 'Authority=Apple Development:' <<<"$signature" && ! grep -q 'Authority=Developer ID Application:' <<<"$signature"; then
  echo "Action.app is not signed with a developer identity." >&2
  echo "$signature" >&2
  exit 1
fi

if grep -q 'Signature=adhoc' <<<"$signature"; then
  echo "Action.app is ad-hoc signed, which is not acceptable for stable TCC checks." >&2
  echo "$signature" >&2
  exit 1
fi

if grep -q 'Info.plist=not bound' <<<"$signature"; then
  echo "Action.app signature does not bind Info.plist." >&2
  echo "$signature" >&2
  exit 1
fi

echo "bundleId=$bundle_id"
echo "$signature" | awk '/^Identifier=|^Authority=|^TeamIdentifier=|^Signed Time=/{print}'
