#!/bin/zsh
set -euo pipefail

ROOT="/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG"

if ! command -v swift >/dev/null 2>&1; then
  echo "FAIL swift not found"
  exit 1
fi

if [[ ! -f "$ROOT/config/projects.json" ]]; then
  echo "FAIL missing $ROOT/config/projects.json"
  exit 1
fi

cd "$ROOT"

swift build
echo "PASS swift build"

swift test
echo "PASS swift test"
