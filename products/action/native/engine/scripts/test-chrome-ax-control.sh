#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
BUN_BIN="${BUN_BIN:-$HOME/.bun/bin/bun}"
TRACE_FILE="${ACTION_CHROME_AX_TRACE_FILE:-/tmp/action-chrome-ax-control.trace}"
OUTPUT_DIR="${ACTION_CHROME_AX_OUTPUT_DIR:-/tmp/action-chrome-ax-control-$(date +%Y%m%d-%H%M%S)}"
TARGET_URL="${ACTION_CHROME_AX_TARGET_URL:-https://example.com/?action_ax_chrome=1}"
CHROME_BUNDLE_ID="${ACTION_CHROME_AX_BUNDLE_ID:-com.google.Chrome}"

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

show_overlay() {
  "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
    --duration-ms 30000 \
    --status-only true \
    --label "Chrome AX" \
    --status-detail "observe -> resolve -> act -> rescan -> verify" \
    --trace-file "$TRACE_FILE" \
    --trace-title "Chrome AX control" >/dev/null 2>&1 &
  OVERLAY_PID=$!
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
  "$BUN_BIN" -e '
const fs = require("fs");
const path = process.argv[1];
const nodes = JSON.parse(fs.readFileSync(path, "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const omnibox = nodes.find((node) =>
  node.role === "AXTextField" &&
  /address and search bar/i.test(text(node))
);
const newTab = nodes.find((node) =>
  (node.actions || []).includes("AXPress") &&
  /new tab/i.test(text(node))
);
const focused = nodes.find((node) => node.focused);
console.log(JSON.stringify({
  nodes: nodes.length,
  hasNewTab: Boolean(newTab),
  omniboxValue: omnibox?.value ?? null,
  omniboxActions: omnibox?.actions ?? [],
  omniboxSettable: omnibox?.settableAttributes ?? [],
  focusedRole: focused?.role ?? null,
  focusedText: focused ? text(focused).slice(0, 120) : null,
}));
' "$path"
}

require_new_tab_button() {
  local path="$1"
  "$BUN_BIN" -e '
const fs = require("fs");
const nodes = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const found = nodes.some((node) =>
  (node.actions || []).includes("AXPress") &&
  /new tab/i.test(text(node))
);
process.exit(found ? 0 : 1);
' "$path"
}

FRONT_BEFORE=$(front_bundle)
log_event "observe" "frontmost before: ${FRONT_BEFORE:-unknown}"
log_event "policy" "Chrome target focus may change; host focus should not"
show_overlay

log_event "observe" "snapshot Chrome before acting"
BEFORE_JSON=$(snapshot_chrome "01-before")
BEFORE_SUMMARY=$(summarize_snapshot "$BEFORE_JSON")
log_event "resolve" "before: $BEFORE_SUMMARY"
if ! require_new_tab_button "$BEFORE_JSON"; then
  log_event "abort" "Could not resolve Chrome New Tab button"
  exit 1
fi

sleep 0.8
log_event "act" "AXPress New Tab"
"$APP_EXECUTABLE" press-accessibility-element \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --label "New Tab" \
  --role AXButton >/dev/null

sleep 0.8
log_event "observe" "rescan after New Tab"
AFTER_TAB_JSON=$(snapshot_chrome "02-after-new-tab")
log_event "resolve" "after tab: $(summarize_snapshot "$AFTER_TAB_JSON")"

sleep 0.4
log_event "act" "direct-to-Chrome Cmd-L"
"$APP_EXECUTABLE" press-app-key \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --key l \
  --modifiers cmd >/dev/null

sleep 0.4
log_event "observe" "rescan after Cmd-L"
AFTER_CMDL_JSON=$(snapshot_chrome "03-after-cmd-l")
log_event "resolve" "after Cmd-L: $(summarize_snapshot "$AFTER_CMDL_JSON")"

sleep 0.4
log_event "act" "direct-to-Chrome type target URL"
"$APP_EXECUTABLE" type-app-text \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --text "$TARGET_URL" \
  --delay-ms 2 >/dev/null

sleep 0.5
log_event "observe" "rescan after typing"
AFTER_TYPE_JSON=$(snapshot_chrome "04-after-type")
log_event "resolve" "after type: $(summarize_snapshot "$AFTER_TYPE_JSON")"

sleep 0.3
log_event "act" "direct-to-Chrome Return"
"$APP_EXECUTABLE" press-app-key \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --key return >/dev/null

sleep 2.0
log_event "observe" "rescan after Return"
AFTER_RETURN_JSON=$(snapshot_chrome "05-after-return")
AFTER_RETURN_SUMMARY=$(summarize_snapshot "$AFTER_RETURN_JSON")
log_event "verify" "after Return: $AFTER_RETURN_SUMMARY"

FRONT_AFTER=$(front_bundle)
if [[ -n "${FRONT_BEFORE:-}" && -n "${FRONT_AFTER:-}" && "$FRONT_BEFORE" == "$FRONT_AFTER" ]]; then
  log_event "done" "frontmost preserved: $FRONT_AFTER"
else
  log_event "warn" "frontmost changed: ${FRONT_BEFORE:-unknown} -> ${FRONT_AFTER:-unknown}"
fi

wait "$OVERLAY_PID" || true
printf 'Trace: %s\n' "$TRACE_FILE"
printf 'Snapshots: %s\n' "$OUTPUT_DIR"
