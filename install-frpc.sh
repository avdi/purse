#!/usr/bin/env bash
# Install frpc + lenticel wrapper, and write ~/.config/lenticel/frpc.toml.
#
# Token resolution order (strictly non-interactive):
#   1. $LENTICEL_TOKEN env var (set automatically in GitHub Codespaces)
#   2. Zoho Vault CLI (zv) if installed, already unlocked, and jq+timeout are available
#      Secret name: lenticel-frp-auth-token  (ZV_SECRET_ID env var or set below)
#   3. If still unavailable, continue with a comment-only frpc.toml stub
#
# Required env vars:
#   LENTICEL_SERVER       Hostname of the frps server (e.g. tunnel.example.com)
#
# Tunnel configuration (optional env vars):
#   LENTICEL_SUBDOMAIN    Subdomain to expose (default: myproject)
#   LENTICEL_PORT         Local port to tunnel (default: 3000)
#
# Multi-port project config (optional env vars):
#   LENTICEL_NAME      Project/subdomain name (also used by lenticel wrapper)
#   LENTICEL_PORTS        Space-separated "port[:label]" (e.g. "3000 3036:vite")
#   LENTICEL_ENV          Newline-separated KEY=VALUE with {label} placeholders
#
# If LENTICEL_NAME + LENTICEL_PORTS are set, a project config file is
# generated at ~/.config/lenticel/projects/<project>.toml so that
# `lenticel serve` (or `lenticel <project> serve`) works immediately.
set -euo pipefail

# Zoho Vault secret ID for the lenticel FRP auth token.
# Override with ZV_SECRET_ID env var, or leave empty to skip Zoho Vault lookup.
ZV_SECRET_ID="${ZV_SECRET_ID:-}"

FRPC_VERSION=0.61.0
FRPC_BIN="$HOME/.local/bin/frpc"
LENTICEL_BIN="$HOME/.local/bin/lenticel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LENTICEL_DIR="$HOME/.config/lenticel"
BASE_CONFIG="$LENTICEL_DIR/frpc.toml"
INSTALL_FRPC_COPY="$LENTICEL_DIR/install-frpc.sh"

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

# ---- lenticel wrapper ----
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/lenticel" "$LENTICEL_BIN"
chmod +x "$LENTICEL_BIN"
echo "lenticel wrapper installed at $LENTICEL_BIN"

# ---- shell-setup ----
mkdir -p "$LENTICEL_DIR"
cp "$SCRIPT_DIR/shell-setup.sh" "$LENTICEL_DIR/shell-setup.sh"
echo "shell-setup.sh installed at ~/.config/lenticel/shell-setup.sh"

# ---- install-frpc copy ----
cp "$SCRIPT_DIR/install-frpc.sh" "$INSTALL_FRPC_COPY"
chmod +x "$INSTALL_FRPC_COPY"
echo "install-frpc.sh installed at ~/.config/lenticel/install-frpc.sh"

# ---- Codespace warning ----
if [[ "${CODESPACES:-}" == "true" && -z "${LENTICEL_TOKEN:-}" ]]; then
  echo ""
  echo "⚠️  WARNING: Running in a GitHub Codespace but LENTICEL_TOKEN is not set."
  echo "   Fix: github.com → Settings → Codespaces → Secrets → New secret"
  echo "   Name: LENTICEL_TOKEN  |  Value: FRP_AUTH_TOKEN from the lenticel server/.env"
  echo "   Then rebuild / reopen this Codespace."
  echo ""
fi

# ---- resolve token (non-interactive) ----
_zv_get_token() {
  [[ -n "$ZV_SECRET_ID" ]] || return 1
  command -v zv &>/dev/null || return 1
  command -v jq &>/dev/null || return 1
  command -v timeout &>/dev/null || return 1
  local out
  out=$(timeout 5s zv get -id "$ZV_SECRET_ID" --not-safe --output json </dev/null 2>/dev/null) || return 1
  jq -re '.secret.secretData[] | select(.id == "password") | .value' <<< "$out" 2>/dev/null
}

if [[ -z "${LENTICEL_TOKEN:-}" ]] && command -v zv &>/dev/null; then
  echo "Trying Zoho Vault (zv) non-interactively..."
  LENTICEL_TOKEN=$(_zv_get_token || true)
fi

if [[ -z "${LENTICEL_TOKEN:-}" ]]; then
  echo ""
  echo "⚠️  LENTICEL_TOKEN not found; lenticel auth is not configured yet."
  echo "   Devcontainer/Codespaces startup will continue without lenticel auth configured."
  echo "   To enable lenticel later, run:"
  echo "     LENTICEL_TOKEN=your_token_here $INSTALL_FRPC_COPY"
  if [[ -f "$BASE_CONFIG" ]]; then
    echo "   Leaving existing ~/.config/lenticel/frpc.toml in place."
  else
    cat > "$BASE_CONFIG" <<EOF
# lenticel is not configured yet: LENTICEL_TOKEN was unavailable.
#
# To configure it later, run:
#
#   LENTICEL_TOKEN=your_token_here $INSTALL_FRPC_COPY
#
# Or rerun the same command later with LENTICEL_TOKEN already present
# in the environment. Once configured, this file will be replaced with
# the auth-bearing frpc.toml used by lenticel.
EOF
    echo "   Wrote ~/.config/lenticel/frpc.toml stub with recovery instructions."
  fi
fi

# ---- base frpc config (auth token only — proxies generated at runtime) ----
if [[ -n "${LENTICEL_TOKEN:-}" ]]; then
  if [[ -z "${LENTICEL_SERVER:-}" ]]; then
    echo "ERROR: LENTICEL_SERVER is not set. Set it to the hostname of your frps server."
    exit 1
  fi
  mkdir -p "$LENTICEL_DIR"
  cat > "$BASE_CONFIG" <<EOF
serverAddr = "${LENTICEL_SERVER}"
serverPort = 7000

auth.method = "token"
auth.token = "${LENTICEL_TOKEN}"

# Keep retrying if frps is temporarily unreachable or another instance
# is holding the same subdomain. frpc will claim it once it's free.
loginFailExit = false
transport.heartbeatInterval = 10

# Legacy single-port proxy (used by lenticel <project> <port> fallback)
[[proxies]]
name = "${LENTICEL_SUBDOMAIN:-myproject}"
type = "http"
localPort = ${LENTICEL_PORT:-3000}
subdomain = "${LENTICEL_SUBDOMAIN:-myproject}"
requestHeaders.set.X-Forwarded-Proto = "https"
EOF

  echo "Base frpc config written to ~/.config/lenticel/frpc.toml"
fi

# ---- project config from env vars ----
if [[ -n "${LENTICEL_NAME:-}" && -n "${LENTICEL_PORTS:-}" ]]; then
  mkdir -p "$HOME/.config/lenticel/projects"
  PROJECT_FILE="$HOME/.config/lenticel/projects/${LENTICEL_NAME}.toml"

  {
    echo "subdomain = \"${LENTICEL_NAME}\""
    echo ""
    for spec in $LENTICEL_PORTS; do
      port="${spec%%:*}"
      label="${spec#*:}"
      [[ "$label" == "$spec" ]] && label=""
      echo "[[ports]]"
      echo "port = ${port}"
      [[ -n "$label" ]] && echo "label = \"${label}\""
      echo ""
    done

    if [[ -n "${LENTICEL_ENV:-}" ]]; then
      echo "[env]"
      _OLD_IFS="${IFS:-}"
      IFS=';'
      for entry in $LENTICEL_ENV; do
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
  echo "  Run: lenticel ${LENTICEL_NAME} -- <command>"
  echo "   or: lenticel ${LENTICEL_NAME}              (tunnel only)"
else
  echo ""
  echo "Next: make sure ~/.local/bin is in your PATH, then:"
  echo "  lenticel <project> serve    # multi-port with project config"
  echo "  lenticel <project> <port>   # single-port legacy mode"
  echo "  lenticel <project> edit     # create/edit project config"
fi
