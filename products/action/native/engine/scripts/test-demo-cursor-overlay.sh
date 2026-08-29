#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
CONTROL_FILE="${ACTION_TERMINAL_CONTROL_FILE:-/tmp/action-overlay-smoke.controls}"
STOP_FILE="${ACTION_TERMINAL_STOP_FILE:-/tmp/action-overlay-smoke.stop}"
OUTPUT_PREFIX="${1:-/tmp/action-overlay-smoke-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_PREFIX="${OUTPUT_PREFIX%.png}"

rm -f "$CONTROL_FILE" "$STOP_FILE"

"$SCRIPT_DIR/run-app-host.sh" terminal-session \
  --control-file "$CONTROL_FILE" \
  --stop-file "$STOP_FILE" \
  --cwd "$ROOT_DIR"

sleep 0.9

# Narrow multi-monitor placement check: overlay CGWindow X/size must match an
# NSScreen.frame (never 2× screen origin from double-applied contentRect).
assert_overlay_on_screen() {
  swift -e '
import Cocoa
guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
  fputs("FAIL: no window list\n", stderr); exit(1)
}
var matched = false
for w in info {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  guard owner == "Action" else { continue }
  let layer = w[kCGWindowLayer as String] as? Int ?? 0
  guard layer >= 1000 else { continue }
  let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let x = (bounds["X"] as? NSNumber)?.doubleValue ?? -1
  let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? -1
  let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? -1
  let matches = NSScreen.screens.contains {
    abs($0.frame.origin.x - x) < 1
      && abs($0.frame.size.width - width) < 1
      && abs($0.frame.size.height - height) < 1
  }
  let doubled = NSScreen.screens.contains {
    $0.frame.origin.x != 0 && abs(($0.frame.origin.x * 2) - x) < 1
  }
  if doubled {
    fputs("FAIL: demo cursor overlay double-applied screen origin (x=\(Int(x)))\n", stderr)
    exit(2)
  }
  if !matches {
    fputs("FAIL: demo cursor overlay bounds x=\(Int(x)) \(Int(width))x\(Int(height)) match no NSScreen\n", stderr)
    exit(3)
  }
  matched = true
  FileHandle.standardError.write(Data("overlay-placement: x=\(Int(x)) \(Int(width))x\(Int(height)) ok\n".utf8))
}
if !matched {
  fputs("FAIL: no Action overlay window found\n", stderr)
  exit(4)
}
'
}

# Mouse click beat: default --cursor auto draws the premium pointer.
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 1400 \
  --start-x 3060 \
  --start-y 910 \
  --end-x 2410 \
  --end-y 995 \
  --click-progress 0.72 \
  --label Click \
  --cursor auto &
CLICK_PID=$!
sleep 0.45
assert_overlay_on_screen
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-click.png"
wait "$CLICK_PID" || true
sleep 0.3

# Typing beat under auto: captions only — no synthetic pointer or caret.
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 2600 \
  --start-x 2410 \
  --start-y 995 \
  --end-x 2410 \
  --end-y 995 \
  --click-progress 0.50 \
  --label Typing \
  --typing-text 'echo "overlay smoke typing"' \
  --cursor auto

sleep 0.25
printf 'echo "overlay smoke typing"\n' >> "$CONTROL_FILE"
sleep 0.55
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-typing.png"
sleep 2.2

"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 900 \
  --start-x 2410 \
  --start-y 995 \
  --end-x 3070 \
  --end-y 920 \
  --click-progress 0.95 \
  --label Move \
  --cursor auto

sleep 0.35
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-move.png"
sleep 1.0

# Key chord under auto: key-cap caption, no synthetic cursor.
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 1100 \
  --start-x 3070 \
  --start-y 920 \
  --end-x 3070 \
  --end-y 920 \
  --click-progress 0.50 \
  --label Command-Tab \
  --key-label Command-Tab \
  --cursor auto

sleep 0.5
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-key.png"
sleep 1.2

# Explicit caption-only mode: status/caption surfaces with no pointer on a mouse label.
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 900 \
  --start-x 2600 \
  --start-y 980 \
  --end-x 2900 \
  --end-y 900 \
  --click-progress 0.55 \
  --label "Observe surface" \
  --status-detail "caption-only mode" \
  --cursor caption-only

sleep 0.35
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-caption-only.png"

printf 'stop\n' > "$STOP_FILE"
ls -lh "$OUTPUT_PREFIX"-*.png
