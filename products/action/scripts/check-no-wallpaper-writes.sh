#!/bin/zsh

# Action composites on top of the screen. It does not mutate persistent user state to
# get a visual effect.
#
# The desktop picture is the sharp edge of that rule. A staging script set the wallpaper
# to a near-black backdrop for a clean recording background, wrote a snapshot meant to
# restore it, and the snapshot pointed at a path that did not exist. The original was
# unrecoverable — there is no undo for a wallpaper, and a crash between set and restore
# leaves the operator worse off with no signal about what changed.
#
# A drape is the supported alternative: an overlay window that goes up and comes back
# down, and that the runtime tears down even on abnormal exit. See action.stage.set.
#
# This guard is deliberately about mutation verbs, not the word "wallpaper" — prose,
# comments, and incident notes that discuss wallpapers are fine and should stay greppable.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SELF_PATH="scripts/${0:t}"

cd "$ROOT_DIR"

# Each entry is "<regex>|<why it is banned>".
typeset -a PATTERNS
PATTERNS=(
  'set +picture +of|AppleScript desktop picture write'
  'set +desktop +picture|AppleScript desktop picture write'
  'setDesktopImageURL|NSWorkspace desktop image write'
  'defaults +write +com\.apple\.desktop|defaults write to the desktop picture domain'
  'desktoppicture\.db|direct write to the desktop picture database'
  'com\.apple\.wallpaper/Store|direct write to the wallpaper store'
)

typeset -i failed=0

for entry in "${PATTERNS[@]}"; do
  pattern="${entry%%|*}"
  reason="${entry#*|}"

  # git ls-files keeps this to tracked sources, which excludes node_modules, .build,
  # and native/dist without needing to enumerate them here.
  matches=$(git ls-files -z \
    | xargs -0 grep -nIE -- "$pattern" 2>/dev/null \
    | grep -v "^${SELF_PATH}:" \
    || true)

  if [[ -n "$matches" ]]; then
    failed=1
    print -r -- "Blocked: $reason"
    print -r -- "$matches" | sed 's/^/  /'
    print -r -- ""
  fi
done

if (( failed )); then
  print -r -- "Action must not modify the desktop wallpaper."
  print -r -- "Use a drape instead: an overlay window dismissed on teardown and on abnormal exit."
  exit 1
fi

print -r -- "ok: no desktop wallpaper writes"
