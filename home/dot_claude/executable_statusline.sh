#!/usr/bin/env bash
# Claude Code status line, rendered by Starship's claude-code profile.
#
# Wired up in ~/.claude/settings.json; the profile and its modules are
# configured in ~/.config/starship.toml. See https://starship.rs/advanced-config/
#
# Starship's `directory` and `git_*` modules read the process working
# directory, which is not guaranteed to be the session's. Pass the workspace
# path from the payload explicitly so the rendered path always matches the
# session rather than wherever the status line happened to be invoked.

set -uo pipefail

payload=$(cat)
workspace=$(printf '%s' "$payload" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)

# --path drives the git modules, --logical-path drives `directory`; both are
# needed or the rendered path and branch can disagree.
if [ -n "${workspace:-}" ] && [ -d "$workspace" ]; then
  printf '%s' "$payload" |
    exec starship statusline claude-code --path "$workspace" --logical-path "$workspace"
else
  printf '%s' "$payload" | exec starship statusline claude-code
fi
