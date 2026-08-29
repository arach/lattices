#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
CDP_HELPER="$SCRIPT_DIR/mira-midjourney-cdp.mjs"
CHROME_APP_NAME="${ACTION_CHROME_APP_NAME:-Google Chrome}"
DEBUG_PORT="${ACTION_MIRA_DEBUG_PORT:-9335}"
PROFILE_DIR="${ACTION_MIRA_PROFILE_DIR:-$HOME/Library/Application Support/Action/ChromeProfiles/mira}"
TARGET_URL="${ACTION_MIDJOURNEY_URL:-https://www.midjourney.com/imagine}"
OUTPUT_DIR="${ACTION_MIDJOURNEY_RECORD_OUTPUT_DIR:-$ROOT_DIR/artifacts/captures/mira-midjourney-logo-$(date +%Y%m%d-%H%M%S)}"
PROMPT="${ACTION_MIDJOURNEY_PROMPT:-refined logo mark for Action macOS app, flat vector symbol, abstract capital A formed by a cursor arrow in negative space and one electric cyan stroke, tiny coral recording dot, four subtle capture-corner ticks, confident developer tool identity, clean geometric strokes, balanced centered composition, warm off-white background, graphite black, minimal and memorable, no shadows, no app tile, no texture, no mockup photo, no words, no readable text}"
FPS="${ACTION_MIDJOURNEY_RECORD_FPS:-15}"
WAIT_TIMEOUT_MS="${ACTION_MIDJOURNEY_WAIT_TIMEOUT_MS:-300000}"
SKIP_SUBMIT="${ACTION_MIDJOURNEY_SKIP_SUBMIT:-0}"

usage() {
  cat <<'EOF'
record-mira-midjourney-logo-demo: record Action driving the mira Chrome profile on Midjourney

Usage:
  record-mira-midjourney-logo-demo.sh [options]

Options:
  --output-dir <dir>     Artifact directory
  --prompt <text>        Midjourney prompt
  --debug-port <port>    Mira Chrome debug port, default 9335
  -h, --help             Show this help
EOF
}

activate_mira() {
  local pid
  pid=$(mira_pid)
  if [[ -z "$pid" ]]; then
    return 0
  fi

  /usr/bin/osascript - "$pid" <<'APPLESCRIPT' >/dev/null
use framework "AppKit"
use scripting additions
on run argv
  set targetPid to (item 1 of argv) as integer
  set appRef to current application's NSRunningApplication's runningApplicationWithProcessIdentifier:targetPid
  if appRef is not missing value then
    appRef's activateWithOptions:(current application's NSApplicationActivateIgnoringOtherApps)
  end if
end run
APPLESCRIPT
  sleep 0.5
}

mira_pid() {
  pgrep -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=.*ChromeProfiles/mira" | head -1 || true
}

write_mira_frame() {
  local pid
  pid=$(mira_pid)
  if [[ -z "$pid" ]]; then
    echo "Mira Chrome profile is not running." >&2
    exit 2
  fi

  MIRA_PID="$pid" swift - > "$FRAME_JSON" <<'SWIFT'
import CoreGraphics
import Foundation

let pid = Int(ProcessInfo.processInfo.environment["MIRA_PID"] ?? "") ?? -1
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let match = windows.first { item in
    (item[kCGWindowOwnerPID as String] as? Int) == pid
        && (item[kCGWindowLayer as String] as? Int ?? 0) == 0
        && ((item[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 200
}

guard let match,
      let bounds = match[kCGWindowBounds as String] as? [String: Any] else {
    fputs("Unable to resolve Mira Chrome window frame.\\n", stderr)
    exit(1)
}

let frame: [String: Any] = [
    "x": bounds["X"] ?? 0,
    "y": bounds["Y"] ?? 0,
    "width": bounds["Width"] ?? 0,
    "height": bounds["Height"] ?? 0,
]
let payload: [String: Any] = [
    "pid": pid,
    "windowId": match[kCGWindowNumber as String] ?? 0,
    "title": match[kCGWindowName as String] ?? "",
    "frame": frame,
]
let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
SWIFT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --prompt)
      PROMPT="$2"
      shift 2
      ;;
    --debug-port)
      DEBUG_PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  "$SCRIPT_DIR/build-app.sh" >/dev/stderr
fi

mkdir -p "$OUTPUT_DIR" "$PROFILE_DIR"

MOV_PATH="$OUTPUT_DIR/action-mira-midjourney-logo.mov"
STOP_FILE="$MOV_PATH.stop"
FINISHED_FILE="$MOV_PATH.finished"
DEBUG_LOG="$MOV_PATH.log"
RECORD_REPLY="$OUTPUT_DIR/record-start.json"
STATUS_BEFORE="$OUTPUT_DIR/status-before.json"
STATUS_AFTER="$OUTPUT_DIR/status-after-submit.json"
STATUS_RESULT="$OUTPUT_DIR/status-result.json"
FINAL_SCREENSHOT="$OUTPUT_DIR/final-midjourney.png"
FRAME_JSON="$OUTPUT_DIR/mira-frame.json"

rm -f "$MOV_PATH" "$STOP_FILE" "$FINISHED_FILE" "$DEBUG_LOG" "$RECORD_REPLY" \
  "$STATUS_BEFORE" "$STATUS_AFTER" "$STATUS_RESULT" "$FINAL_SCREENSHOT" "$FRAME_JSON"

if ! curl -fsS "http://127.0.0.1:$DEBUG_PORT/json/version" >/dev/null 2>&1; then
  open -n -a "$CHROME_APP_NAME" --args \
    "--user-data-dir=$PROFILE_DIR" \
    "--no-first-run" \
    "--no-default-browser-check" \
    "--remote-debugging-port=$DEBUG_PORT" \
    --new-window "$TARGET_URL"
  sleep 3
fi

"$CDP_HELPER" status --debug-port "$DEBUG_PORT" --url "$TARGET_URL" > "$STATUS_BEFORE"
BEFORE_IMAGE_COUNT=$(STATUS_PATH="$STATUS_BEFORE" bun -e 'const status = await Bun.file(process.env.STATUS_PATH).json(); console.log(status.imageCount || 0);')
activate_mira

if ! /usr/bin/grep -q '"promptReady": true' "$STATUS_BEFORE"; then
  echo "Mira is not ready to submit a Midjourney prompt yet." >&2
  echo "Sign in to Midjourney in the mira Chrome profile, then rerun this script." >&2
  echo "Status: $STATUS_BEFORE" >&2
  exit 2
fi

activate_mira
write_mira_frame
REGION_X=$(STATUS_PATH="$FRAME_JSON" bun -e 'const data = await Bun.file(process.env.STATUS_PATH).json(); console.log(Math.floor(data.frame.x));')
REGION_Y=$(STATUS_PATH="$FRAME_JSON" bun -e 'const data = await Bun.file(process.env.STATUS_PATH).json(); console.log(Math.floor(data.frame.y));')
REGION_W=$(STATUS_PATH="$FRAME_JSON" bun -e 'const data = await Bun.file(process.env.STATUS_PATH).json(); console.log(Math.ceil(data.frame.width));')
REGION_H=$(STATUS_PATH="$FRAME_JSON" bun -e 'const data = await Bun.file(process.env.STATUS_PATH).json(); console.log(Math.ceil(data.frame.height));')

"$SCRIPT_DIR/run-app-host.sh" record-region \
  --x "$REGION_X" \
  --y "$REGION_Y" \
  --width "$REGION_W" \
  --height "$REGION_H" \
  --fps "$FPS" \
  --scale 1 \
  --output "$MOV_PATH" \
  --stop-file "$STOP_FILE" \
  --finished-file "$FINISHED_FILE" \
  --debug-log "$DEBUG_LOG" > "$RECORD_REPLY"

sleep 0.8

if [[ "$SKIP_SUBMIT" == "1" ]]; then
  cp "$STATUS_BEFORE" "$STATUS_AFTER"
  sleep "${ACTION_MIDJOURNEY_SHOWCASE_SECONDS:-12}"
  cp "$STATUS_BEFORE" "$STATUS_RESULT"
  WAIT_STATUS=0
else
  "$CDP_HELPER" submit \
    --debug-port "$DEBUG_PORT" \
    --url "$TARGET_URL" \
    --prompt "$PROMPT" > "$STATUS_AFTER"

  set +e
  "$CDP_HELPER" wait-result \
    --debug-port "$DEBUG_PORT" \
    --url "$TARGET_URL" \
    --min-image-count "$BEFORE_IMAGE_COUNT" \
    --timeout-ms "$WAIT_TIMEOUT_MS" > "$STATUS_RESULT"
  WAIT_STATUS=$?
  set -e
fi

activate_mira
"$SCRIPT_DIR/run-app-host.sh" screenshot-region \
  --x "$REGION_X" \
  --y "$REGION_Y" \
  --width "$REGION_W" \
  --height "$REGION_H" \
  --output "$FINAL_SCREENSHOT" >/dev/null

printf 'stop\n' > "$STOP_FILE"

for _ in {1..240}; do
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

if [[ "$WAIT_STATUS" -ne 0 ]]; then
  echo "Midjourney result was not confirmed before timeout; recording was still saved." >&2
fi

echo "[done] recording: $MOV_PATH"
echo "[done] finished-marker: $FINISHED_FILE"
echo "[done] final-screenshot: $FINAL_SCREENSHOT"
echo "[done] status-before: $STATUS_BEFORE"
echo "[done] status-after-submit: $STATUS_AFTER"
echo "[done] status-result: $STATUS_RESULT"
echo "[done] frame: $FRAME_JSON"
ls -lh "$MOV_PATH" "$FINAL_SCREENSHOT"
