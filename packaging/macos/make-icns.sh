#!/usr/bin/env bash
# Build a macOS .icns from the shared SVG application icon.
#
# Run automatically by the CMake build on macOS. Uses only the tools that ship
# with macOS plus one rasterizer; qlmanage is present on every Mac, so no
# Homebrew dependency is required for a plain build.
set -euo pipefail

SVG="${1:?usage: make-icns.sh <input.svg> <output.icns>}"
OUT="${2:?usage: make-icns.sh <input.svg> <output.icns>}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/pomodoro.iconset"
mkdir -p "$ICONSET"

# Rasterize one PNG at the requested pixel size.
render() {
  local size="$1" target="$2"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$target"
  elif command -v magick >/dev/null 2>&1; then
    magick -background none -density 512 "$SVG" -resize "${size}x${size}" "$target"
  elif command -v qlmanage >/dev/null 2>&1; then
    # Preview's thumbnailer renders at a fixed size, then sips rescales.
    qlmanage -t -s "$size" -o "$WORK" "$SVG" >/dev/null 2>&1
    mv "$WORK/$(basename "$SVG").png" "$target"
    sips -z "$size" "$size" "$target" >/dev/null
  else
    echo "make-icns.sh: no SVG rasterizer found (rsvg-convert, magick, or qlmanage)" >&2
    exit 1
  fi
}

for size in 16 32 128 256 512; do
  render "$size" "$ICONSET/icon_${size}x${size}.png"
  render "$((size * 2))" "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil --convert icns --output "$OUT" "$ICONSET"
echo "make-icns.sh: wrote $OUT"
