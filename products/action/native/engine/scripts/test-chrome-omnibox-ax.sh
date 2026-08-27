#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUTPUT_PREFIX="${1:-/tmp/action-chrome-omnibox-ax-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_PREFIX="${OUTPUT_PREFIX%.png}"
QUERY="${ACTION_CHROME_AX_QUERY:-action ax omnibox demo}"
TREE_JSON="$OUTPUT_PREFIX-tree.json"
AFTER_JSON="$OUTPUT_PREFIX-after.json"
SCREEN_PROBE="$OUTPUT_PREFIX-screen.png"
POINT_JSON="$OUTPUT_PREFIX-point.json"
TRACE_LOG="$OUTPUT_PREFIX-trace.log"

rm -f "$TRACE_LOG"

log_event() {
  printf '%s|%s\n' "$1" "$2" >> "$TRACE_LOG"
}

status_overlay() {
  "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
    --duration-ms "${2:-900}" \
    --label "$1" \
    --status-detail "${3:-}" \
    --trace-file "$TRACE_LOG" \
    --trace-title "Action decisions" \
    --status-only true >/dev/null
}

log_event "open" "Open Chrome to google.com"
status_overlay "Open Chrome" 900 "google.com" &
open -a "Google Chrome" "https://www.google.com"
sleep 1.4

"$SCRIPT_DIR/run-app-host.sh" set-window-frame \
  --bundle-id com.google.Chrome \
  --x 1720 \
  --y 30 \
  --width 1120 \
  --height 860 >/dev/null
sleep 0.4

log_event "observe" "Inspect Chrome accessibility tree"
status_overlay "Inspect AX" 900 "Chrome accessibility tree" &
"$SCRIPT_DIR/run-app-host.sh" inspect-app-ui \
  --bundle-id com.google.Chrome \
  --max-depth 8 \
  --max-nodes 700 > "$TREE_JSON"

"$SCRIPT_DIR/run-app-host.sh" screenshot-screen --output "$SCREEN_PROBE" >/dev/null

node - "$TREE_JSON" "$SCREEN_PROBE" "$POINT_JSON" <<'NODE'
const fs = require('fs');
const { execFileSync } = require('child_process');
const [treePath, screenPath, pointPath] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(treePath, 'utf8'));
const field = nodes.find((node) =>
  node.role === 'AXTextField' &&
  node.detail === 'Address and search bar' &&
  node.frame
);
if (!field) {
  throw new Error('Could not resolve Chrome Address and search bar AXTextField');
}

const sips = execFileSync('/usr/bin/sips', ['-g', 'pixelHeight', screenPath], { encoding: 'utf8' });
const match = sips.match(/pixelHeight:\\s*(\\d+)/);
const screenHeight = match ? Number(match[1]) : 1440;
const x = Math.round(field.frame.x + field.frame.width / 2);
const y = Math.round(screenHeight - (field.frame.y + field.frame.height / 2));
fs.writeFileSync(pointPath, JSON.stringify({ field, overlayPoint: { x, y }, screenHeight }, null, 2));
NODE

OMNI_X=$(node -e "console.log(require('$POINT_JSON').overlayPoint.x)")
OMNI_Y=$(node -e "console.log(require('$POINT_JSON').overlayPoint.y)")

RESOLVE_DETAIL=$(node -e "const p=require('$POINT_JSON'); const f=p.field.frame; console.log('AXTextField '+Math.round(f.width)+'x'+Math.round(f.height)+' @ '+Math.round(f.x)+','+Math.round(f.y))")
log_event "resolve" "Resolved omnibox: $RESOLVE_DETAIL"
status_overlay "Resolved AX" 1000 "$RESOLVE_DETAIL" &
sleep 0.9

log_event "act" "Show click at omnibox center $OMNI_X,$OMNI_Y"
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 1050 \
  --start-x 3060 \
  --start-y 1160 \
  --end-x "$OMNI_X" \
  --end-y "$OMNI_Y" \
  --click-progress 0.72 \
  --status-detail "omnibox center $OMNI_X,$OMNI_Y" \
  --trace-file "$TRACE_LOG" \
  --trace-title "Action decisions" \
  --label Click >/dev/null
sleep 1.1

log_event "act" "Type query into Chrome omnibox through AX"
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 4300 \
  --start-x "$OMNI_X" \
  --start-y "$OMNI_Y" \
  --end-x "$OMNI_X" \
  --end-y "$OMNI_Y" \
  --click-progress 0.50 \
  --label Typing \
  --status-detail "AX value update" \
  --typing-text "$QUERY" \
  --trace-file "$TRACE_LOG" \
  --trace-title "Action decisions" \
  --typing-sound timed >/dev/null &

sleep 0.25
/bin/bash -s "$SCRIPT_DIR" "$QUERY" <<'BASH'
set -euo pipefail
script_dir="$1"
query="$2"
value=""
for ((i=0; i<${#query}; i++)); do
  value+="${query:i:1}"
  "$script_dir/run-app-host.sh" set-accessibility-value \
    --bundle-id com.google.Chrome \
    --label "Address and search bar" \
    --role AXTextField \
    --value "$value" >/dev/null
  sleep 0.045
done
BASH
wait

log_event "verify" "Read back Chrome omnibox value"
status_overlay "Verify AX" 900 "read back omnibox" &
"$SCRIPT_DIR/run-app-host.sh" inspect-app-ui \
  --bundle-id com.google.Chrome \
  --max-depth 8 \
  --max-nodes 700 > "$AFTER_JSON"

"$SCRIPT_DIR/run-app-host.sh" screenshot-app-window \
  --bundle-id com.google.Chrome \
  --output "$OUTPUT_PREFIX-window.png" >/dev/null

node - "$AFTER_JSON" "$QUERY" <<'NODE'
const fs = require('fs');
const [afterPath, query] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(afterPath, 'utf8'));
const field = nodes.find((node) =>
  node.role === 'AXTextField' &&
  node.detail === 'Address and search bar'
);
if (!field) {
  throw new Error('Could not find omnibox after typing');
}
if (field.value !== query) {
  throw new Error(`Omnibox value mismatch: expected "${query}", got "${field.value}"`);
}
console.log(JSON.stringify({
  status: 'verified',
  value: field.value,
  frame: field.frame,
}, null, 2));
NODE
log_event "verify" "AX value matched: $QUERY"

node - "$TREE_JSON" "$POINT_JSON" "$AFTER_JSON" "$QUERY" "$OUTPUT_PREFIX-window.png" "$TRACE_LOG" "$OUTPUT_PREFIX-replay.html" <<'NODE'
const fs = require('fs');
const [treePath, pointPath, afterPath, query, screenshotPath, tracePath, reportPath] = process.argv.slice(2);
const tree = JSON.parse(fs.readFileSync(treePath, 'utf8'));
const point = JSON.parse(fs.readFileSync(pointPath, 'utf8'));
const after = JSON.parse(fs.readFileSync(afterPath, 'utf8'));
const finalField = after.find((node) => node.role === 'AXTextField' && node.detail === 'Address and search bar');
const traceLines = fs.readFileSync(tracePath, 'utf8').trim().split(/\n+/).filter(Boolean);
const interesting = tree
  .filter((node) => {
    const haystack = [node.role, node.title, node.detail, node.value, node.identifier].filter(Boolean).join(' ').toLowerCase();
    return haystack.includes('address') || haystack.includes('search') || haystack.includes('google') || node.role === 'AXTextField';
  })
  .slice(0, 18);

const escape = (value) => String(value ?? '')
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;');

const nodeRows = interesting.map((node) => `
  <tr>
    <td>${node.depth}</td>
    <td>${escape(node.role)}</td>
    <td>${escape(node.detail || node.title || node.identifier || '')}</td>
    <td>${escape(node.value || '')}</td>
    <td>${node.frame ? `${Math.round(node.frame.x)}, ${Math.round(node.frame.y)}, ${Math.round(node.frame.width)} x ${Math.round(node.frame.height)}` : ''}</td>
  </tr>
`).join('');
const traceRows = traceLines.map((line) => {
  const [kind, ...rest] = line.split('|');
  return `<li><b>${escape(kind || 'event')}</b><span>${escape(rest.join('|') || line)}</span></li>`;
}).join('');

const html = `<!doctype html>
<meta charset="utf-8">
<title>Action Chrome AX Replay</title>
<style>
  body { margin: 0; background: #101417; color: #eef0eb; font: 14px ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  main { max-width: 1180px; margin: 0 auto; padding: 28px; }
  h1 { font-size: 24px; margin: 0 0 6px; letter-spacing: 0; }
  h2 { font-size: 15px; margin: 28px 0 10px; color: #d8d1bd; }
  .muted { color: #8f989b; }
  .steps { display: grid; grid-template-columns: repeat(5, 1fr); gap: 10px; margin-top: 18px; }
  .step { border: 1px solid rgba(255,255,255,.08); background: rgba(255,255,255,.045); border-radius: 8px; padding: 12px; min-height: 64px; }
  .step b { display: block; color: #f1ead6; margin-bottom: 4px; }
  .grid { display: grid; grid-template-columns: 360px 1fr; gap: 22px; align-items: start; }
  .card { border: 1px solid rgba(255,255,255,.08); background: rgba(255,255,255,.045); border-radius: 8px; padding: 16px; }
  .trace { list-style: none; margin: 0; padding: 0; border: 1px solid rgba(255,255,255,.08); border-radius: 8px; overflow: hidden; }
  .trace li { display: grid; grid-template-columns: 84px 1fr; gap: 12px; padding: 9px 12px; border-bottom: 1px solid rgba(255,255,255,.06); background: rgba(255,255,255,.035); }
  .trace li:last-child { border-bottom: 0; }
  .trace b { color: #d8d1bd; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
  .trace span { color: #e7e9e4; font-size: 13px; }
  code { color: #e8d7a7; }
  table { width: 100%; border-collapse: collapse; overflow: hidden; border-radius: 8px; }
  th, td { padding: 8px 10px; border-bottom: 1px solid rgba(255,255,255,.075); text-align: left; vertical-align: top; }
  th { color: #bdc6c8; font-size: 12px; font-weight: 600; background: rgba(255,255,255,.055); }
  td { color: #e7e9e4; font-size: 12px; }
  img { width: 100%; border-radius: 8px; border: 1px solid rgba(255,255,255,.08); display: block; }
</style>
<main>
  <h1>Chrome AX Omnibox Replay</h1>
  <div class="muted">Action resolved a real Chrome accessibility element, placed the overlay from its frame, typed via AX, then verified the final value.</div>

  <section class="steps">
    <div class="step"><b>Open Chrome</b><span class="muted">google.com</span></div>
    <div class="step"><b>Inspect AX</b><span class="muted">${tree.length} nodes sampled</span></div>
    <div class="step"><b>Resolve</b><span class="muted">${escape(point.field.role)} / ${escape(point.field.detail)}</span></div>
    <div class="step"><b>Type</b><span class="muted"><code>${escape(query)}</code></span></div>
    <div class="step"><b>Verify</b><span class="muted">${escape(finalField?.value || '')}</span></div>
  </section>

  <h2>Resolved Target</h2>
  <section class="grid">
    <div class="card">
      <p><b>Role:</b> <code>${escape(point.field.role)}</code></p>
      <p><b>Detail:</b> <code>${escape(point.field.detail)}</code></p>
      <p><b>AX frame:</b> <code>${Math.round(point.field.frame.x)}, ${Math.round(point.field.frame.y)}, ${Math.round(point.field.frame.width)} x ${Math.round(point.field.frame.height)}</code></p>
      <p><b>Overlay point:</b> <code>${point.overlayPoint.x}, ${point.overlayPoint.y}</code></p>
      <p><b>Verified value:</b> <code>${escape(finalField?.value || '')}</code></p>
    </div>
    <img src="${screenshotPath}" alt="Chrome after AX typing">
  </section>

  <h2>Decision And Action Log</h2>
  <ol class="trace">${traceRows}</ol>

  <h2>AX Tree Excerpt</h2>
  <table>
    <thead><tr><th>Depth</th><th>Role</th><th>Label</th><th>Value</th><th>Frame</th></tr></thead>
    <tbody>${nodeRows}</tbody>
  </table>
</main>`;

fs.writeFileSync(reportPath, html);
console.log(JSON.stringify({ status: 'replay-written', reportPath }, null, 2));
NODE

ls -lh "$POINT_JSON" "$TRACE_LOG" "$OUTPUT_PREFIX-window.png" "$OUTPUT_PREFIX-replay.html"
