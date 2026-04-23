#!/usr/bin/env bash
# run_onchange_setup-ai-symlinks.sh
#
# Symlinks each AI agent's expected system-prompt location to the shared file
# managed by chezmoi at ~/.config/ai/system-prompt.md.
#
# Covered tools:
#   - Claude Code  -> ~/.claude/CLAUDE.md
#   - Gemini CLI   -> ~/.gemini/GEMINI.md
#   - Augment      -> ~/.augment/rules/global.md
#
# This script re-runs whenever its own content changes (run_onchange_ prefix).

set -euo pipefail

SOURCE="$HOME/.config/ai/system-prompt.md"

link() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  ln -sf "$SOURCE" "$target"
  echo "Linked: $target -> $SOURCE"
}

link "$HOME/.claude/CLAUDE.md"
link "$HOME/.gemini/GEMINI.md"
link "$HOME/.augment/rules/global.md"
