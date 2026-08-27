#!/bin/bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
elif [[ -x "${HOME}/.bun/bin/bun" ]]; then
  BUN_BIN="${HOME}/.bun/bin/bun"
else
  echo "Action Browser requires Bun. Install it from https://bun.sh, then reload or restart your agent." >&2
  exit 1
fi

exec "${BUN_BIN}" "${PLUGIN_ROOT}/server/index.ts"
