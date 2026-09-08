#!/usr/bin/env bash
# Install the desktop build for a Linux user who is not running Omarchy.
#
# Omarchy users do not need this: the timer runs in the bar as a Quickshell
# plugin, installed with tools/sync-omarchy-plugin.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build-linux}"
PREFIX="${PREFIX:-$HOME/.local}"

[[ -x "$BUILD/pomodoro" ]] || {
  echo "No build found at $BUILD. Run:" >&2
  echo "  cmake -S \"$ROOT\" -B \"$BUILD\" -DCMAKE_BUILD_TYPE=Release && cmake --build \"$BUILD\"" >&2
  exit 1
}

install -Dm755 "$BUILD/pomodoro" "$PREFIX/bin/pomodoro"
install -Dm644 "$ROOT/assets/pomodoro.svg" "$PREFIX/share/icons/hicolor/scalable/apps/pomodoro.svg"
install -Dm644 "$ROOT/packaging/linux/pomodoro.desktop" "$PREFIX/share/applications/pomodoro.desktop"

# The bridges are looked up beside the executable.
install -d "$PREFIX/bin/scripts"
install -m644 "$ROOT"/scripts/*.py "$PREFIX/bin/scripts/"
chmod +x "$PREFIX/bin/scripts/pomodoro_integrations.py" \
         "$PREFIX/bin/scripts/pomodoro_google_auth.py" \
         "$PREFIX/bin/scripts/pomodoro_whistler_setup.py" \
         "$PREFIX/bin/scripts/pomodoro_whistler_import.py"

echo "Installed to $PREFIX. Verify with: pomodoro --diagnose"
