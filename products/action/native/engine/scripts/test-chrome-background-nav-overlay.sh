#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
BUN_BIN="${BUN_BIN:-$HOME/.bun/bin/bun}"
TRACE_FILE="${ACTION_CHROME_BG_TRACE_FILE:-/tmp/action-chrome-bg-nav.trace}"
OUTPUT_DIR="${ACTION_CHROME_BG_OUTPUT_DIR:-/tmp/action-chrome-bg-nav-$(date +%Y%m%d-%H%M%S)}"
TARGET_URL="${ACTION_CHROME_BG_TARGET_URL:-https://www.midjourney.com/}"
CHROME_BUNDLE_ID="${ACTION_CHROME_BG_BUNDLE_ID:-com.google.Chrome}"
SUPPRESS_OVERLAY="${ACTION_CHROME_BG_SUPPRESS_OVERLAY:-0}"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  "$SCRIPT_DIR/build-app.sh" >/dev/stderr
fi

if [[ ! -x "$BUN_BIN" ]]; then
  echo "bun was not found at $BUN_BIN" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$TRACE_FILE"

front_bundle() {
  local asn
  asn=$(lsappinfo front 2>/dev/null | awk '{print $1}' | sed 's/ASN://;s/:$//' || true)
  [[ -n "$asn" ]] || return 0
  lsappinfo info -only bundleid "ASN:$asn" 2>/dev/null \
    | sed -n 's/^"CFBundleIdentifier"="\(.*\)"$/\1/p' \
    | head -1
}

log_event() {
  local kind="$1"
  local text="$2"
  printf '%s|%s\n' "$kind" "$text" >> "$TRACE_FILE"
  printf '[%s] %s\n' "$kind" "$text"
}

status_overlay() {
  if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
    return 0
  fi

  local label="$1"
  local duration_ms="$2"
  local detail="$3"
  "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
    --duration-ms "$duration_ms" \
    --status-only true \
    --label "$label" \
    --status-detail "$detail" \
    --trace-file "$TRACE_FILE" \
    --trace-title "Action background Chrome" >/dev/null 2>&1 &
}

start_action_overlay() {
  if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
    return 0
  fi

  local label="$1"
  local duration_ms="$2"
  local detail="$3"
  shift 3
  if [[ "$TARGET_IS_FRONTMOST" == "true" ]]; then
    "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
      --duration-ms "$duration_ms" \
      --label "$label" \
      --status-detail "$detail" \
      --trace-file "$TRACE_FILE" \
      --trace-title "Action background Chrome" \
      "$@" >/dev/null 2>&1 &
  else
    "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
      --duration-ms "$duration_ms" \
      --status-only true \
      --label "$label" \
      --status-detail "background Chrome: $detail" \
      --trace-file "$TRACE_FILE" \
      --trace-title "Action background Chrome" \
      "$@" >/dev/null 2>&1 &
  fi
}

snapshot_chrome() {
  local name="$1"
  local path="$OUTPUT_DIR/$name.json"
  "$APP_EXECUTABLE" inspect-app-ui \
    --bundle-id "$CHROME_BUNDLE_ID" \
    --max-depth 14 \
    --max-nodes 3000 > "$path"
  printf '%s\n' "$path"
}

summarize_snapshot() {
  local path="$1"
  "$BUN_BIN" - "$path" <<'BUN'
const fs = require("fs");
const nodes = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const omnibox = nodes.find((node) =>
  node.role === "AXTextField" &&
  /address and search bar/i.test(text(node))
);
const focused = nodes.find((node) => node.focused);
const window = nodes.find((node) => node.role === "AXWindow");
const webArea = nodes.find((node) => node.role === "AXWebArea");
console.log(JSON.stringify({
  nodes: nodes.length,
  windowTitle: window?.title ?? null,
  omniboxValue: omnibox?.value ?? null,
  omniboxFocused: omnibox?.focused ?? null,
  focusedRole: focused?.role ?? null,
  focusedText: focused ? text(focused).slice(0, 140) : null,
  webTitle: webArea?.title ?? null,
}));
BUN
}

resolve_omnibox_point() {
  local tree_json="$1"
  local screen_png="$2"
  local point_json="$3"
  "$BUN_BIN" - "$tree_json" "$screen_png" "$point_json" <<'BUN'
const fs = require("fs");
const { execFileSync } = require("child_process");
const [treePath, screenPath, pointPath] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(treePath, "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const field = nodes.find((node) =>
  node.role === "AXTextField" &&
  /address and search bar/i.test(text(node)) &&
  node.frame
);
if (!field) {
  throw new Error("Could not resolve Chrome Address and search bar AXTextField");
}

const sips = execFileSync("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", screenPath], {
  encoding: "utf8",
});
const widthMatch = sips.match(/pixelWidth:\s*(\d+)/);
const heightMatch = sips.match(/pixelHeight:\s*(\d+)/);
const screenWidth = widthMatch ? Number(widthMatch[1]) : 3024;
const screenHeight = heightMatch ? Number(heightMatch[1]) : 1964;

const x = Math.round(field.frame.x + field.frame.width / 2);
const y = Math.round(screenHeight - (field.frame.y + field.frame.height / 2));
const startX = Math.max(42, Math.min(screenWidth - 80, x + Math.min(520, Math.max(240, field.frame.width * 0.32))));
const startY = Math.max(86, Math.min(screenHeight - 90, y + 230));

fs.writeFileSync(pointPath, JSON.stringify({
  field,
  overlayPoint: { x, y },
  startPoint: { x: Math.round(startX), y: Math.round(startY) },
  screen: { width: screenWidth, height: screenHeight },
}, null, 2));
BUN
}

write_suppressed_overlay_point() {
  local tree_json="$1"
  local point_json="$2"
  "$BUN_BIN" - "$tree_json" "$point_json" <<'BUN'
const fs = require("fs");
const [treePath, pointPath] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(treePath, "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const field = nodes.find((node) =>
  node.role === "AXTextField" &&
  /address and search bar/i.test(text(node)) &&
  node.frame
);
if (!field) {
  throw new Error("Could not resolve Chrome Address and search bar AXTextField");
}

fs.writeFileSync(pointPath, JSON.stringify({
  field,
  overlayPoint: { x: 0, y: 0 },
  startPoint: { x: 0, y: 0 },
  screen: null,
}, null, 2));
BUN
}

if ! pgrep -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" >/dev/null 2>&1; then
  log_event "abort" "Google Chrome is not running; refusing to launch it because this test should stay background-safe"
  status_overlay "Chrome not running" 1800 "background-safe test stopped"
  wait || true
  exit 1
fi

FRONT_BEFORE=$(front_bundle)
TARGET_IS_FRONTMOST=false
if [[ "${FRONT_BEFORE:-}" == "$CHROME_BUNDLE_ID" ]]; then
  TARGET_IS_FRONTMOST=true
fi
log_event "observe" "frontmost before: ${FRONT_BEFORE:-unknown}"
if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
  log_event "policy" "overlay suppressed; real action uses Chrome AX and process-directed key events"
else
  log_event "policy" "decorative cursor only; real action uses Chrome AX and process-directed key events"
  if [[ "$TARGET_IS_FRONTMOST" != "true" ]]; then
    log_event "policy" "decorative cursor disabled for background target"
  fi
fi
status_overlay "Observe" 1200 "scan Chrome AX without activation"

BEFORE_JSON=$(snapshot_chrome "01-before")
log_event "resolve" "before: $(summarize_snapshot "$BEFORE_JSON")"

SCREEN_PROBE="$OUTPUT_DIR/screen.png"
POINT_JSON="$OUTPUT_DIR/omnibox-point.json"
if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
  write_suppressed_overlay_point "$BEFORE_JSON" "$POINT_JSON"
else
  "$SCRIPT_DIR/run-app-host.sh" screenshot-screen --output "$SCREEN_PROBE" >/dev/null
  resolve_omnibox_point "$BEFORE_JSON" "$SCREEN_PROBE" "$POINT_JSON"
fi

OMNI_X=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').overlayPoint.x)")
OMNI_Y=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').overlayPoint.y)")
START_X=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').startPoint.x)")
START_Y=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').startPoint.y)")
FIELD_DETAIL=$("$BUN_BIN" -e "const p=require('$POINT_JSON'); const f=p.field.frame; console.log('omnibox '+Math.round(f.width)+'x'+Math.round(f.height)+' @ '+Math.round(f.x)+','+Math.round(f.y))")

log_event "resolve" "resolved visible Chrome omnibox: $FIELD_DETAIL"

if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
  log_event "act" "AXPress Address and search bar"
else
  log_event "act" "visual click at $OMNI_X,$OMNI_Y; AXPress Address and search bar"
fi
start_action_overlay \
  "Click" \
  1050 \
  "AXPress Chrome omnibox" \
  --start-x "$START_X" \
  --start-y "$START_Y" \
  --end-x "$OMNI_X" \
  --end-y "$OMNI_Y" \
  --click-progress 0.64
sleep 0.62
"$APP_EXECUTABLE" perform-accessibility-action \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --role AXTextField \
  --label "Address and search bar" \
  --action AXPress >/dev/null

AFTER_FOCUS_JSON=$(snapshot_chrome "02-after-focus")
if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
  log_event "observe" "after AXPress: $(summarize_snapshot "$AFTER_FOCUS_JSON")"
else
  log_event "observe" "after visual click: $(summarize_snapshot "$AFTER_FOCUS_JSON")"
fi

TYPE_DURATION_MS=$(( 1250 + ${#TARGET_URL} * 42 ))
CHAR_DELAY=$("$BUN_BIN" -e "console.log(Math.max(0.028, Math.min(0.06, (($TYPE_DURATION_MS - 650) / Math.max(1, '$TARGET_URL'.length)) / 1000)).toFixed(3))")

if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
  log_event "act" "AX value update: $TARGET_URL"
else
  log_event "act" "visual typing and AX value update: $TARGET_URL"
fi
start_action_overlay \
  "Typing" \
  "$TYPE_DURATION_MS" \
  "AX value update" \
  --start-x "$OMNI_X" \
  --start-y "$OMNI_Y" \
  --end-x "$OMNI_X" \
  --end-y "$OMNI_Y" \
  --click-progress 0.50 \
  --typing-text "$TARGET_URL" \
  --typing-sound timed
sleep 0.18
/bin/bash -s "$APP_EXECUTABLE" "$CHROME_BUNDLE_ID" "$TARGET_URL" "$CHAR_DELAY" <<'BASH'
set -euo pipefail
app="$1"
bundle="$2"
target="$3"
delay="$4"
value=""
for ((i = 0; i < ${#target}; i++)); do
  value+="${target:i:1}"
  "$app" set-accessibility-value \
    --bundle-id "$bundle" \
    --role AXTextField \
    --label "Address and search bar" \
    --value "$value" >/dev/null
  sleep "$delay"
done
BASH

AFTER_TYPE_JSON=$(snapshot_chrome "03-after-type")
log_event "observe" "after typing: $(summarize_snapshot "$AFTER_TYPE_JSON")"

if [[ "$SUPPRESS_OVERLAY" == "1" ]]; then
  log_event "act" "process-directed Return to Chrome"
else
  log_event "act" "visual Return key; process-directed Return to Chrome"
fi
start_action_overlay \
  "Return" \
  950 \
  "commit navigation" \
  --start-x "$OMNI_X" \
  --start-y "$OMNI_Y" \
  --end-x "$OMNI_X" \
  --end-y "$OMNI_Y" \
  --click-progress 0.50 \
  --key-label "Return"
sleep 0.42
"$APP_EXECUTABLE" press-app-key \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --key return >/dev/null

sleep 2.0
AFTER_RETURN_JSON=$(snapshot_chrome "04-after-return")
AFTER_RETURN_SUMMARY=$(summarize_snapshot "$AFTER_RETURN_JSON")
log_event "verify" "after Return: $AFTER_RETURN_SUMMARY"

VERIFY_RESULT=$("$BUN_BIN" - "$AFTER_RETURN_JSON" "$TARGET_URL" <<'BUN'
const fs = require("fs");
const [afterPath, targetUrl] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(afterPath, "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const omnibox = nodes.find((node) => node.role === "AXTextField" && /address and search bar/i.test(text(node)));
const value = String(omnibox?.value ?? "");
const targetHost = new URL(targetUrl).hostname.replace(/^www\./, "");
const ok = value.includes(targetHost);
console.log(JSON.stringify({ ok, value, targetHost }));
process.exit(ok ? 0 : 1);
BUN
) || VERIFY_RESULT='{"ok":false}'

FRONT_AFTER=$(front_bundle)
if [[ -n "${FRONT_BEFORE:-}" && -n "${FRONT_AFTER:-}" && "$FRONT_BEFORE" == "$FRONT_AFTER" ]]; then
  log_event "done" "frontmost preserved: $FRONT_AFTER"
else
  log_event "warn" "frontmost changed: ${FRONT_BEFORE:-unknown} -> ${FRONT_AFTER:-unknown}"
  if [[ -n "${FRONT_BEFORE:-}" ]]; then
    "$APP_EXECUTABLE" activate-app --bundle-id "$FRONT_BEFORE" >/dev/null || true
  fi
fi

if [[ "$VERIFY_RESULT" == *'"ok":true'* ]]; then
  status_overlay "Done" 1800 "loaded without frontmost change"
else
  status_overlay "Check needed" 2200 "navigation did not verify"
fi
wait || true

printf 'Trace: %s\n' "$TRACE_FILE"
printf 'Artifacts: %s\n' "$OUTPUT_DIR"
printf 'Verification: %s\n' "$VERIFY_RESULT"

if [[ "$VERIFY_RESULT" != *'"ok":true'* ]]; then
  exit 1
fi
