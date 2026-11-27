#!/bin/zsh
set -euo pipefail

# Usage: zsh scripts/embed-sparkle.sh APP_DIR BIN_DIR SIGNING_IDENTITY
# Invoke after assembling the app, before signing its outer bundle.
# https://sparkle-project.org/documentation/sandboxing/#code-signing
ROOT_DIR="${0:A:h:h}"

fail() {
  print -u2 -r -- "embed-sparkle: $*"
  exit 1
}

[[ $# -eq 3 ]] || fail "usage: $0 APP_DIR BIN_DIR SIGNING_IDENTITY"
APP_DIR="${1:A}"
BIN_DIR="${2:A}"
SIGNING_IDENTITY="$3"
[[ -n "$SIGNING_IDENTITY" ]] || fail "SIGNING_IDENTITY must not be empty"
[[ -d "$APP_DIR/Contents" ]] || fail "app Contents directory is missing: $APP_DIR"
[[ -d "$BIN_DIR" ]] || fail "binary directory is missing: $BIN_DIR"

SOURCE_FRAMEWORK="$BIN_DIR/Sparkle.framework"
if [[ ! -d "$SOURCE_FRAMEWORK" ]]; then
  SOURCE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi

if [[ ! -d "$SOURCE_FRAMEWORK" ]]; then
  # Limit discovery to macOS XCFramework slices. Never select symbol bundles or
  # silently choose between multiple downloaded framework versions/slices.
  typeset -a candidates=()
  if [[ -d "$ROOT_DIR/.build/artifacts" ]]; then
    while IFS= read -r -d '' candidate; do
      candidates+=("$candidate")
    done < <(/usr/bin/find "$ROOT_DIR/.build/artifacts" \
      -type d -name '*.dSYM' -prune -o \
      -type d -name 'Sparkle.framework' \
      -path '*/Sparkle.xcframework/macos-*/Sparkle.framework' -print0)
  fi
  [[ ${#candidates[@]} -eq 1 ]] || fail \
    "expected one macOS Sparkle.framework in $BIN_DIR or .build/artifacts; found ${#candidates[@]} fallback candidates"
  SOURCE_FRAMEWORK="${candidates[1]}"
fi
SOURCE_FRAMEWORK="${SOURCE_FRAMEWORK:A}"

FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
/bin/mkdir -p "$FRAMEWORKS_DIR"
STAGING_DIR="$(/usr/bin/mktemp -d "$FRAMEWORKS_DIR/.sparkle-embed.XXXXXX")"
trap '/bin/rm -rf "$STAGING_DIR"' EXIT
STAGED_FRAMEWORK="$STAGING_DIR/Sparkle.framework"

# ditto preserves the versioned framework's symlinks and executable modes.
# Stage a fresh copy so obsolete files cannot survive from an earlier build.
/usr/bin/ditto "$SOURCE_FRAMEWORK" "$STAGED_FRAMEWORK"
VERSION_DIR="${STAGED_FRAMEWORK}/Versions/Current"
[[ -d "$VERSION_DIR" ]] || fail "missing Sparkle Versions/Current directory"
VERSION_DIR="${VERSION_DIR:A}"
[[ "$VERSION_DIR" == "$STAGED_FRAMEWORK"/Versions/* ]] || fail \
  "Sparkle Versions/Current resolves outside the copied framework"

# Sparkle 2.10.1's executable inventory is explicit: sign bundles rather than
# signing their main executable paths separately or traversing resource files.
typeset -a nested_code=(
  "$VERSION_DIR/XPCServices/Installer.xpc"
  "$VERSION_DIR/XPCServices/Downloader.xpc"
  "$VERSION_DIR/Autoupdate"
  "$VERSION_DIR/Updater.app"
)
typeset -a executables=(
  "$VERSION_DIR/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  "$VERSION_DIR/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
  "$VERSION_DIR/Autoupdate"
  "$VERSION_DIR/Updater.app/Contents/MacOS/Updater"
  "$VERSION_DIR/Sparkle"
)
for executable in "${executables[@]}"; do
  [[ -f "$executable" && -x "$executable" ]] || fail "missing executable: $executable"
  [[ "$(/usr/bin/file -b "$executable")" == *Mach-O* ]] || fail "not Mach-O: $executable"
done

if [[ "$SIGNING_IDENTITY" != '-' ]]; then
  # Preserve Downloader's existing entitlements, as required by Sparkle >=2.6.
  # The other components use Sparkle's documented distribution signing flags.
  # Do not use --deep for signing: different helpers require different metadata.
  for code in "${nested_code[@]}"; do
    typeset -a signing_flags=(--force --sign "$SIGNING_IDENTITY" --options runtime --timestamp)
    if [[ "$code" == "$VERSION_DIR/XPCServices/Downloader.xpc" ]]; then
      signing_flags+=(--preserve-metadata=entitlements)
    fi
    /usr/bin/codesign "${signing_flags[@]}" "$code"
  done
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$STAGED_FRAMEWORK"
fi

# For an ad-hoc, non-hardened host, leave Sparkle's supplied helper/framework
# signatures untouched. Update archives are authenticated separately with EdDSA.
/usr/bin/codesign --verify --deep --strict "$STAGED_FRAMEWORK"

DESTINATION_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
/bin/rm -rf "$DESTINATION_FRAMEWORK"
/bin/mv "$STAGED_FRAMEWORK" "$DESTINATION_FRAMEWORK"
/usr/bin/codesign --verify --deep --strict "$DESTINATION_FRAMEWORK"
print -r -- "Embedded and verified Sparkle.framework: $DESTINATION_FRAMEWORK"
