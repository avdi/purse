# shellcheck shell=sh
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

alias cm="chezmoi"
alias gs="git status"
alias vs="vscli open"
alias vsr="vscli recent"
alias lt="lenticel"
# `dc` lives at ~/.local/bin/dc as a script (routes through the devcontainer
# shim that injects --dotfiles-* flags); intentionally not aliased here so the
# script stays discoverable via `which dc` and works in non-interactive shells.

# Pull latest from the chezmoi source clone (~/.local/share/chezmoi) and
# apply. The working clone at ~/projects/avdi/purse is separate, so edits
# committed/pushed there don't take effect on disk until this runs.
alias purse-pull="chezmoi update --safe=false"

# cd to the chezmoi source clone (the purse repo) on this machine.
purse-cd() { cd "$(chezmoi source-path)"; }
alias cdpurse="purse-cd"

alias bcprune="git-bc-prune"

# Branch-clone helpers — must be functions (not aliases) so that `cd` affects
# the current shell session.

# bcadd <source> <branch> [target]
# Creates a branch clone via git-bc-add and cd's into it on success.
# Replicates git-bc-add's default-target logic so we know the path even when
# [target] is omitted.
bcadd() {
  local source_abs branch safe_branch project target
  source_abs="$(cd "${1:?<source> required}" && pwd)"
  branch="${2:?<branch> required}"
  safe_branch="${branch//\//-}"
  project="$(basename "$source_abs")"
  target="${3:-$(dirname "$source_abs")/${project}.${safe_branch}}"
  git-bc-add "$@" && cd "$target"
}

# bcrm <clone-dir> [--force]
# Removes a branch clone via git-bc-rm. If the clone-dir resolves to the
# current directory, cd's to the parent first to avoid being stranded.
bcrm() {
  local clone_abs cwd_abs
  clone_abs="$(cd "${1:?<clone-dir> required}" && pwd)"
  cwd_abs="$(pwd)"
  if [ "$clone_abs" = "$cwd_abs" ]; then
    cd ..
  fi
  git-bc-rm "$@"
}

# direnv shell hook — loads/unloads .envrc as you cd between directories.
# See: https://direnv.net/docs/hook.html
if command -v direnv >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(direnv hook zsh)"
  else
    eval "$(direnv hook bash)"
  fi
fi

# chruby shell hook — enables 'chruby X.Y.Z' to switch Ruby versions.
# auto.sh additionally reads .ruby-version files and switches automatically.
# Probe known brew prefix locations (linuxbrew / Apple Silicon / Intel) and
# the default prefix used by manual 'make install'.
# See: https://github.com/postmodern/chruby
for _chruby_sh in \
  /home/linuxbrew/.linuxbrew/opt/chruby/share/chruby/chruby.sh \
  /opt/homebrew/opt/chruby/share/chruby/chruby.sh \
  /usr/local/opt/chruby/share/chruby/chruby.sh \
  /usr/local/share/chruby/chruby.sh; do
  if [ -f "$_chruby_sh" ]; then
    # shellcheck source=/dev/null
    . "$_chruby_sh"
    # Only enable .ruby-version auto-switching when chruby actually has rubies
    # to switch between. chruby discovers them from ~/.rubies and /opt/rubies
    # (chruby.sh); where Ruby is provided by the system/image (devcontainers,
    # Codespaces) those are empty, so auto.sh would just spew "unknown Ruby"
    # for every .ruby-version it reads. Skipping it keeps the system Ruby and
    # stays quiet, while chruby remains available for manual use.
    for _rubies_dir in "$HOME/.rubies" /opt/rubies; do
      if [ -d "$_rubies_dir" ] && [ -n "$(ls -A "$_rubies_dir" 2>/dev/null)" ]; then
        # shellcheck source=/dev/null
        . "${_chruby_sh%chruby.sh}auto.sh" 2>/dev/null || true
        # auto.sh does `unset RUBY_AUTO_VERSION`; re-initialise to "" so that
        # subsequent references inside chruby_auto don't trigger set -u.
        RUBY_AUTO_VERSION="${RUBY_AUTO_VERSION-}"
        break
      fi
    done
    unset _rubies_dir
    break
  fi
done
unset _chruby_sh

# fzf — fuzzy finder; key bindings: Ctrl+R (history), Ctrl+T (file), Alt+C (cd)
# Modern fzf (0.46+, brew) uses 'fzf --bash/--zsh'.
# Older fzf (apt on Ubuntu ≤24.04) ships integration files instead; fall back
# to those so both install paths work.
if command -v fzf >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    _fzf_init="$(fzf --zsh </dev/null 2>/dev/null)" && eval "$_fzf_init" || \
      { [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && \
          . /usr/share/doc/fzf/examples/key-bindings.zsh; }
  else
    _fzf_init="$(fzf --bash </dev/null 2>/dev/null)" && eval "$_fzf_init" || \
      { [ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && \
          . /usr/share/doc/fzf/examples/key-bindings.bash; }
  fi
  unset _fzf_init
fi

# work <project> [branch-or-issue#]  (alias: wb)
#
# z to the project dir, optionally switch/create a worktree branch, then
# ensure a devcontainer is running (dc up) and shell into it (dcsh).
#
# Second argument:
#   <branch>  — wt switch -c to a new branch
#   <number>  — GitHub issue; switch to linked PR branch or ask agent for one
#   (omitted) — stay in the base workspace, no worktree switch
work() {
  local project="${1:?usage: work <project> [branch-or-issue]}"
  local arg="${2:-}"

  z "$project" || return 1

  if [[ -z "$arg" ]]; then
    : # base workspace — no worktree switch
  elif [[ "$arg" =~ ^[0-9]+$ ]]; then
    _work_switch_for_issue "$arg" || return 1
  else
    wt switch -c "$arg" || return 1
  fi

  dc up && dcsh
}

_work_switch_for_issue() {
  local issue_num="$1"
  local pr_num branch issue_title prompt

  pr_num=$(gh api "repos/{owner}/{repo}/issues/${issue_num}/timeline" \
    --jq '[.[] | select(.event == "cross-referenced" and .source.type == "pullrequest") | .source.issue.number] | first // empty' \
    2>/dev/null)

  if [[ -n "$pr_num" ]]; then
    wt switch "pr:${pr_num}"
    return
  fi

  issue_title=$(gh issue view "$issue_num" --json title --jq '.title' 2>/dev/null) \
    || issue_title="issue #${issue_num}"

  echo "work: no PR found for issue #${issue_num}: ${issue_title}" >&2

  prompt="Suggest a git branch name for GitHub issue #${issue_num}: ${issue_title}. Use lowercase with hyphens, optionally prefixed with the issue number (e.g. '42-fix-the-bug'). Reply with only the branch name, nothing else."
  branch=$(purse-default-agent -p "$prompt" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r' | grep -v '^\s*$' | tail -1)

  if [[ -z "$branch" ]]; then
    read -r -p "Branch name: " branch </dev/tty
  fi

  [[ -n "$branch" ]] || { echo "work: no branch name given" >&2; return 1; }
  branch="${branch//[[:space:]]/-}"
  wt switch -c "$branch"
}

alias wb=work

# wt — git worktree manager shell integration (enables directory switching)
if command -v wt >/dev/null 2>&1; then
  eval "$(command wt config shell init bash 2>/dev/null)" 2>/dev/null || true
fi

# zoxide — frecency-based directory jumper; replaces cd with 'z' / 'zi'
# Not initialized in devcontainers (not installed there by default), which is
# intentional: single-project ephemeral environments get little value from a
# frecency database that starts fresh each time.
if command -v zoxide >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(zoxide init zsh)"
  else
    eval "$(zoxide init bash)"
  fi
fi
