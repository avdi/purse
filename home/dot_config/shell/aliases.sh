# Shell aliases — managed by chezmoi
#
# This file lives in the repo at:
#   home/dot_config/shell/aliases.sh
#
# chezmoi installs it to:
#   ~/.config/shell/aliases.sh
#
# The "dot_config" prefix is chezmoi's naming convention: "dot_" becomes "."
# in the target path, so dot_config/ → .config/, dot_bashrc → .bashrc, etc.
# See: https://www.chezmoi.io/reference/source-state-attributes/
#
# run_once_setup-shell.sh adds a source line for this file to ~/.bashrc,
# ~/.profile, and ~/.zshrc (if present) on first apply.

# Source env vars first so aliases can reference them if needed
# shellcheck source=/dev/null
_shell_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/shell"
[ -f "$_shell_cfg/env.sh" ] && . "$_shell_cfg/env.sh"
unset _shell_cfg

alias gs="git status"

# direnv shell hook — loads/unloads .envrc as you cd between directories.
# See: https://direnv.net/docs/hook.html
if command -v direnv >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(direnv hook zsh)"
  else
    eval "$(direnv hook bash)"
  fi
fi
