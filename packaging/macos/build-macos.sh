#!/usr/bin/env bash
# Build, deploy, and optionally package Pomodoro.app on macOS.
#
#   ./packaging/macos/build-macos.sh              # build + macdeployqt
#   ./packaging/macos/build-macos.sh --dmg        # ...and produce a .dmg
#   ./packaging/macos/build-macos.sh --install    # ...and copy to /Applications
#
# Requirements: Xcode command line tools, CMake, and Qt 6.5+ for macOS.
# Point QT_ROOT at the Qt kit if it is not in a standard location, e.g.
#   QT_ROOT=~/Qt/6.8.1/macos ./packaging/macos/build-macos.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/build-macos"
APP="$BUILD/Pomodoro.app"
MAKE_DMG=0
INSTALL=0

for argument in "$@"; do
  case "$argument" in
    --dmg) MAKE_DMG=1 ;;
    --install) INSTALL=1 ;;
    --clean) rm -rf "$BUILD" ;;
    *) echo "unknown option: $argument" >&2; exit 2 ;;
  esac
done

# Locate a Qt kit. An explicit QT_ROOT wins; otherwise try the Homebrew and
# online-installer layouts before falling back to whatever qmake is on PATH.
if [[ -z "${QT_ROOT:-}" ]]; then
  for candidate in \
    "$HOME"/Qt/6.*/macos \
    /opt/homebrew/opt/qt6 \
    /opt/homebrew/opt/qt \
    /usr/local/opt/qt6
  do
    if [[ -d "$candidate" ]]; then QT_ROOT="$candidate"; break; fi
  done
fi
if [[ -z "${QT_ROOT:-}" ]] && command -v qmake6 >/dev/null 2>&1; then
  QT_ROOT="$(qmake6 -query QT_INSTALL_PREFIX)"
fi
if [[ -z "${QT_ROOT:-}" ]]; then
  echo "Qt 6 not found. Install it (brew install qt) or set QT_ROOT." >&2
  exit 1
fi
echo "==> Qt: $QT_ROOT"

cmake -S "$ROOT" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_ROOT"
cmake --build "$BUILD" --parallel

[[ -d "$APP" ]] || { echo "build did not produce $APP" >&2; exit 1; }

# Bundle Qt itself, including the QML modules, so the .app runs on a Mac that
# has no Qt installed.
"$QT_ROOT/bin/macdeployqt" "$APP" -qmldir="$ROOT/core/qml" -qmldir="$ROOT/platform/desktop/qml"

# An unsigned bundle is quarantined on download and Gatekeeper refuses to open
# it. An ad-hoc signature is enough for a locally built app.
codesign --force --deep --sign - "$APP"
echo "==> built $APP"

if [[ "$MAKE_DMG" == "1" ]]; then
  DMG="$BUILD/Pomodoro.dmg"
  rm -f "$DMG"
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname Pomodoro -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  echo "==> packaged $DMG"
fi

if [[ "$INSTALL" == "1" ]]; then
  rm -rf /Applications/Pomodoro.app
  cp -R "$APP" /Applications/
  echo "==> installed /Applications/Pomodoro.app"
  echo "    Python 3 is required for the Google Calendar and Whistler bridges:"
  echo "    xcode-select --install"
fi
