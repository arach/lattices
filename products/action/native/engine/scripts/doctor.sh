#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

"$SCRIPT_DIR/build-app.sh" >/dev/null
"$SCRIPT_DIR/verify-app.sh"
"$SCRIPT_DIR/run-app-host.sh" status
"$SCRIPT_DIR/../../../scripts/secret-setup.sh" status
