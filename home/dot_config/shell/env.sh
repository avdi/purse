# shellcheck shell=sh
# Shell environment variables — managed by chezmoi
#
# This file lives in the repo at:
#   home/dot_config/shell/env.sh
#
# chezmoi installs it to:
#   ~/.config/shell/env.sh
#
# It is sourced by ~/.config/shell/aliases.sh, which is itself sourced by
# ~/.bashrc, ~/.profile, and ~/.zshrc. Add any exported env vars here.

export EDITOR=code

# GPG needs to know the current TTY to prompt for passphrase on git signing.
# Git commit signing is opt-in per-repo; without GPG_TTY, pinentry-curses fails
# silently and signed commits/tags error out with "Inappropriate ioctl".
export GPG_TTY=$(tty)

# Secrets pulled from Zoho Vault by setup-secrets (not chezmoi-managed, never committed)
# shellcheck disable=SC1091
[ -f "${HOME}/.config/shell/secrets.sh" ] && . "${HOME}/.config/shell/secrets.sh"
