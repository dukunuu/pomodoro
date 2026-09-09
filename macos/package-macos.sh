#!/bin/sh
# Zips the built .app for distribution and writes a checksum.
# ditto preserves the bundle's signature and symlinks, which plain zip does not.
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
VERSION=${VERSION:-0.0.0-dev}
ARCH=$(uname -m)
APP="$ROOT/dist/Pomodoro.app"
OUT="$ROOT/dist/Pomodoro-$VERSION-macos-$ARCH.zip"

[ -d "$APP" ] || { echo "no build at $APP; run build-macos.sh first" >&2; exit 1; }

ditto -c -k --keepParent "$APP" "$OUT"
( cd "$ROOT/dist" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

echo "$OUT"
cat "$OUT.sha256"
