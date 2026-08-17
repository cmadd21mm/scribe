#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR=${SCRIBE_DIST_DIR:-"$PROJECT_ROOT/dist"}
STAGING_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/Scribe.dmg"

"$PROJECT_ROOT/scripts/build-app.sh"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$DIST_DIR/Scribe.app" "$STAGING_DIR/Scribe.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "Scribe" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING_DIR"

if [ -n "${APPLE_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
fi

printf '%s\n' "$DMG_PATH"
