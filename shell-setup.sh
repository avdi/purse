#!/usr/bin/env bash
# devtunnel shell integration — source this from your .bashrc / .zshrc.
#
# In your purse dotfiles, add:
#   source ~/.config/devtunnel/shell-setup.sh   # if you copy it there, or:
#   source ~/projects/devtunnel/dotfiles/shell-setup.sh

# Add ~/.local/bin to PATH (idempotent)
case ":${PATH}:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Short alias
alias dt='devtunnel'
