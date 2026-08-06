#!/usr/bin/env bash
# Claude Code status line: working directory, git branch, model, plugin badges.
#
# Wired up in ~/.claude/settings.json as statusLine.command. Runs on every
# render, so it stays bash + a single jq call rather than Ruby.

set -uo pipefail

payload=$(cat)

read -r cwd model < <(
  printf '%s' "$payload" |
    jq -r '[(.workspace.current_dir // .cwd // ""), (.model.display_name // "")] | @tsv' 2>/dev/null
)

DIM=$'\033[2m'
CYAN=$'\033[38;5;110m'
RESET=$'\033[0m'

segments=()

if [ -n "${cwd:-}" ]; then
  segments+=("${DIM}${cwd/#$HOME/\~}${RESET}")
fi

if [ -n "${cwd:-}" ]; then
  branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null) ||
    branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  [ -n "${branch:-}" ] && segments+=("${CYAN}${branch}${RESET}")
fi

if [ -n "${model:-}" ]; then
  segments+=("${DIM}${model}${RESET}")
fi

# Plugin badges append themselves; each exits silently when inactive.
caveman_badge=$(
  ls -td "$HOME"/.claude/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh 2>/dev/null |
    head -1
)
if [ -n "$caveman_badge" ]; then
  badge=$(bash "$caveman_badge" 2>/dev/null)
  [ -n "$badge" ] && segments+=("$badge")
fi

separator='  '
line=""
for segment in ${segments[@]+"${segments[@]}"}; do
  line+="${line:+$separator}$segment"
done
printf '%s' "$line"
