#!/bin/bash
# Distributable artifacts only; local development signing remains product-owned.
set -euo pipefail
POLICY="$(cd "$(dirname "$0")" && pwd)/companion-signing.json"
TEAM="$(/usr/bin/plutil -extract teamID raw -o - "$POLICY")"
OID="$(/usr/bin/plutil -extract developerIDLeafOID raw -o - "$POLICY")"
/usr/bin/codesign --verify --deep --strict -R "=anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\" and certificate leaf[field.$OID] exists" "$1"
