#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUTPUT_PREFIX="${1:-/tmp/action-chrome-google-search-cdp-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_PREFIX="${OUTPUT_PREFIX%.png}"
QUERY="${ACTION_CHROME_CDP_QUERY:-action google search box demo}"
PORT="${ACTION_CHROME_CDP_PORT:-9222}"
PROFILE_DIR="${ACTION_CHROME_CDP_PROFILE:-/tmp/action-chrome-cdp-profile}"
TRACE_LOG="$OUTPUT_PREFIX-trace.log"
POINT_JSON="$OUTPUT_PREFIX-point.json"
VERIFY_JSON="$OUTPUT_PREFIX-verify.json"
SCREEN_PROBE="$OUTPUT_PREFIX-screen.png"

rm -f "$TRACE_LOG"
rm -rf "$PROFILE_DIR"

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

log_event "open" "Launch Chrome with CDP on port $PORT"
status_overlay "Open Chrome" 900 "CDP page control" &
open -na "Google Chrome" --args \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$PROFILE_DIR" \
  --new-window "https://www.google.com"

sleep 2.0
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen --output "$SCREEN_PROBE" >/dev/null

log_event "observe" "Resolve Google page search textarea via CDP DOM"
status_overlay "Inspect DOM" 900 "textarea[name=q]" &

node - "$PORT" "$SCREEN_PROBE" "$POINT_JSON" <<'NODE'
const fs = require('fs');
const { execFileSync } = require('child_process');
const [port, screenPath, pointPath] = process.argv.slice(2);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} -> ${response.status}`);
  return response.json();
}

async function getPage() {
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      const pages = await fetchJson(`http://127.0.0.1:${port}/json`);
      const page = pages.find((entry) => entry.type === 'page' && entry.webSocketDebuggerUrl);
      if (page) return page;
    } catch {}
    await sleep(150);
  }
  throw new Error('Could not find a CDP page target');
}

async function main() {
  const page = await getPage();
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let nextId = 1;
  const pending = new Map();
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
    }
  });
  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve, { once: true });
    ws.addEventListener('error', reject, { once: true });
  });
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });

  await call('Page.enable');
  await call('Runtime.enable');
  await call('Page.bringToFront');

  for (let attempt = 0; attempt < 60; attempt++) {
    const ready = await call('Runtime.evaluate', {
      expression: `Boolean(document.querySelector('textarea[name=q], input[name=q]'))`,
      returnByValue: true,
    });
    if (ready.result.value) break;
    await sleep(100);
  }

  const result = await call('Runtime.evaluate', {
    expression: `(() => {
      const el = document.querySelector('textarea[name=q], input[name=q]');
      if (!el) return null;
      el.focus();
      el.value = '';
      el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'deleteContentBackward', data: null }));
      const r = el.getBoundingClientRect();
      return {
        selector: el.tagName.toLowerCase() + '[name=' + el.getAttribute('name') + ']',
        placeholder: el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('placeholder') || '',
        rect: { left: r.left, top: r.top, width: r.width, height: r.height },
        screenX: window.screenX,
        screenY: window.screenY,
        outerWidth: window.outerWidth,
        outerHeight: window.outerHeight,
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        devicePixelRatio: window.devicePixelRatio,
      };
    })()`,
    returnByValue: true,
  });
  const info = result.result.value;
  if (!info) throw new Error('Google search input not found in page DOM');

  const sips = execFileSync('/usr/bin/sips', ['-g', 'pixelHeight', screenPath], { encoding: 'utf8' });
  const match = sips.match(/pixelHeight:\s*(\d+)/);
  const screenHeight = match ? Number(match[1]) : 1440;
  const viewportLeft = info.screenX + Math.max(0, (info.outerWidth - info.innerWidth) / 2);
  const viewportTop = info.screenY + Math.max(0, info.outerHeight - info.innerHeight);
  const x = Math.round(viewportLeft + info.rect.left + info.rect.width / 2);
  const yTop = Math.round(viewportTop + info.rect.top + info.rect.height / 2);
  const y = Math.round(screenHeight - yTop);

  fs.writeFileSync(pointPath, JSON.stringify({
    page,
    target: info,
    overlayPoint: { x, y },
    screenPointTopLeft: { x, y: yTop },
    screenHeight,
  }, null, 2));
  ws.close();
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
NODE

TARGET_X=$(node -e "console.log(require('$POINT_JSON').overlayPoint.x)")
TARGET_Y=$(node -e "console.log(require('$POINT_JSON').overlayPoint.y)")
TARGET_DETAIL=$(node -e "const p=require('$POINT_JSON'); const r=p.target.rect; console.log(p.target.selector+' '+Math.round(r.width)+'x'+Math.round(r.height))")

log_event "resolve" "Resolved page input: $TARGET_DETAIL"
status_overlay "Resolved DOM" 950 "$TARGET_DETAIL" &
sleep 0.85

log_event "act" "Show click at Google search box $TARGET_X,$TARGET_Y"
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 950 \
  --start-x 3060 \
  --start-y 1160 \
  --end-x "$TARGET_X" \
  --end-y "$TARGET_Y" \
  --click-progress 0.70 \
  --status-detail "search box $TARGET_X,$TARGET_Y" \
  --trace-file "$TRACE_LOG" \
  --trace-title "Action decisions" \
  --label Click >/dev/null

sleep 0.95
log_event "act" "Type query into Google page search box via CDP"
"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 2100 \
  --start-x "$TARGET_X" \
  --start-y "$TARGET_Y" \
  --end-x "$TARGET_X" \
  --end-y "$TARGET_Y" \
  --click-progress 0.50 \
  --label Typing \
  --status-detail "CDP Input.insertText" \
  --typing-text "$QUERY" \
  --typing-sound timed \
  --trace-file "$TRACE_LOG" \
  --trace-title "Action decisions" >/dev/null &

sleep 0.25
node - "$PORT" "$QUERY" "$VERIFY_JSON" <<'NODE'
const fs = require('fs');
const [port, query, verifyPath] = process.argv.slice(2);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} -> ${response.status}`);
  return response.json();
}

async function main() {
  const pages = await fetchJson(`http://127.0.0.1:${port}/json`);
  const page = pages.find((entry) => entry.type === 'page' && entry.webSocketDebuggerUrl);
  if (!page) throw new Error('No CDP page target');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let nextId = 1;
  const pending = new Map();
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
    }
  });
  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve, { once: true });
    ws.addEventListener('error', reject, { once: true });
  });
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
  await call('Runtime.evaluate', {
    expression: `(() => {
      const el = document.querySelector('textarea[name=q], input[name=q]');
      el.focus();
      el.value = '';
      el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'deleteContentBackward', data: null }));
      return true;
    })()`,
    returnByValue: true,
  });
  for (const ch of Array.from(query)) {
    await call('Input.insertText', { text: ch });
    await sleep(18);
  }
  const result = await call('Runtime.evaluate', {
    expression: `document.querySelector('textarea[name=q], input[name=q]')?.value || ''`,
    returnByValue: true,
  });
  fs.writeFileSync(verifyPath, JSON.stringify({ value: result.result.value }, null, 2));
  ws.close();
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
NODE
wait

VALUE=$(node -e "console.log(require('$VERIFY_JSON').value)")
if [[ "$VALUE" != "$QUERY" ]]; then
  echo "Expected page search value '$QUERY', got '$VALUE'" >&2
  exit 1
fi

log_event "verify" "DOM value matched: $VALUE"
status_overlay "Verify DOM" 900 "search box value matched" &
sleep 0.4

"$SCRIPT_DIR/run-app-host.sh" screenshot-app-window \
  --bundle-id com.google.Chrome \
  --output "$OUTPUT_PREFIX-window.png" >/dev/null

node - "$POINT_JSON" "$VERIFY_JSON" "$TRACE_LOG" "$OUTPUT_PREFIX-window.png" "$OUTPUT_PREFIX-replay.html" <<'NODE'
const fs = require('fs');
const [pointPath, verifyPath, tracePath, screenshotPath, reportPath] = process.argv.slice(2);
const point = JSON.parse(fs.readFileSync(pointPath, 'utf8'));
const verify = JSON.parse(fs.readFileSync(verifyPath, 'utf8'));
const traceLines = fs.readFileSync(tracePath, 'utf8').trim().split(/\n+/).filter(Boolean);
const escape = (value) => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const traceRows = traceLines.map((line) => {
  const [kind, ...rest] = line.split('|');
  return `<li><b>${escape(kind || 'event')}</b><span>${escape(rest.join('|') || line)}</span></li>`;
}).join('');
const r = point.target.rect;
const html = `<!doctype html>
<meta charset="utf-8">
<title>Action Google Search Box CDP Replay</title>
<style>
body{margin:0;background:#101417;color:#eef0eb;font:14px ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1160px;margin:0 auto;padding:28px}
h1{font-size:24px;margin:0 0 6px} h2{font-size:15px;margin:28px 0 10px;color:#d8d1bd}
.muted{color:#8f989b}.grid{display:grid;grid-template-columns:360px 1fr;gap:22px;align-items:start}
.card{border:1px solid rgba(255,255,255,.08);background:rgba(255,255,255,.045);border-radius:8px;padding:16px}
code{color:#e8d7a7}.trace{list-style:none;margin:0;padding:0;border:1px solid rgba(255,255,255,.08);border-radius:8px;overflow:hidden}
.trace li{display:grid;grid-template-columns:84px 1fr;gap:12px;padding:9px 12px;border-bottom:1px solid rgba(255,255,255,.06);background:rgba(255,255,255,.035)}
.trace li:last-child{border-bottom:0}.trace b{color:#d8d1bd;font-size:12px;text-transform:uppercase;letter-spacing:.04em}.trace span{color:#e7e9e4;font-size:13px}
img{width:100%;border-radius:8px;border:1px solid rgba(255,255,255,.08);display:block}
</style>
<main>
<h1>Chrome Google Search Box Replay</h1>
<div class="muted">Action resolved the real page search input via Chrome DevTools Protocol, placed the overlay from its DOM rect, typed via CDP, then verified the DOM value.</div>
<h2>Resolved Target</h2>
<section class="grid"><div class="card">
<p><b>Selector:</b> <code>${escape(point.target.selector)}</code></p>
<p><b>Label:</b> <code>${escape(point.target.placeholder)}</code></p>
<p><b>DOM rect:</b> <code>${Math.round(r.left)}, ${Math.round(r.top)}, ${Math.round(r.width)} x ${Math.round(r.height)}</code></p>
<p><b>Overlay point:</b> <code>${point.overlayPoint.x}, ${point.overlayPoint.y}</code></p>
<p><b>Verified value:</b> <code>${escape(verify.value)}</code></p>
</div><img src="${screenshotPath}" alt="Chrome Google search box after CDP typing"></section>
<h2>Decision And Action Log</h2><ol class="trace">${traceRows}</ol>
</main>`;
fs.writeFileSync(reportPath, html);
console.log(JSON.stringify({ status: 'replay-written', reportPath }, null, 2));
NODE

ls -lh "$POINT_JSON" "$VERIFY_JSON" "$TRACE_LOG" "$OUTPUT_PREFIX-window.png" "$OUTPUT_PREFIX-replay.html"
