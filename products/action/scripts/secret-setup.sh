#!/bin/zsh

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT_DIR/.env.secrets"
COMMAND="${1:-status}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing secret manifest: $MANIFEST" >&2
  exit 1
fi

manifest_keys() {
  awk '
    { sub(/^[[:space:]]+/, ""); sub(/^export[[:space:]]+/, "") }
    /^[A-Za-z_][A-Za-z0-9_]*=/ { sub(/=.*/, ""); print }
  ' "$MANIFEST" | sort -u
}

check_manifest_coverage() {
  local key missing=0
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    if secret get "$key" >/dev/null 2>&1; then
      printf '  ✓ %s  (in keychain)\n' "$key" >&2
    else
      printf '  · %s  (missing — run: secret set %s)\n' "$key" "$key" >&2
      missing=1
    fi
  done < <(manifest_keys)

  return "$missing"
}

case "$COMMAND" in
  status)
    echo "Action secret manifest: $MANIFEST" >&2
    echo "Required keys:" >&2
    if check_manifest_coverage; then
      exit 0
    fi
    exit 1
    ;;
  setup)
    "$0" status || true
    cat <<EOF

Action secret setup

  Store a missing key once:
    secret set MINIMAX_API_KEY

  Import from a dotenv file instead:
    secret import .env.local
    secret import .env.local --prune

  Run Action commands with secrets injected:
    secret run MINIMAX_API_KEY -- bun run mcp
    secret run MINIMAX_API_KEY -- bun run inspect:surface --vision

EOF
    ;;
  *)
    echo "Usage: scripts/secret-setup.sh [status|setup]" >&2
    exit 1
    ;;
esac