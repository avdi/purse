#!/bin/sh
# Dotfiles installer — works as both:
#   • VS Code / GitHub Codespace auto-dotfiles hook  (run automatically after clone)
#   • Manual bootstrap on a new machine
#
# Installs chezmoi if absent, then uses it to apply the dotfiles.
# chezmoi reads the source state from the home/ subdirectory of this repo
# (see .chezmoiroot) and runs the run_once_ scripts to set up tools and
# shell hooks.
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- install chezmoi if needed ----
if ! command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi not found — installing to ~/.local/bin ..."
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

# ---- apply dotfiles ----
# --apply   : apply immediately after init
# --source  : use this cloned repo as the source directory
#             (chezmoi reads source state from <source>/home/ per .chezmoiroot)
chezmoi init --apply --source="$DOTFILES_DIR"
