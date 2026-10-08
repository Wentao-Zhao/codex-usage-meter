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
    Sources/CodexMeter/UsagePopoverController.swift \
    Sources/CodexMeter/TokenCompositionBarView.swift \
    Sources/CodexMeter/StatusDotIcon.swift \
    Sources/CodexMeter/ComparisonLineChartView.swift \
    Sources/CodexMeter/GroupedBarChartView.swift \
    Tests/CodexMeterUITests/QuotaLayoutCheck.swift \
    -o "$ROOT_DIR/.build/quota-layout-check"
"$ROOT_DIR/.build/quota-layout-check" "$@"
