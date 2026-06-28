#!/usr/bin/env bash
# Remove the worktrunk shell-integration line that `wt config shell install`
# injected into rc files. Run once; harmless if the line is already gone.

set -euo pipefail

strip_wt_line() {
  local file="$1"
  [ -f "$file" ] || return 0
  if grep -qF 'wt config shell init' "$file"; then
    grep -vF 'wt config shell init' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    echo "→ removed worktrunk shell integration from $file"
  fi
}

strip_wt_line "$HOME/.bashrc"
strip_wt_line "$HOME/.zshrc"
strip_wt_line "$HOME/.bash_profile"
strip_wt_line "$HOME/.profile"
