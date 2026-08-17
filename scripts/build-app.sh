#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR=${SCRIBE_DIST_DIR:-"$PROJECT_ROOT/dist"}
APP_DIR="$DIST_DIR/Scribe.app"
ICONSET_DIR="$DIST_DIR/Scribe.iconset"
ICON_SOURCE="$PROJECT_ROOT/Assets/Brand/ScribeAppIcon-1024.png"

cd "$PROJECT_ROOT"
swift build -c release --product scribe

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"
cp ".build/release/scribe" "$APP_DIR/Contents/MacOS/Scribe"
cp "Sources/quill/Info.plist" "$APP_DIR/Contents/Info.plist"

make_icon() {
    size=$1
    name=$2
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/Scribe.icns"
rm -rf "$ICONSET_DIR"

SIGNING_IDENTITY=${APPLE_SIGNING_IDENTITY:--}
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

printf '%s\n' "$APP_DIR"
