#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
APP_NAME="$(/usr/bin/plutil -extract app_name raw -o - Resources/UpdateRelease.json)"
TARGET="$(/usr/bin/plutil -extract target raw -o - Resources/UpdateRelease.json)"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { print -u2 'Build the app before running updater checks.'; exit 1; }
mkdir -p .build/clang-module-cache
swiftc -parse-as-library -module-cache-path .build/clang-module-cache \
  -F "$APP_PATH/Contents/Frameworks" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$APP_PATH/Contents/Frameworks" \
  "Sources/$TARGET/AppUpdater.swift" Tests/UpdateTests/UpdateCheck.swift -o .build/update-check
.build/update-check "$APP_PATH" "$@"
