#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUTPUT="${2:-/tmp/action-screenshot-$(date +%Y%m%d-%H%M%S).png}"
X="${ACTION_CAPTURE_X:-320}"
Y="${ACTION_CAPTURE_Y:-180}"
WIDTH="${ACTION_CAPTURE_WIDTH:-960}"
HEIGHT="${ACTION_CAPTURE_HEIGHT:-720}"

"$SCRIPT_DIR/run-app-host.sh" screenshot-region --x "$X" --y "$Y" --width "$WIDTH" --height "$HEIGHT" --output "$OUTPUT"
ls -lh "$OUTPUT"
