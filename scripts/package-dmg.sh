#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CodexMeter.app"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"

mkdir -p "$ROOT_DIR/.build" "$DIST_DIR"

STAGING_DIR="$(mktemp -d "$ROOT_DIR/.build/codex-meter-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/package-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="$DIST_DIR/CodexMeter-$VERSION.dmg"
TMP_DMG_PATH="$DIST_DIR/.CodexMeter-$VERSION.dmg.tmp.dmg"

ditto "$APP_DIR" "$STAGING_DIR/CodexMeter.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$TMP_DMG_PATH"
hdiutil create \
    -volname "CodexMeter" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$TMP_DMG_PATH"

hdiutil verify "$TMP_DMG_PATH"
mv -f "$TMP_DMG_PATH" "$DMG_PATH"
echo "Created: $DMG_PATH"
