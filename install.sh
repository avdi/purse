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
# --apply       : apply immediately after init
# --source      : use this cloned repo as the source directory
#                 (chezmoi reads source state from <source>/home/ per .chezmoiroot)
# --safe=false  : write targets in place instead of atomically (temp file +
#                 rename).  Devcontainers split $HOME across several mounts —
#                 ~ on the overlay, ~/.config, ~/.local/share, ~/.local/state
#                 each a separate named Docker volume — and rename() across
#                 mounts fails with EXDEV ("invalid cross-device link"),
#                 aborting the whole apply on the first target that lives on a
#                 different mount than chezmoi's temp dir.  No single temp-dir
#                 location satisfies every target, so disable atomic writes.
#                 Harmless on single-filesystem hosts.
chezmoi init --apply --safe=false --force --source="$DOTFILES_DIR"
