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

# ---- guard against cross-device rename failures ----
# In some devcontainer setups, ~/.config and ~/.local are on different
# filesystems (e.g., ~/.local is a named Docker volume).  Chezmoi creates
# temp files inside its config dir (~/.config/chezmoi/) and then atomically
# renames them to their targets; when those targets live under ~/.local/ the
# rename fails with EXDEV ("invalid cross-device link").  Symlinking chezmoi's
# config dir into ~/.local/ before the first run puts temp files and their
# targets on the same filesystem.  The check is idempotent: it only acts when
# the config dir does not yet exist as a real directory or symlink.
if [ ! -e "$HOME/.config/chezmoi" ] && [ ! -L "$HOME/.config/chezmoi" ]; then
  mkdir -p "$HOME/.local/share/chezmoi-config"
  mkdir -p "$HOME/.config"
  ln -s "$HOME/.local/share/chezmoi-config" "$HOME/.config/chezmoi"
fi

# ---- apply dotfiles ----
# --apply   : apply immediately after init
# --source  : use this cloned repo as the source directory
#             (chezmoi reads source state from <source>/home/ per .chezmoiroot)
chezmoi init --apply --source="$DOTFILES_DIR"
