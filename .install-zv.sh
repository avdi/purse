#!/bin/sh
# chezmoi hooks.read-source-state.pre: install Zoho Vault CLI (zv)
# Runs before chezmoi reads the source state on every apply.
# Exits immediately if zv is already present — must be fast.

type zv >/dev/null 2>&1 && exit 0

echo "Installing Zoho Vault CLI (zv)..."
mkdir -p "$HOME/.local/bin"
curl -fsSL https://downloads.zohocdn.com/vault-cli-desktop/linux/zv_cli.zip \
  -o /tmp/zv_cli.zip
unzip -q -o /tmp/zv_cli.zip zv -d "$HOME/.local/bin"
chmod +x "$HOME/.local/bin/zv"
rm -f /tmp/zv_cli.zip
echo "zv installed at $HOME/.local/bin/zv"
