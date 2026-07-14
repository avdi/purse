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

# EDITOR fallback chain. Prefer VS Code's `code --wait`, but only when the `code`
# CLI actually WORKS — not merely when it's on PATH. Devcontainers ship a
# /usr/local/bin/code stub that is always present yet exits 127 ("code or
# code-insiders is not installed") whenever no real VS Code CLI is reachable:
# VS Code's integrated terminal injects the working shim ahead of the stub, but a
# shell you opened yourself (docker exec, ssh) hits only the failing stub. So we
# probe `code --version` (exit 0 = usable, prints no window) rather than trust
# `command -v`. Fall back to micro (a modern, non-modal terminal editor installed
# to ~/.local/bin by purse-install-extras), then to vi as a universal last resort.
if code --version >/dev/null 2>&1; then
  export EDITOR="code --wait"
elif command -v micro >/dev/null 2>&1; then
  export EDITOR="micro"
else
  export EDITOR="vi"
fi

# Prepend ~/.local/bin so user scripts shadow system binaries.
# Deduplicated so sourcing this file multiple times is a no-op.
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi

# purse shims must be FIRST in PATH to shadow the real devcontainer binary.
# Use strip-and-prepend (not dedup-or-skip) so this holds even when a tool
# installer appends its own PATH line to ~/.bashrc or ~/.profile after us.
if [ -d "$HOME/.local/share/purse/shims" ]; then
  _purse_shims="$HOME/.local/share/purse/shims"
  _purse_newpath=""
  _purse_rest="$PATH:"
  while [ -n "$_purse_rest" ]; do
    _purse_seg="${_purse_rest%%:*}"
    _purse_rest="${_purse_rest#*:}"
    [ "$_purse_seg" = "$_purse_shims" ] && continue
    _purse_newpath="${_purse_newpath:+$_purse_newpath:}$_purse_seg"
  done
  PATH="$_purse_shims:$_purse_newpath"
  unset _purse_shims _purse_newpath _purse_rest _purse_seg
fi
export PATH

# Local Homebrew — wired up by `purse-install-extras` in no-root environments
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
