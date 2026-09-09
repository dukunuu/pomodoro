#!/bin/sh
# Builds the native macOS front end and assembles a real .app bundle.
#
# SwiftPM produces a bare executable; macOS needs the bundle for the Dock
# icon, Notification Center registration, and Launch Services. Nothing here
# requires a full Xcode install — the Command Line Tools are enough.
#
# Environment:
#   VERSION                     marketing version (default 0.0.0-dev)
#   BUILD_NUMBER                CFBundleVersion (default: git commit count)
#   CONFIG                      debug | release (default release)
#   GOOGLE_OAUTH_CLIENT_JSON    OAuth client JSON, inline; baked into the app
#   GOOGLE_OAUTH_CLIENT_FILE    ...or a path to the same JSON
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$ROOT/.." && pwd)
CONFIG=${CONFIG:-release}
VERSION=${VERSION:-0.0.0-dev}
APP="$ROOT/dist/Pomodoro.app"

if [ -n "${BUILD_NUMBER:-}" ]; then
    BUILD=$BUILD_NUMBER
elif git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    BUILD=$(git -C "$REPO" rev-list --count HEAD)
else
    BUILD=1
fi

echo "==> Building ($CONFIG, version $VERSION build $BUILD)"
cd "$ROOT"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/scripts"
cp "$BIN/Pomodoro" "$APP/Contents/MacOS/Pomodoro"

# The Python bridges hold all the Google and Whistler protocol work.
cp "$REPO/scripts"/*.py "$APP/Contents/Resources/scripts/"

# Bake in the OAuth client when one is supplied, so a release can be
# authorized without every user creating their own Google Cloud project.
# pomodoro_paths.py and DataPaths.existingGoogleClient() both prefer a
# per-user copy and fall back to this bundled one.
CLIENT_DEST="$APP/Contents/Resources/scripts/google-calendar-client.json"
if [ -n "${GOOGLE_OAUTH_CLIENT_JSON:-}" ]; then
    printf '%s' "$GOOGLE_OAUTH_CLIENT_JSON" > "$CLIENT_DEST"
elif [ -n "${GOOGLE_OAUTH_CLIENT_FILE:-}" ]; then
    cp "$GOOGLE_OAUTH_CLIENT_FILE" "$CLIENT_DEST"
fi
if [ -f "$CLIENT_DEST" ]; then
    if python3 -c "
import json, sys
data = json.load(open('$CLIENT_DEST'))
client = data.get('installed') or data.get('web')
assert isinstance(client, dict), 'no installed/web section'
assert client.get('client_id'), 'no client_id'
" 2>/dev/null; then
        chmod 600 "$CLIENT_DEST"
        echo "    baked in OAuth client"
    else
        echo "    ERROR: supplied OAuth client JSON is not a valid Desktop client" >&2
        exit 1
    fi
else
    echo "    no OAuth client supplied; users install their own in Settings"
fi

echo "==> Rendering icon"
ICONSET=$(mktemp -d)/Pomodoro.iconset
if swift "$ROOT/Tools/make-icon.swift" "$REPO/assets/pomodoro.svg" "$ICONSET" 2>/dev/null; then
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Pomodoro.icns"
else
    echo "    icon render failed; bundle will use the generic icon"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Pomodoro</string>
    <key>CFBundleDisplayName</key>       <string>Pomodoro</string>
    <key>CFBundleExecutable</key>        <string>Pomodoro</string>
    <key>CFBundleIdentifier</key>        <string>com.dukunuu.pomodoro</string>
    <key>CFBundleIconFile</key>          <string>Pomodoro</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
    <key>NSHumanReadableCopyright</key>  <string>Pomodoro</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signing is enough for local use and keeps Notification Center and
# the floating panel behaving like a normal app. A real Developer ID is used
# instead when one is available (see .github/workflows/release.yml).
echo "==> Signing"
if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$MACOS_SIGN_IDENTITY" "$APP"
    echo "    signed with $MACOS_SIGN_IDENTITY"
else
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
        || echo "    ad-hoc signing failed; the app still runs"
    echo "    ad-hoc (unsigned for distribution)"
fi

echo
echo "Built $APP"
echo "Run it with:  open '$APP'"
