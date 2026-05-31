#!/bin/zsh
set -euo pipefail

ROOT="/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG"

if ! command -v swift >/dev/null 2>&1; then
  echo "FAIL swift not found"
  exit 1
fi

cd "$ROOT"
swift build
echo "PASS FOKSTerminal builds"
