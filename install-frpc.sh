#!/usr/bin/env bash
# Install frpc + devtunnel wrapper, and write ~/.config/devtunnel/frpc.toml.
#
# Token resolution order:
#   1. $DEV_TUNNEL_TOKEN env var (set automatically in GitHub Codespaces)
#   2. Zoho Vault CLI (zv) if installed, unlocked, and jq is available
#      Secret name: devtunnel-frp-auth-token  (ID: 339798000000165005)
#      If vault is locked and stdin is a tty, prompts for master password.
#   3. Interactive prompt
#
# Tunnel configuration (optional env vars):
#   DEV_TUNNEL_SUBDOMAIN  (legacy) Subdomain to expose (default: avdi)
#   DEV_TUNNEL_PORT       (legacy) Local port to tunnel (default: 3000)
#
# Multi-port project config (optional env vars):
#   DEVTUNNEL_PROJECT     Project/subdomain name (also used by devtunnel wrapper)
#   DEVTUNNEL_PORTS       Space-separated "port[:label]" (e.g. "3000 3036:vite")
#   DEVTUNNEL_ENV         Newline-separated KEY=VALUE with {label} placeholders
#
# If DEVTUNNEL_PROJECT + DEVTUNNEL_PORTS are set, a project config file is
# generated at ~/.config/devtunnel/projects/<project>.toml so that
# `devtunnel serve` (or `devtunnel <project> serve`) works immediately.
set -euo pipefail

# Zoho Vault secret ID for the devtunnel FRP auth token
ZV_SECRET_ID="339798000000165005"

FRPC_VERSION=0.61.0
FRPC_BIN="$HOME/.local/bin/frpc"
DEVTUNNEL_BIN="$HOME/.local/bin/devtunnel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
mkdir -p "$HOME/.config/devtunnel"
cp "$SCRIPT_DIR/shell-setup.sh" "$HOME/.config/devtunnel/shell-setup.sh"
echo "shell-setup.sh installed at ~/.config/devtunnel/shell-setup.sh"

# ---- Codespace warning ----
if [[ "${CODESPACES:-}" == "true" && -z "${DEV_TUNNEL_TOKEN:-}" ]]; then
  echo ""
  echo "⚠️  WARNING: Running in a GitHub Codespace but DEV_TUNNEL_TOKEN is not set."
  echo "   Fix: github.com → Settings → Codespaces → Secrets → New secret"
  echo "   Name: DEV_TUNNEL_TOKEN  |  Value: FRP_AUTH_TOKEN from avdi/devtunnel server/.env"
  echo "   Then rebuild / reopen this Codespace."
  echo ""
fi

# ---- resolve token ----
_zv_get_token() {
  command -v zv &>/dev/null || return 1
  command -v jq &>/dev/null || return 1
  local out
  out=$(timeout 5 zv get -id "$ZV_SECRET_ID" --not-safe --output json 2>/dev/null) || return 1
  jq -re '.secret.secretData[] | select(.id == "password") | .value' <<< "$out" 2>/dev/null
}

if [[ -z "${DEV_TUNNEL_TOKEN:-}" ]] && command -v zv &>/dev/null; then
  echo "Trying Zoho Vault (zv)..."
  DEV_TUNNEL_TOKEN=$(_zv_get_token || true)

  if [[ -z "${DEV_TUNNEL_TOKEN:-}" && -t 0 ]]; then
    echo "Vault appears locked. Enter your Zoho Vault master password to unlock,"
    echo "or press Enter to skip and type the token manually."
    read -rsp "Master password: " _zv_mp && echo
    if [[ -n "${_zv_mp:-}" ]]; then
      zv unlock "$_zv_mp" 2>/dev/null || true
      DEV_TUNNEL_TOKEN=$(_zv_get_token || true)
    fi
    unset _zv_mp
  fi
fi

if [[ -z "${DEV_TUNNEL_TOKEN:-}" ]]; then
  if [[ "${CODESPACES:-}" == "true" ]]; then
    echo "ERROR: DEV_TUNNEL_TOKEN is required in Codespaces. See warning above." >&2
    exit 1
  fi
  echo "DEV_TUNNEL_TOKEN not found in environment or Zoho Vault."
  read -rsp "Paste DEV_TUNNEL_TOKEN: " DEV_TUNNEL_TOKEN
  echo
fi

: "${DEV_TUNNEL_TOKEN:?Could not resolve DEV_TUNNEL_TOKEN}"

# ---- base frpc config (auth token only — proxies generated at runtime) ----
mkdir -p "$HOME/.config/devtunnel"
cat > "$HOME/.config/devtunnel/frpc.toml" <<EOF
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

# ---- project config from env vars ----
if [[ -n "${DEVTUNNEL_PROJECT:-}" && -n "${DEVTUNNEL_PORTS:-}" ]]; then
  mkdir -p "$HOME/.config/devtunnel/projects"
  PROJECT_FILE="$HOME/.config/devtunnel/projects/${DEVTUNNEL_PROJECT}.toml"

  {
    echo "subdomain = \"${DEVTUNNEL_PROJECT}\""
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
  echo "  Run: devtunnel ${DEVTUNNEL_PROJECT} -- <command>"
  echo "   or: devtunnel ${DEVTUNNEL_PROJECT}              (tunnel only)"
else
  echo ""
  echo "Next: make sure ~/.local/bin is in your PATH, then:"
  echo "  devtunnel <project> serve    # multi-port with project config"
  echo "  devtunnel <project> <port>   # single-port legacy mode"
  echo "  devtunnel <project> edit     # create/edit project config"
fi
