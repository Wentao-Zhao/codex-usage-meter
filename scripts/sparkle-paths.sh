#!/bin/zsh
# Source after building the application's Sparkle binary target.
ROOT_DIR="${0:A:h:h}"
typeset -a sparkle_bins=("$ROOT_DIR"/.build/artifacts/*/Sparkle/bin(N/))
if [[ ${#sparkle_bins[@]} -ne 1 || ! -x "${sparkle_bins[1]}/sign_update" ]]; then
  print -u2 'Build the app first; expected exactly one pinned Sparkle tool distribution in .build/artifacts.'
  return 1
fi
SPARKLE_TOOL_DIR="${sparkle_bins[1]}"
