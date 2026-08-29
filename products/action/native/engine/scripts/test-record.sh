#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUTPUT="${2:-/tmp/action-record-$(date +%Y%m%d-%H%M%S).mov}"
STOP_FILE="${OUTPUT}.stop"
FINISHED_FILE="${OUTPUT}.finished"
LOG_FILE="${OUTPUT}.log"
STOP_DELAY="${ACTION_RECORD_SECONDS:-5}"
X="${ACTION_CAPTURE_X:-320}"
Y="${ACTION_CAPTURE_Y:-180}"
WIDTH="${ACTION_CAPTURE_WIDTH:-960}"
HEIGHT="${ACTION_CAPTURE_HEIGHT:-720}"

"$SCRIPT_DIR/build-app.sh" >/dev/null

rm -f "$STOP_FILE"
rm -f "$FINISHED_FILE"
rm -f "$LOG_FILE"

(
  sleep "$STOP_DELAY"
  printf 'stop\n' > "$STOP_FILE"
) &

"$SCRIPT_DIR/run-app-host.sh" record-region --x "$X" --y "$Y" --width "$WIDTH" --height "$HEIGHT" --fps "${ACTION_RECORD_FPS:-15}" --scale "${ACTION_RECORD_SCALE:-0.75}" --output "$OUTPUT" --stop-file "$STOP_FILE" --finished-file "$FINISHED_FILE" --debug-log "$LOG_FILE"

for attempt in {1..200}; do
  if [[ -s "$FINISHED_FILE" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -s "$FINISHED_FILE" ]]; then
  echo "Timed out waiting for recording completion marker: $FINISHED_FILE" >&2
  exit 1
fi

if grep -q '^error:' "$FINISHED_FILE"; then
  cat "$FINISHED_FILE" >&2
  exit 1
fi

rm -f "$STOP_FILE"
ls -lh "$OUTPUT"
echo "finished-marker=$FINISHED_FILE"
echo "debug-log=$LOG_FILE"
