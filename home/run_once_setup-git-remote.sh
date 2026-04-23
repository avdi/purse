#!/bin/sh
# chezmoi run_once: ensure the chezmoi source repo has branch tracking set up
#
# When chezmoi clones the dotfiles repo via `chezmoi init user/repo`, it does
# not set an upstream tracking branch, so `chezmoi update` (which runs git pull)
# fails with "no tracking information for the current branch".
#
# This script runs once after the first apply to wire origin/main as the
# upstream for the local main branch.

chezmoi git -- branch --set-upstream-to=origin/main main 2>/dev/null && \
  echo "chezmoi: set upstream to origin/main" || \
  echo "chezmoi: upstream already set or not applicable, skipping"
