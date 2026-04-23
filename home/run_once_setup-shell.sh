#!/bin/bash
# chezmoi run_once: wire shell aliases and lenticel into rc files
# Idempotent — checks before appending.

# shellcheck disable=SC2016  # $HOME intentionally unexpanded — written as literal text into rc files
ALIASES_LINE='. "$HOME/.config/shell/aliases.sh"'
LENTICEL_LINE='. "$HOME/.config/lenticel/shell-setup.sh" 2>/dev/null || true'

_append_if_missing() {
  local file="$1"
  local marker="$2"
  local line="$3"
  if [ -f "$file" ] && ! grep -qF "$marker" "$file"; then
    printf '\n%s\n' "$line" >> "$file"
    echo "Added to $file: $line"
  fi
}

# Shell aliases → .profile and .bashrc (and .zshrc if present)
for rc in ~/.profile ~/.bashrc; do
  _append_if_missing "$rc" '.config/shell/aliases.sh' "$ALIASES_LINE"
done
if [ -f ~/.zshrc ]; then
  _append_if_missing ~/.zshrc '.config/shell/aliases.sh' "$ALIASES_LINE"
fi

# Lenticel → .bashrc (and .zshrc if present)
_append_if_missing ~/.bashrc '.config/lenticel/shell-setup.sh' "$LENTICEL_LINE"
if [ -f ~/.zshrc ]; then
  _append_if_missing ~/.zshrc '.config/lenticel/shell-setup.sh' "$LENTICEL_LINE"
fi
