#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/CodexMeter.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

export HOME="${HOME:-$ROOT_DIR/.swift-home}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

BUILD_ARGS=(--disable-sandbox -c release)
if [[ -n "${CODEX_METER_SDK:-}" ]]; then
    BUILD_ARGS+=(--sdk "$CODEX_METER_SDK")
fi

cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    "$ROOT_DIR/scripts/generate-app-icon.sh"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BIN_DIR/CodexMeter" "$MACOS_DIR/CodexMeter"
install -m 644 "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS_DIR/Info.plist")"
SIGNING_IDENTITY="${CODEX_METER_SIGNING_IDENTITY:--}"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign \
        --force \
        --sign - \
        --identifier "$BUNDLE_ID" \
        --requirements "=designated => identifier \"$BUNDLE_ID\"" \
        "$APP_DIR"
else
    codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp \
        "$APP_DIR"
fi

echo "Created: $APP_DIR"
