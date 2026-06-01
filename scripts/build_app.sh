#!/bin/zsh
set -euo pipefail

ROOT="/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG"
APP_NAME="FOKSTerminal"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$ROOT/packaging/FOKSTerminal-Info.plist"
RELEASE_BIN="$ROOT/.build/release/$APP_NAME"

if ! command -v swift >/dev/null 2>&1; then
  echo "FAIL swift not found"
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "FAIL missing $INFO_PLIST"
  exit 1
fi

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$RELEASE_BIN" "$MACOS/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
chmod +x "$MACOS/$APP_NAME"

echo "PASS built $APP"
