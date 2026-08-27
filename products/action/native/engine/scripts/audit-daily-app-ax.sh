#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
OUTPUT_DIR="${ACTION_AX_AUDIT_DIR:-/tmp/action-ax-audit-$(date +%Y%m%d-%H%M%S)}"
MAX_DEPTH="${ACTION_AX_AUDIT_MAX_DEPTH:-14}"
MAX_NODES="${ACTION_AX_AUDIT_MAX_NODES:-2500}"

DEFAULT_APPS=(
  "com.google.Chrome:Chrome"
  "com.googlecode.iterm2:iTerm2"
  "com.openai.codex:Codex"
  "com.todesktop.230313mzl4w4u92:Cursor"
)

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  "$SCRIPT_DIR/build-app.sh" >/dev/stderr
fi

mkdir -p "$OUTPUT_DIR"

front_bundle() {
  local asn
  asn=$(lsappinfo front 2>/dev/null | awk '{print $1}' | sed 's/ASN://;s/:$//' || true)
  [[ -n "$asn" ]] || return 0
  lsappinfo info -only bundleid "ASN:$asn" 2>/dev/null \
    | sed -n 's/^"CFBundleIdentifier"="\(.*\)"$/\1/p' \
    | head -1
}

FRONT_BEFORE=$(front_bundle)
printf 'AX daily app audit\n'
printf 'output=%s\n' "$OUTPUT_DIR"
printf 'frontmost.before=%s\n' "${FRONT_BEFORE:-unknown}"

if [[ "$#" -gt 0 ]]; then
  APP_SPECS=("$@")
else
  APP_SPECS=("${DEFAULT_APPS[@]}")
fi

for spec in "${APP_SPECS[@]}"; do
  bundle="${spec%%:*}"
  label="${spec#*:}"
  [[ "$label" != "$bundle" ]] || label="$bundle"
  safe_name=$(printf '%s' "$label" | tr -c '[:alnum:]_.-' '_')
  json_path="$OUTPUT_DIR/$safe_name.json"
  err_path="$OUTPUT_DIR/$safe_name.err"

  printf '\n[%s] inspecting %s\n' "$label" "$bundle"
  if "$APP_EXECUTABLE" inspect-app-ui \
      --bundle-id "$bundle" \
      --max-depth "$MAX_DEPTH" \
      --max-nodes "$MAX_NODES" > "$json_path" 2> "$err_path"; then
    node - "$json_path" "$label" "$bundle" <<'NODE'
const fs = require("fs");
const [jsonPath, label, bundle] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const roleCounts = new Map();
const actionCounts = new Map();
const settableCounts = new Map();
const pressable = [];
const writable = [];
const focusable = [];
const scrollable = [];
const menuLike = [];
const interesting = [];
const textRoles = new Set([
  "AXTextArea",
  "AXTextField",
  "AXSearchField",
  "AXComboBox",
]);

function textOf(node) {
  return [node.title, node.detail, node.value, node.identifier]
    .filter((value) => typeof value === "string" && value.trim())
    .join(" | ")
    .replace(/\s+/g, " ")
    .slice(0, 140);
}

function frameOf(node) {
  if (!node.frame) return "";
  const f = node.frame;
  return `${Math.round(f.x)},${Math.round(f.y)} ${Math.round(f.width)}x${Math.round(f.height)}`;
}

for (const node of nodes) {
  const role = node.role || "unknown";
  roleCounts.set(role, (roleCounts.get(role) || 0) + 1);

  for (const action of node.actions || []) {
    actionCounts.set(action, (actionCounts.get(action) || 0) + 1);
  }
  for (const attribute of node.settableAttributes || []) {
    settableCounts.set(attribute, (settableCounts.get(attribute) || 0) + 1);
  }

  const actions = new Set(node.actions || []);
  const settable = new Set(node.settableAttributes || []);
  const textLike = textRoles.has(role) || /TextArea|TextField|SearchField|ComboBox/i.test(role);
  const summary = {
    role,
    text: textOf(node),
    frame: frameOf(node),
    actions: [...actions],
    settable: [...settable],
  };

  if (actions.has("AXPress")) pressable.push(summary);
  if (textLike && (settable.has("value") || settable.has("selectedText"))) writable.push(summary);
  if (textLike && settable.has("focused")) focusable.push(summary);
  if ([...actions].some((action) => /Scroll/i.test(action))) scrollable.push(summary);
  if (actions.has("AXShowMenu") || role.includes("Menu")) menuLike.push(summary);
  if (
    /Text|Search|Combo|Button|Link|Tab|Menu|Scroll/i.test(role) ||
    actions.has("AXPress") ||
    settable.has("value") ||
    settable.has("selectedText")
  ) {
    interesting.push(summary);
  }
}

const topRoles = [...roleCounts.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, 10)
  .map(([role, count]) => `${role}:${count}`)
  .join(", ");

const topActions = [...actionCounts.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, 8)
  .map(([action, count]) => `${action}:${count}`)
  .join(", ") || "none";

const topSettable = [...settableCounts.entries()]
  .sort((a, b) => b[1] - a[1])
  .map(([attribute, count]) => `${attribute}:${count}`)
  .join(", ") || "none";

function sample(items, limit = 8) {
  return items
    .filter((item) => item.text || item.frame)
    .slice(0, limit)
    .map((item) => `  - ${item.role} ${item.text ? JSON.stringify(item.text) : ""} ${item.frame ? `@ ${item.frame}` : ""}`.trimEnd())
    .join("\n") || "  - none";
}

const namedPressable = pressable.filter((item) => item.text);
let attentionTier = "observe-only";
let recommendation = "Read AX tree safely; no obvious semantic action surface in this sample.";
if (namedPressable.length || writable.length) {
  attentionTier = "background-semantic";
  recommendation = "Prefer AXPress / AXValue / AXSelectedText before any focus or HID fallback.";
} else if (focusable.length) {
  attentionTier = "target-focus-risk";
  recommendation = "May need AXFocused plus postToPid key events; warn that target text focus may change.";
} else if (actionCounts.has("AXRaise")) {
  attentionTier = "attention-risk";
  recommendation = "Likely needs raise/activate or coordinate fallback for meaningful interaction.";
}

const summary = {
  label,
  bundle,
  nodeCount: nodes.length,
  roleCounts: Object.fromEntries([...roleCounts.entries()].sort((a, b) => b[1] - a[1])),
  actionCounts: Object.fromEntries([...actionCounts.entries()].sort((a, b) => b[1] - a[1])),
  settableCounts: Object.fromEntries([...settableCounts.entries()].sort((a, b) => b[1] - a[1])),
  attentionTier,
  recommendation,
  pressableSample: pressable.slice(0, 12),
  writableSample: writable.slice(0, 12),
  focusableSample: focusable.slice(0, 12),
  scrollableSample: scrollable.slice(0, 12),
};

fs.writeFileSync(jsonPath.replace(/\.json$/, ".summary.json"), JSON.stringify(summary, null, 2));

console.log(`  nodes=${nodes.length}`);
console.log(`  topRoles=${topRoles}`);
console.log(`  actions=${topActions}`);
console.log(`  settable=${topSettable}`);
console.log(`  tier=${attentionTier}`);
console.log(`  recommendation=${recommendation}`);
console.log("  pressable:");
console.log(sample(pressable, 5));
console.log("  writable:");
console.log(sample(writable, 5));
NODE
  else
    printf '  unavailable: '
    tr '\n' ' ' < "$err_path"
    printf '\n'
  fi
done

FRONT_AFTER=$(front_bundle)
printf '\nfrontmost.after=%s\n' "${FRONT_AFTER:-unknown}"
if [[ -n "${FRONT_BEFORE:-}" && -n "${FRONT_AFTER:-}" && "$FRONT_BEFORE" != "$FRONT_AFTER" ]]; then
  printf 'warning=frontmost app changed during audit: %s -> %s\n' "$FRONT_BEFORE" "$FRONT_AFTER"
else
  printf 'frontmost.preserved=true\n'
fi
