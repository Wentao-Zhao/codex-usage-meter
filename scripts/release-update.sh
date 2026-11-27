#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
MODE="${1:---prepare}"
[[ "$MODE" == '--prepare' || "$MODE" == '--publish' ]] || { print -u2 'Usage: release-update.sh [--prepare|--publish]'; exit 2; }
export APP_UNINSTALLER_SWIFTPM_DISABLE_SANDBOX=1
export CLIPBOARD_HISTORY_SWIFTPM_DISABLE_SANDBOX=1
zsh scripts/package-dmg.sh
zsh scripts/check-updater.sh
zsh scripts/generate-update.sh
if [[ "$MODE" == '--prepare' ]]; then exit 0; fi
REPOSITORY="$(/usr/bin/plutil -extract repository raw -o - Resources/UpdateRelease.json)"
SOURCE_REPOSITORY="$(/usr/bin/plutil -extract source_repository raw -o - Resources/UpdateRelease.json)"
APP_NAME="$(/usr/bin/plutil -extract app_name raw -o - Resources/UpdateRelease.json)"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]] || { print -u2 'Commit and push all changes before publishing.'; exit 1; }
[[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse HEAD)" ]] || { print -u2 'Release tag must point at HEAD.'; exit 1; }
REMOTE_TAG="$(gh api "repos/$SOURCE_REPOSITORY/git/ref/tags/$TAG" --jq .object.sha)"
[[ "$REMOTE_TAG" == "$(git rev-parse "refs/tags/$TAG")" ]] || { print -u2 'Remote annotated tag differs from local; push the matching source tag first.'; exit 1; }
# Never replace assets on an already-published release. A newer build needs a new version.
if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  print -u2 "Release $TAG already exists; inspect it before retrying."
  exit 1
fi
typeset -a archives=("$ROOT_DIR/dist/$APP_NAME-$VERSION"*.dmg(N))
NOTES="$ROOT_DIR/.build/update-release-notes.md"
print -r -- "$APP_NAME $VERSION：手动检查更新、签名验证、安装并重启。" > "$NOTES"
print -r -- '首次需要手动安装带更新器的新版本；后续可在应用菜单中选择「检查更新…」。' >> "$NOTES"
gh release create "$TAG" "${archives[1]}" dist/appcast.xml dist/SHA256SUMS \
  --repo "$REPOSITORY" --title "$APP_NAME $VERSION" --notes-file "$NOTES" --draft
gh release edit "$TAG" --repo "$REPOSITORY" --draft=false --latest
