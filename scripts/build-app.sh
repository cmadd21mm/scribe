#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR=${SCRIBE_DIST_DIR:-"$PROJECT_ROOT/dist"}
APP_DIR="$DIST_DIR/Scribe.app"
ICONSET_DIR="$DIST_DIR/Scribe.iconset"
ICON_SOURCE="$PROJECT_ROOT/Assets/Brand/ScribeAppIcon-1024.png"

cd "$PROJECT_ROOT"
if [ "${SCRIBE_UNIVERSAL:-0}" = "1" ]; then
    UNIVERSAL_BUILD_DIR="$PROJECT_ROOT/.build-universal"
    swift build -c release --product scribe \
        --arch arm64 --arch x86_64 \
        --scratch-path "$UNIVERSAL_BUILD_DIR"
    SCRIBE_BINARY="$UNIVERSAL_BUILD_DIR/apple/Products/Release/scribe"
    SPARKLE_ARTIFACTS="$UNIVERSAL_BUILD_DIR/artifacts"
else
    swift build -c release --product scribe
    SCRIBE_BINARY="$PROJECT_ROOT/.build/release/scribe"
    SPARKLE_ARTIFACTS="$PROJECT_ROOT/.build/artifacts"
fi

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks" "$ICONSET_DIR"
cp "$SCRIBE_BINARY" "$APP_DIR/Contents/MacOS/Scribe"
cp "Sources/Scribe/Info.plist" "$APP_DIR/Contents/Info.plist"

SPARKLE_FRAMEWORK="$SPARKLE_ARTIFACTS/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
else
    printf '%s\n' "missing Sparkle.framework at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

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
ENTITLEMENTS="$PROJECT_ROOT/Sources/Scribe/Scribe.entitlements"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    # Ad-hoc local builds have no Team ID, so hardened library validation
    # cannot establish that the app and Sparkle share a signer.
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    # Re-sign Sparkle with our Team ID for hardened library validation, then
    # sign only the host app with Scribe's privacy-sensitive entitlements.
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
codesign -d --entitlements - "$APP_DIR" 2>&1 \
    | grep -q "com.apple.security.device.audio-input"
codesign -d --entitlements - "$APP_DIR" 2>&1 \
    | grep -q "com.apple.security.personal-information.calendars"

printf '%s\n' "$APP_DIR"
