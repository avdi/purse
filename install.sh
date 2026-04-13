#!/bin/sh

echo ". ~/dotfiles/aliases.sh" >> ~/.profile
echo ". ~/dotfiles/aliases.sh" >> ~/.bashrc

# devtunnel: source shell-setup in interactive shells
echo ". ~/.config/devtunnel/shell-setup.sh 2>/dev/null || true" >> ~/.bashrc
if [ -f ~/.zshrc ]; then
  echo ". ~/.config/devtunnel/shell-setup.sh 2>/dev/null || true" >> ~/.zshrc
fi

# devtunnel: install frpc + devtunnel wrapper + frpc.toml
curl -fsSL https://raw.githubusercontent.com/avdi/devtunnel/main/dotfiles/install-frpc.sh | bash
