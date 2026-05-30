#!/usr/bin/env bash
# Lattices dev run helper.
#
# Mirrors the Talkie convention: run.sh is the dev build/run entry point,
# while build.sh is for package/release artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NO_LAUNCH=0
EXEC_ONLY=0

usage() {
    cat <<'EOF'
Lattices dev runner

Usage:
  ./run.sh                 Build/install/relaunch the dev app
  ./run.sh Lattices        Build/install/relaunch the dev app
  ./run.sh --no-launch     Build/install dev app, do not launch
  ./run.sh -e              Launch installed dev app only
  ./run.sh --list          List runnable apps
  ./run.sh --where         Show canonical paths and bundle ids

Dev permission target:
  ~/Applications/dev/Lattices/Lattices.app
  dev.lattices.app.dev
EOF
}

apps_to_run=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-launch)
            NO_LAUNCH=1
            ;;
        -e|--exec-only)
            EXEC_ONLY=1
            ;;
        --where|where)
            "$SCRIPT_DIR/bin/lattices-build" where
            exit 0
            ;;
        --list|-l)
            echo "Available apps:"
            echo "  Lattices"
            echo ""
            echo "Dev apps install to: ~/Applications/dev/Lattices"
            exit 0
            ;;
        --help|-h|help)
            usage
            exit 0
            ;;
        Lattices|lattices|app)
            apps_to_run="Lattices"
            ;;
        *)
            echo "Unknown app or option: $1" >&2
            echo "Run './run.sh --list' to see available apps." >&2
            exit 1
            ;;
    esac
    shift
done

apps_to_run="${apps_to_run:-Lattices}"

case "$apps_to_run" in
    Lattices)
        if [ "$EXEC_ONLY" = "1" ]; then
            "$SCRIPT_DIR/bin/lattices-dev" launch
        elif [ "$NO_LAUNCH" = "1" ]; then
            "$SCRIPT_DIR/bin/lattices-build" dev
        else
            "$SCRIPT_DIR/bin/lattices-build" dev:restart
        fi
        ;;
esac
