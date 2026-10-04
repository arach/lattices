#!/bin/bash
set -euo pipefail
ROOT=/Users/arach/dev/lattices-editor-host-slice-1
APP="$HOME/Applications/dev/Lattices/Lattices.app"
OUT=$(mktemp -d /private/tmp/lattices-carry-live.XXXXXX)
DOC="$OUT/lattices-carry-test-$(date +%s).txt"
echo "$OUT" > /private/tmp/lattices-carry-live-latest
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" == dev.lattices.app.dev ]]
osascript -e 'tell application id "dev.lattices.app.dev" to quit' 2>/dev/null || true
sleep 1
if pgrep -f "$APP/Contents/MacOS/Lattices" >/dev/null; then echo 'Dev still running'; exit 1; fi
cp "$ROOT/apps/mac/.build/debug/Lattices" "$APP/Contents/MacOS/Lattices"
IDENTITY=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')
codesign --force --options runtime --sign "$IDENTITY" --identifier dev.lattices.app.dev "$APP"
printf 'Bounded Lattices Space carry acceptance test. This document alone may move.\n' > "$DOC"
cleanup() {
  osascript - "$DOC" <<'OSA'
on run argv
 set wanted to item 1 of argv
 tell application "TextEdit"
  repeat with d in documents
   try
    if (path of d as text) is wanted then close d saving no
   end try
  end repeat
 end tell
end run
OSA
}
trap cleanup EXIT
open -a TextEdit "$DOC"
sleep 3
osascript - "$(basename "$DOC")" <<'OSA'
on run argv
 tell application "TextEdit" to set bounds of window (item 1 of argv) to {200, 200, 760, 620}
end run
OSA
sleep 1
open -n "$APP" --args --overview-drag-fixture "$OUT" --overview-carry-live "$DOC"
for ((i=0;i<140;i++)); do [[ -f "$OUT/result.json" ]] && break; sleep 1; done
cat "$OUT/result.json"
echo; echo "Evidence: $OUT"
