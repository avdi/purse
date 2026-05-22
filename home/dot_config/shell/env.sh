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

alias codew="code --wait"
export EDITOR="code --wait"

# Prepend purse shims so they shadow real binaries on PATH. The devcontainer
# shim that lives here injects --dotfiles-* flags into `up` invocations.
# Conditional on the directory existing so this is a no-op before chezmoi
# has applied the dotfiles.
if [ -d "$HOME/.local/share/purse/shims" ]; then
  case ":$PATH:" in
    *":$HOME/.local/share/purse/shims:"*) ;;
    *) PATH="$HOME/.local/share/purse/shims:$PATH" ;;
  esac
  export PATH
fi

# GPG needs to know the current TTY to prompt for passphrase on git signing.
# Git commit signing is opt-in per-repo; without GPG_TTY, pinentry-curses fails
# silently and signed commits/tags error out with "Inappropriate ioctl".
export GPG_TTY=$(tty)

# Secrets pulled from Zoho Vault by setup-secrets (not chezmoi-managed, never committed)
# shellcheck disable=SC1091
[ -f "${HOME}/.config/shell/secrets.sh" ] && . "${HOME}/.config/shell/secrets.sh"

# Inside a devcontainer with the devcontainer-bridge (dbr) feature installed,
# route $BROWSER through dbr-open so URLs opened by container tools land in
# the host browser. Harmless no-op outside containers / when dbr isn't present.
if [ -z "${BROWSER:-}" ] && command -v dbr-open >/dev/null 2>&1; then
  export BROWSER=dbr-open
fi
