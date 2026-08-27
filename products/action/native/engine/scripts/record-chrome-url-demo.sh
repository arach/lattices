#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
BUN_BIN="${BUN_BIN:-$HOME/.bun/bin/bun}"
TARGET_URL="${ACTION_CHROME_RECORD_TARGET_URL:-https://lattices.dev/action}"
OUTPUT_DIR="${ACTION_CHROME_RECORD_OUTPUT_DIR:-/tmp/action-chrome-url-demo-$(date +%Y%m%d-%H%M%S)}"
CHROME_BUNDLE_ID="${ACTION_CHROME_RECORD_BUNDLE_ID:-com.google.Chrome}"
FPS="${ACTION_CHROME_RECORD_FPS:-15}"
SCALE="${ACTION_CHROME_RECORD_SCALE:-0.75}"
PADDING="${ACTION_CHROME_RECORD_PADDING:-24}"
BACKGROUND="${ACTION_CHROME_RECORD_BACKGROUND:-0}"
OPEN_CHROME="${ACTION_CHROME_RECORD_OPEN_CHROME:-1}"
CAPTURE_MODE="${ACTION_CHROME_RECORD_CAPTURE_MODE:-auto}"
SUPPRESS_OVERLAY="${ACTION_CHROME_RECORD_SUPPRESS_OVERLAY:-}"

usage() {
  cat <<'EOF'
record-chrome-url-demo: record Action driving Chrome to a URL

Usage:
  record-chrome-url-demo [url] [options]

Options:
  --background         Do not activate Chrome; preserve the current frontmost app
  --foreground         Activate Chrome before recording (default)
  --capture-mode <m>   Capture mode: auto, region, or app-window
  --no-open           Do not open a new Chrome window before recording
  --output-dir <dir>  Artifact directory
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --background)
      BACKGROUND=1
      shift
      ;;
    --foreground)
      BACKGROUND=0
      shift
      ;;
    --no-open)
      OPEN_CHROME=0
      shift
      ;;
    --capture-mode)
      if [[ $# -lt 2 ]]; then
        echo "--capture-mode requires a value" >&2
        exit 1
      fi
      CAPTURE_MODE="$2"
      shift 2
      ;;
    --output-dir)
      if [[ $# -lt 2 ]]; then
        echo "--output-dir requires a value" >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      TARGET_URL="$1"
      shift
      ;;
  esac
done

if [[ ! -x "$BUN_BIN" ]]; then
  echo "bun was not found at $BUN_BIN" >&2
  exit 1
fi

case "$CAPTURE_MODE" in
  auto|region|app-window) ;;
  *)
    echo "Invalid capture mode: $CAPTURE_MODE (expected auto, region, or app-window)" >&2
    exit 1
    ;;
esac

if [[ -z "$SUPPRESS_OVERLAY" ]]; then
  SUPPRESS_OVERLAY="$BACKGROUND"
fi

if [[ "$CAPTURE_MODE" == "auto" ]]; then
  if [[ "$BACKGROUND" == "1" ]]; then
    RESOLVED_CAPTURE_MODE="app-window"
  else
    RESOLVED_CAPTURE_MODE="region"
  fi
else
  RESOLVED_CAPTURE_MODE="$CAPTURE_MODE"
fi

mkdir -p "$OUTPUT_DIR"

MOV_PATH="$OUTPUT_DIR/action-chrome-url-demo.mov"
STOP_FILE="$MOV_PATH.stop"
FINISHED_FILE="$MOV_PATH.finished"
DEBUG_LOG="$MOV_PATH.log"
RECORD_REPLY="$OUTPUT_DIR/record-start.json"
FINAL_SCREENSHOT="$OUTPUT_DIR/final-chrome-window.png"
FRAME_JSON="$OUTPUT_DIR/chrome-frame.json"
SCREEN_PROBE="$OUTPUT_DIR/screen-probe.png"

rm -f "$MOV_PATH" "$STOP_FILE" "$FINISHED_FILE" "$DEBUG_LOG" "$RECORD_REPLY" "$FINAL_SCREENSHOT" "$FRAME_JSON" "$SCREEN_PROBE"

front_bundle() {
  local asn
  asn=$(lsappinfo front 2>/dev/null | awk '{print $1}' | sed 's/ASN://;s/:$//' || true)
  [[ -n "$asn" ]] || return 0
  lsappinfo info -only bundleid "ASN:$asn" 2>/dev/null \
    | sed -n 's/^"CFBundleIdentifier"="\(.*\)"$/\1/p' \
    | head -1
}

activate_bundle() {
  local bundle_id="$1"
  [[ -n "$bundle_id" ]] || return 0

  if [[ -x "$APP_EXECUTABLE" ]]; then
    "$APP_EXECUTABLE" activate-app --bundle-id "$bundle_id" >/dev/null 2>&1 && return 0
  fi

  osascript -e "tell application id \"$bundle_id\" to activate" >/dev/null 2>&1 || true
}

restore_frontmost() {
  if [[ "$BACKGROUND" == "1" && -n "${FRONT_BEFORE:-}" && "$FRONT_BEFORE" != "$CHROME_BUNDLE_ID" ]]; then
    activate_bundle "$FRONT_BEFORE"
    sleep 0.4
  fi
}

FRONT_BEFORE=$(front_bundle)
echo "[open] Chrome navigation target: $TARGET_URL"
echo "[open] frontmost before: ${FRONT_BEFORE:-unknown}"
echo "[open] mode: background=$BACKGROUND open=$OPEN_CHROME capture=$RESOLVED_CAPTURE_MODE suppress-overlay=$SUPPRESS_OVERLAY"

if [[ "$OPEN_CHROME" == "1" ]]; then
  if [[ "$BACKGROUND" == "1" ]]; then
    echo "[open] background mode: preparing Chrome without activation"
    open -gj -a "Google Chrome" --args --new-window about:blank >/dev/null 2>&1 || open -ga "Google Chrome" --args --new-window about:blank >/dev/null 2>&1 || true
  else
    echo "[open] foreground mode: opening and activating Chrome"
    open -na "Google Chrome" --args --new-window about:blank
    sleep 1.0
    osascript -e 'tell application "Google Chrome" to activate' >/dev/null 2>&1 || true
  fi
else
  echo "[open] --no-open: using existing Chrome window"
fi

sleep 1.0

restore_frontmost

if [[ "$RESOLVED_CAPTURE_MODE" == "region" ]]; then
  "$SCRIPT_DIR/run-app-host.sh" screenshot-screen --output "$SCREEN_PROBE" >/dev/null
  "$SCRIPT_DIR/run-app-host.sh" get-window-frame --bundle-id "$CHROME_BUNDLE_ID" > "$FRAME_JSON"

  REGION_JSON=$("$BUN_BIN" - "$FRAME_JSON" "$SCREEN_PROBE" "$PADDING" <<'BUN'
const fs = require("fs");
const { execFileSync } = require("child_process");
const [framePath, screenPath, paddingText] = process.argv.slice(2);
const frameResponse = JSON.parse(fs.readFileSync(framePath, "utf8"));
const frame = frameResponse.frame;
if (!frame) throw new Error("Chrome frame missing from get-window-frame response");

const sips = execFileSync("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", screenPath], {
  encoding: "utf8",
});
const widthMatch = sips.match(/pixelWidth:\s*(\d+)/);
const heightMatch = sips.match(/pixelHeight:\s*(\d+)/);
const screenWidth = widthMatch ? Number(widthMatch[1]) : 3440;
const screenHeight = heightMatch ? Number(heightMatch[1]) : 1440;
const padding = Number(paddingText) || 0;

const x = Math.max(0, Math.floor(frame.x - padding));
const y = Math.max(0, Math.floor(frame.y - padding));
const width = Math.min(screenWidth - x, Math.ceil(frame.width + padding * 2));
const height = Math.min(screenHeight - y, Math.ceil(frame.height + padding * 2));

console.log(JSON.stringify({ x, y, width, height, screenWidth, screenHeight, frame }));
BUN
  )

  REGION_X=$("$BUN_BIN" -e "const r=$REGION_JSON; console.log(r.x)")
  REGION_Y=$("$BUN_BIN" -e "const r=$REGION_JSON; console.log(r.y)")
  REGION_W=$("$BUN_BIN" -e "const r=$REGION_JSON; console.log(r.width)")
  REGION_H=$("$BUN_BIN" -e "const r=$REGION_JSON; console.log(r.height)")

  echo "[record] region ${REGION_X},${REGION_Y} ${REGION_W}x${REGION_H} fps=$FPS scale=$SCALE"
  "$SCRIPT_DIR/run-app-host.sh" record-region \
    --x "$REGION_X" \
    --y "$REGION_Y" \
    --width "$REGION_W" \
    --height "$REGION_H" \
    --fps "$FPS" \
    --scale "$SCALE" \
    --output "$MOV_PATH" \
    --stop-file "$STOP_FILE" \
    --finished-file "$FINISHED_FILE" \
    --debug-log "$DEBUG_LOG" > "$RECORD_REPLY"
else
  echo "[record] app-window bundle=$CHROME_BUNDLE_ID"
  "$SCRIPT_DIR/run-app-host.sh" record-app-window \
    --bundle-id "$CHROME_BUNDLE_ID" \
    --output "$MOV_PATH" \
    --stop-file "$STOP_FILE" \
    --finished-file "$FINISHED_FILE" \
    --debug-log "$DEBUG_LOG" > "$RECORD_REPLY"
fi

sleep 0.8
restore_frontmost

if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
  echo "[demo] background AX navigation (overlay suppressed)"
else
  echo "[demo] Action cursor + typing overlay"
fi
ACTION_CHROME_BG_TARGET_URL="$TARGET_URL" \
ACTION_CHROME_BG_OUTPUT_DIR="$OUTPUT_DIR/navigation" \
ACTION_CHROME_BG_TRACE_FILE="$OUTPUT_DIR/trace.log" \
ACTION_CHROME_BG_BUNDLE_ID="$CHROME_BUNDLE_ID" \
ACTION_CHROME_BG_SUPPRESS_OVERLAY="$SUPPRESS_OVERLAY" \
  "$SCRIPT_DIR/test-chrome-background-nav-overlay.sh"

sleep 0.8
printf 'stop\n' > "$STOP_FILE"

for attempt in {1..240}; do
  if [[ -s "$FINISHED_FILE" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -s "$FINISHED_FILE" ]]; then
  echo "Timed out waiting for recording completion marker: $FINISHED_FILE" >&2
  exit 1
fi

if grep -q '^error:' "$FINISHED_FILE"; then
  cat "$FINISHED_FILE" >&2
  exit 1
fi

if [[ -x "$APP_EXECUTABLE" ]]; then
  "$APP_EXECUTABLE" screenshot-app-window \
    --bundle-id "$CHROME_BUNDLE_ID" \
    --output "$FINAL_SCREENSHOT" >/dev/null
else
  "$SCRIPT_DIR/run-app-host.sh" screenshot-app-window \
    --bundle-id "$CHROME_BUNDLE_ID" \
    --output "$FINAL_SCREENSHOT" >/dev/null
fi

restore_frontmost

echo "[done] recording: $MOV_PATH"
echo "[done] finished-marker: $FINISHED_FILE"
echo "[done] final-screenshot: $FINAL_SCREENSHOT"
echo "[done] trace: $OUTPUT_DIR/trace.log"
echo "[done] artifacts: $OUTPUT_DIR"
echo "[done] frontmost before: ${FRONT_BEFORE:-unknown}"
echo "[done] frontmost after: $(front_bundle)"

ls -lh "$MOV_PATH" "$FINAL_SCREENSHOT"
