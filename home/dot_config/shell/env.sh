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

# Prepend ~/.local/bin and purse shims so they shadow real binaries on PATH.
# The devcontainer shim that lives here injects --dotfiles-* flags into `up` invocations.
# Conditional on the directory existing so this is a no-op before chezmoi
# has applied the dotfiles.
for _local_bin in "$HOME/.local/bin" "$HOME/.local/share/purse/shims"; do
  if [ -d "$_local_bin" ]; then
    case ":$PATH:" in
      *":$_local_bin:"*) ;;
      *) PATH="$_local_bin:$PATH" ;;
    esac
  fi
done
export PATH
unset _local_bin

# Local Homebrew — wired up by `purse-install-tools` in no-root environments
# (installed to ~/.homebrew) or the standard linuxbrew prefix. `brew shellenv`
# prepends brew's bin/man paths and exports HOMEBREW_* for the session.
# No-op when neither prefix exists (e.g. macOS, where brew is already on PATH).
for _brew in "$HOME/.homebrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
  if [ -x "$_brew" ]; then
    eval "$("$_brew" shellenv)"
    break
  fi
done
unset _brew

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
