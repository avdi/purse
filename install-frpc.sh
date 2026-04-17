#!/usr/bin/env bash
# Install frpc + devtunnel wrapper, and write ~/.config/devtunnel/frpc.toml.
#
# Token resolution order (strictly non-interactive):
#   1. $DEV_TUNNEL_TOKEN env var (set automatically in GitHub Codespaces)
#   2. Zoho Vault CLI (zv) if installed, already unlocked, and jq+timeout are available
#      Secret name: devtunnel-frp-auth-token  (ID: 339798000000165005)
#   3. If still unavailable, continue with a comment-only frpc.toml stub
#
# Tunnel configuration (optional env vars):
#   DEV_TUNNEL_SUBDOMAIN  (legacy) Subdomain to expose (default: avdi)
#   DEV_TUNNEL_PORT       (legacy) Local port to tunnel (default: 3000)
#
# Multi-port project config (optional env vars):
#   DEVTUNNEL_NAME     Project/subdomain name (also used by devtunnel wrapper)
#   DEVTUNNEL_PORTS       Space-separated "port[:label]" (e.g. "3000 3036:vite")
#   DEVTUNNEL_ENV         Newline-separated KEY=VALUE with {label} placeholders
#
# If DEVTUNNEL_NAME + DEVTUNNEL_PORTS are set, a project config file is
# generated at ~/.config/devtunnel/projects/<project>.toml so that
# `devtunnel serve` (or `devtunnel <project> serve`) works immediately.
set -euo pipefail

# Zoho Vault secret ID for the devtunnel FRP auth token
ZV_SECRET_ID="339798000000165005"

FRPC_VERSION=0.61.0
FRPC_BIN="$HOME/.local/bin/frpc"
DEVTUNNEL_BIN="$HOME/.local/bin/devtunnel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTUNNEL_DIR="$HOME/.config/devtunnel"
BASE_CONFIG="$DEVTUNNEL_DIR/frpc.toml"
INSTALL_FRPC_COPY="$DEVTUNNEL_DIR/install-frpc.sh"

# ---- frpc install ----
if [[ ! -x "$FRPC_BIN" ]]; then
  echo "Installing frpc ${FRPC_VERSION}..."
  mkdir -p "$HOME/.local/bin"
  curl -sL "https://github.com/fatedier/frp/releases/download/v${FRPC_VERSION}/frp_${FRPC_VERSION}_linux_amd64.tar.gz" \
    | tar -xz --strip-components=1 -C "$HOME/.local/bin" \
      "frp_${FRPC_VERSION}_linux_amd64/frpc"
  chmod +x "$FRPC_BIN"
  echo "frpc installed at $FRPC_BIN"
else
  echo "frpc already at $FRPC_BIN ($(frpc --version 2>/dev/null || true))"
fi

# ---- devtunnel wrapper ----
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/devtunnel" "$DEVTUNNEL_BIN"
chmod +x "$DEVTUNNEL_BIN"
echo "devtunnel wrapper installed at $DEVTUNNEL_BIN"

# ---- shell-setup ----
mkdir -p "$DEVTUNNEL_DIR"
cp "$SCRIPT_DIR/shell-setup.sh" "$DEVTUNNEL_DIR/shell-setup.sh"
echo "shell-setup.sh installed at ~/.config/devtunnel/shell-setup.sh"

# ---- install-frpc copy ----
cp "$SCRIPT_DIR/install-frpc.sh" "$INSTALL_FRPC_COPY"
chmod +x "$INSTALL_FRPC_COPY"
echo "install-frpc.sh installed at ~/.config/devtunnel/install-frpc.sh"

# ---- Codespace warning ----
if [[ "${CODESPACES:-}" == "true" && -z "${DEV_TUNNEL_TOKEN:-}" ]]; then
  echo ""
  echo "⚠️  WARNING: Running in a GitHub Codespace but DEV_TUNNEL_TOKEN is not set."
  echo "   Fix: github.com → Settings → Codespaces → Secrets → New secret"
  echo "   Name: DEV_TUNNEL_TOKEN  |  Value: FRP_AUTH_TOKEN from avdi/devtunnel server/.env"
  echo "   Then rebuild / reopen this Codespace."
  echo ""
fi

# ---- resolve token (non-interactive) ----
_zv_get_token() {
  command -v zv &>/dev/null || return 1
  command -v jq &>/dev/null || return 1
  command -v timeout &>/dev/null || return 1
  local out
  out=$(timeout 5s zv get -id "$ZV_SECRET_ID" --not-safe --output json </dev/null 2>/dev/null) || return 1
  jq -re '.secret.secretData[] | select(.id == "password") | .value' <<< "$out" 2>/dev/null
}

if [[ -z "${DEV_TUNNEL_TOKEN:-}" ]] && command -v zv &>/dev/null; then
  echo "Trying Zoho Vault (zv) non-interactively..."
  DEV_TUNNEL_TOKEN=$(_zv_get_token || true)
fi

if [[ -z "${DEV_TUNNEL_TOKEN:-}" ]]; then
  echo ""
  echo "⚠️  DEV_TUNNEL_TOKEN not found; devtunnel auth is not configured yet."
  echo "   Devcontainer/Codespaces startup will continue without devtunnel auth configured."
  echo "   To enable devtunnel later, run:"
  echo "     DEV_TUNNEL_TOKEN=your_token_here $INSTALL_FRPC_COPY"
  if [[ -f "$BASE_CONFIG" ]]; then
    echo "   Leaving existing ~/.config/devtunnel/frpc.toml in place."
  else
    cat > "$BASE_CONFIG" <<EOF
# devtunnel is not configured yet: DEV_TUNNEL_TOKEN was unavailable.
#
# To configure it later, run:
#
#   DEV_TUNNEL_TOKEN=your_token_here $INSTALL_FRPC_COPY
#
# Or rerun the same command later with DEV_TUNNEL_TOKEN already present
# in the environment. Once configured, this file will be replaced with
# the auth-bearing frpc.toml used by devtunnel.
EOF
    echo "   Wrote ~/.config/devtunnel/frpc.toml stub with recovery instructions."
  fi
fi

# ---- base frpc config (auth token only — proxies generated at runtime) ----
if [[ -n "${DEV_TUNNEL_TOKEN:-}" ]]; then
  mkdir -p "$DEVTUNNEL_DIR"
  cat > "$BASE_CONFIG" <<EOF
serverAddr = "avdi.dev"
serverPort = 7000

auth.method = "token"
auth.token = "${DEV_TUNNEL_TOKEN}"

# Keep retrying if frps is temporarily unreachable or another instance
# is holding the same subdomain. frpc will claim it once it's free.
loginFailExit = false
transport.heartbeatInterval = 10

# Legacy single-port proxy (used by devtunnel <project> <port> fallback)
[[proxies]]
name = "${DEV_TUNNEL_SUBDOMAIN:-avdi}"
type = "http"
localPort = ${DEV_TUNNEL_PORT:-3000}
subdomain = "${DEV_TUNNEL_SUBDOMAIN:-avdi}"
EOF

  echo "Base frpc config written to ~/.config/devtunnel/frpc.toml"
fi

# ---- project config from env vars ----
if [[ -n "${DEVTUNNEL_NAME:-}" && -n "${DEVTUNNEL_PORTS:-}" ]]; then
  mkdir -p "$HOME/.config/devtunnel/projects"
  PROJECT_FILE="$HOME/.config/devtunnel/projects/${DEVTUNNEL_NAME}.toml"

  {
    echo "subdomain = \"${DEVTUNNEL_NAME}\""
    echo ""
    for spec in $DEVTUNNEL_PORTS; do
      port="${spec%%:*}"
      label="${spec#*:}"
      [[ "$label" == "$spec" ]] && label=""
      echo "[[ports]]"
      echo "port = ${port}"
      [[ -n "$label" ]] && echo "label = \"${label}\""
      echo ""
    done

    if [[ -n "${DEVTUNNEL_ENV:-}" ]]; then
      echo "[env]"
      _OLD_IFS="${IFS:-}"
      IFS=';'
      for entry in $DEVTUNNEL_ENV; do
        # trim whitespace
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        [[ -z "$entry" ]] && continue
        key="${entry%%=*}"
        val="${entry#*=}"
        echo "${key} = \"${val}\""
      done
      IFS="$_OLD_IFS"
    fi
  } > "$PROJECT_FILE"

  echo "Project config written to $PROJECT_FILE"
  echo "  Run: devtunnel ${DEVTUNNEL_NAME} -- <command>"
  echo "   or: devtunnel ${DEVTUNNEL_NAME}              (tunnel only)"
else
  echo ""
  echo "Next: make sure ~/.local/bin is in your PATH, then:"
  echo "  devtunnel <project> serve    # multi-port with project config"
  echo "  devtunnel <project> <port>   # single-port legacy mode"
  echo "  devtunnel <project> edit     # create/edit project config"
fi
