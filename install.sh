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

# ---- refuse to run against a locked-down $HOME ----
# Shared-hosting "application-specific" SSH accounts (Cloudways is the known
# case) give you a login but not your own home directory: $HOME itself is
# root-owned with no write bit for your user or group, so any attempt to
# create a new file or directory directly under it — ~/.local, ~/.config,
# ~/.bashrc, everything chezmoi's default paths and every dotfile target need
# — fails with a bare "permission denied" that gives no hint why. Only a
# couple of app-specific subdirectories (e.g. public_html, private_html) are
# actually writable, and chezmoi can't discover or use those on its own.
# Catch it here with a clear diagnosis instead of letting chezmoi's own crash
# be the first anyone hears of it.
if [ ! -w "$HOME" ]; then
  cat >&2 <<EOF
✗ \$HOME ($HOME) is not writable by $(id -un 2>/dev/null || echo "this user").

This is typical of a shared-hosting "application-specific" SSH account
(e.g. Cloudways) where the account gets a login but not its own home
directory — only specific subdirectories (public_html, private_html, ...)
are actually writable, and \$HOME's top level is root-owned.

chezmoi cannot install here as-is: its default state directories and every
dotfile target live directly under \$HOME. Point \$HOME at a writable,
non-web-served directory before bootstrapping instead, e.g.:

    export HOME="\$HOME/private_html/home"
    mkdir -p "\$HOME"
    sh -c "\$(curl -fsLS get.chezmoi.io)" -- init --apply avdi/purse

Never use public_html for this — it is served to the web. The redirected
\$HOME won't be picked up by future login shells automatically (the real
\$HOME/.bashrc is root-owned and can't be edited to export it), so re-export
HOME at the start of each session that needs these dotfiles.
EOF
  exit 1
fi

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
