#!/bin/bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${ACTION_BUN_BIN:-}" ]]; then
  BUN_BIN="${ACTION_BUN_BIN}"
  if [[ "${BUN_BIN}" != /* ]]; then
    BUN_BIN="$(command -v "${BUN_BIN}" || true)"
  fi
elif command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
else
  BUN_BIN=""
  for candidate in "${HOME}/.bun/bin/bun" /opt/homebrew/bin/bun /usr/local/bin/bun; do
    if [[ -f "$candidate" && -x "$candidate" ]]; then
      BUN_BIN="$candidate"
      break
    fi
  done
fi

if [[ "${BUN_BIN}" != /* || ! -f "${BUN_BIN}" || ! -x "${BUN_BIN}" ]]; then
  echo "Action Browser requires Bun. Set ACTION_BUN_BIN to its absolute executable path, or install Bun and reload your agent." >&2
  exit 1
fi

exec "${BUN_BIN}" "${PLUGIN_ROOT}/server/index.ts"
