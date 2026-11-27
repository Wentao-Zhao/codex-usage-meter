#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
source scripts/sparkle-paths.sh
APP_NAME="$(/usr/bin/plutil -extract app_name raw -o - Resources/UpdateRelease.json)"
REPOSITORY="$(/usr/bin/plutil -extract repository raw -o - Resources/UpdateRelease.json)"
KEY_ACCOUNT="$(/usr/bin/plutil -extract key_account raw -o - Resources/UpdateRelease.json)"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
typeset -a archives=("$ROOT_DIR/dist/$APP_NAME-$VERSION"*.dmg(N))
[[ ${#archives[@]} -eq 1 ]] || { print -u2 'Expected exactly one DMG for the current version.'; exit 1; }
DMG="${archives[1]}"
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")" == "$VERSION" ]] || exit 1
/usr/bin/cmp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
zsh "$ROOT_DIR/scripts/verify-dmg.sh" "$DMG"
mkdir -p .build/clang-module-cache
swiftc -module-cache-path .build/clang-module-cache scripts/verify-update.swift -o .build/verify-update
python3 scripts/generate-appcast.py --app "$APP_PATH" --dmg "$DMG" \
  --repo "$REPOSITORY" --key-account "$KEY_ACCOUNT" \
  --sign-tool "$SPARKLE_TOOL_DIR/sign_update" --verify-tool "$ROOT_DIR/.build/verify-update" \
  --output "$ROOT_DIR/dist/appcast.xml"
"$SPARKLE_TOOL_DIR/sign_update" --account "$KEY_ACCOUNT" "$ROOT_DIR/dist/appcast.xml"
"$SPARKLE_TOOL_DIR/sign_update" --account "$KEY_ACCOUNT" --verify "$ROOT_DIR/dist/appcast.xml"
(cd dist && /usr/bin/shasum -a 256 "${DMG:t}" appcast.xml > SHA256SUMS)
print -r -- "Prepared signed update: $DMG"
