#!/bin/sh
# chezmoi hooks.read-source-state.pre: install Zoho Vault CLI (zv)
# Runs before chezmoi reads the source state on every apply.
# Exits immediately if zv is already present — must be fast.
#
# Always exits 0: a read-source-state hook that fails aborts the entire apply,
# including every run_once/run_onchange script. A missing zv only costs secret
# templating, so it must never be the reason a machine goes unprovisioned.

# Probe for a *real* zv, not the purse shim. The shim sits ahead of the real
# binary on PATH and satisfies `type zv`, so a naive check exits early and
# never installs what the shim delegates to — leaving the shim to advise
# "run: chezmoi apply", the command that just no-opped.
zv_shim="$HOME/.local/share/purse/shims/zv"
zv_found="$(command -v zv 2>/dev/null || true)"
if [ -n "$zv_found" ] && [ "$zv_found" != "$zv_shim" ]; then
  exit 0
fi
[ -x "$HOME/.local/bin/zv" ] && exit 0

case "$(uname -s)" in
  Linux)  zv_platform="linux" ;;
  Darwin) zv_platform="macos" ;;
  *)      echo "zv: unsupported platform $(uname -s) — skipping" >&2; exit 0 ;;
esac

# Zoho publishes only an x86_64 build for macOS, so Apple silicon runs it under
# Rosetta. Installing it without Rosetta would put a binary on PATH that passes
# `command -v` and then dies with "bad CPU type" on every call — worse than not
# installing it at all. Test for the installed oahd binary rather than a running
# oahd process: the daemon starts on demand, so a process check reads as "no
# Rosetta" on a capable Mac that simply hasn't translated anything yet.
if [ "$zv_platform" = "macos" ] && [ "$(uname -m)" = "arm64" ] \
   && [ ! -x /usr/libexec/rosetta/oahd ]; then
  cat >&2 <<'EOF'
⚠️  zv (Zoho Vault CLI) ships as x86_64-only for macOS and needs Rosetta 2,
   which isn't installed. Secret templating and purse-install-secrets stay
   unavailable until you run:

       softwareupdate --install-rosetta --agree-to-license

   then re-run: chezmoi apply
EOF
  exit 0
fi

echo "Installing Zoho Vault CLI (zv)..."
mkdir -p "$HOME/.local/bin"
zv_tmp="$(mktemp -d)" || exit 0
if curl -fsSL "https://downloads.zohocdn.com/vault-cli-desktop/${zv_platform}/zv_cli.zip" \
     -o "$zv_tmp/zv_cli.zip" \
   && unzip -q -o "$zv_tmp/zv_cli.zip" zv -d "$HOME/.local/bin"; then
  chmod +x "$HOME/.local/bin/zv"
  echo "zv installed at $HOME/.local/bin/zv"
else
  echo "⚠️  zv: download failed — skipping (re-run chezmoi apply to retry)" >&2
fi
rm -rf "$zv_tmp"
exit 0
