#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR=${SCRIBE_DIST_DIR:-"$PROJECT_ROOT/dist"}
DMG_PATH=${1:-"$DIST_DIR/Scribe.dmg"}
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Sources/Scribe/Info.plist")
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

if [ ! -f "$DMG_PATH" ]; then
    printf '%s\n' "missing update archive: $DMG_PATH" >&2
    exit 1
fi

cp "$DMG_PATH" "$WORK_DIR/Scribe-$VERSION.dmg"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/cmadd21mm/scribe/releases/download/v$VERSION/" \
    "$WORK_DIR"
cp "$WORK_DIR/appcast.xml" "$DIST_DIR/appcast.xml"
printf '%s\n' "$DIST_DIR/appcast.xml"
