#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
swift build --disable-sandbox --target CodexMeterCore
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
if [[ -f "$BIN_DIR/CodexMeterCore.o" ]]; then
    OBJECTS=("$BIN_DIR/CodexMeterCore.o")
    MODULE_DIR="$BIN_DIR"
else
    OBJECTS=("$BIN_DIR"/CodexMeterCore.build/*.swift.o)
    MODULE_DIR="$BIN_DIR/Modules"
fi
xcrun swiftc \
    -I "$MODULE_DIR" \
    "${OBJECTS[@]}" \
    Sources/CodexMeter/CodexAppServerClient.swift \
    Tests/CodexMeterAccountTests/AccountConnectionCheck.swift \
    -o "$ROOT_DIR/.build/account-connection-check"
"$ROOT_DIR/.build/account-connection-check" "$@"
