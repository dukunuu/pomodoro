#!/bin/sh
# Builds a distributable DMG from the assembled .app and writes a checksum.
#
# The disk image carries the app plus a symlink to /Applications, which is the
# drag-to-install convention users expect on macOS.
#
# Environment:
#   VERSION   marketing version, used in the file and volume name
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
# Same default as build-macos.sh: the latest tag, suffixed when ahead of it.
if [ -z "${VERSION:-}" ]; then
    TAG=$(git -C "$(dirname "$0")" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
    if [ -n "$TAG" ]; then
        AHEAD=$(git -C "$(dirname "$0")" rev-list --count "$TAG..HEAD")
        VERSION=${TAG#v}
        [ "$AHEAD" -gt 0 ] && VERSION="$VERSION-dev.$AHEAD"
    else
        VERSION=0.0.0-dev
    fi
fi
export VERSION
APP="$ROOT/dist/Pomodoro.app"

[ -d "$APP" ] || { echo "no build at $APP; run build-macos.sh first" >&2; exit 1; }

# Name the artifact after what it actually runs on.
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Pomodoro")
case "$ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) SLICE=universal ;;
    *) SLICE=$ARCHS ;;
esac

NAME="Pomodoro-$VERSION-macos-$SLICE"
DMG="$ROOT/dist/$NAME.dmg"
STAGE=$(mktemp -d)/Pomodoro
trap 'rm -rf "$(dirname "$STAGE")"' EXIT

mkdir -p "$STAGE"
# ditto rather than cp -R: it preserves the bundle's signature and metadata.
ditto "$APP" "$STAGE/Pomodoro.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "Pomodoro $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    "$DMG"

( cd "$ROOT/dist" && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256" )

echo "$DMG"
echo "    slices: $ARCHS"
echo "    $(du -h "$DMG" | cut -f1)"
cat "$DMG.sha256"
