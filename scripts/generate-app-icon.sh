#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${CODEX_METER_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
GENERATOR="$ROOT_DIR/.build/generate-app-icon"

mkdir -p "$ROOT_DIR/.build/clang-module-cache" "$ROOT_DIR/Resources"

swiftc \
    -sdk "$SDK" \
    -module-cache-path "$ROOT_DIR/.build/clang-module-cache" \
    "$ROOT_DIR/scripts/generate-app-icon.swift" \
    -o "$GENERATOR"

"$GENERATOR"

echo "Created: $ROOT_DIR/Resources/AppIcon.icns"
