#!/bin/sh
# chezmoi run_once: install Zoho Vault CLI (zv)
# Runs only on first `chezmoi apply` (or after a state reset).

if command -v zv >/dev/null 2>&1; then
  echo "zv already installed ($(zv --version 2>/dev/null || true))"
  exit 0
fi

echo "Installing Zoho Vault CLI (zv)..."
mkdir -p "$HOME/.local/bin"
curl -fsSL https://downloads.zohocdn.com/vault-cli-desktop/linux/zv_cli.zip \
  -o /tmp/zv_cli.zip
unzip -q -o /tmp/zv_cli.zip zv -d "$HOME/.local/bin"
chmod +x "$HOME/.local/bin/zv"
rm -f /tmp/zv_cli.zip
echo "zv installed at $HOME/.local/bin/zv"
