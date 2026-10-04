#!/bin/bash
# Real pointer input, only in an isolated dev-app fixture. No real windows are relocated.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/dev/Lattices/Lattices.app"
OUT="$(mktemp -d /private/tmp/lattices-overview-input.XXXXXX)"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" == dev.lattices.app.dev ]]
if pgrep -f "$APP/Contents/MacOS/Lattices" >/dev/null; then
  /usr/bin/osascript -e 'tell application id "dev.lattices.app.dev" to quit' >/dev/null 2>&1 || true
fi
for ((i=0; i<20; i++)); do
  pgrep -f "$APP/Contents/MacOS/Lattices" >/dev/null || break
  sleep 0.5
done
if pgrep -f "$APP/Contents/MacOS/Lattices" >/dev/null; then
  echo "Dev app did not exit; refusing to replace or launch over a live executable." >&2
  exit 1
fi
if [[ "${1:-}" == --debug ]]; then
  LATTICES_HUDSON_PATH="${LATTICES_HUDSON_PATH:-/Users/arach/dev/hudson}" xcrun swift build --package-path "$ROOT/apps/mac"
  cp "$ROOT/apps/mac/.build/debug/Lattices" "$APP/Contents/MacOS/Lattices"
  python3 - "$ROOT/apps/mac/Info.plist" "$APP/Contents/Info.plist" <<'PYCODE'
import plistlib,sys
source=plistlib.load(open(sys.argv[1],'rb')); target=plistlib.load(open(sys.argv[2],'rb'))
target['UTExportedTypeDeclarations']=source['UTExportedTypeDeclarations']
plistlib.dump(target,open(sys.argv[2],'wb'))
PYCODE
  IDENTITY="$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')"
  [[ -n "$IDENTITY" ]]
  codesign --force --options runtime --sign "$IDENTITY" --identifier dev.lattices.app.dev "$APP"
fi
open -n "$APP" --args --overview-drag-fixture "$OUT"
for ((i=0; i<120; i++)); do
  [[ -f "$OUT/result.json" ]] && break
  sleep 1
done
echo "Fixture evidence: $OUT"
cat "$OUT/trace.log" 2>/dev/null || true
python3 - "$OUT/result.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
print(json.dumps(result, indent=2))
sys.exit(0 if result.get('passed') else 1)
PY
