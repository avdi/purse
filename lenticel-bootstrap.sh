#!/usr/bin/env bash
# Purse-side bootstrapper for lenticel.
# Resolves LENTICEL_TOKEN from available secret stores, then invokes
# the lenticel installer. This script is the purse-specific glue —
# it knows about Zoho Vault. The lenticel installer itself only speaks
# plain env vars.
#
# Set these in your environment or Codespace secrets:
#   LENTICEL_SERVER  — hostname of the frps server (default: avdi.dev)
#   ZV_SECRET_ID     — Zoho Vault secret ID for LENTICEL_TOKEN (optional)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- token resolution (purse-specific) ----
ZV_SECRET_ID="${ZV_SECRET_ID:-}"

# Every failure here is soft — lenticel installs without a token — but it says
# which one it hit. zv reports auth failures as prose on stdout and still exits
# 0, so the output is classified rather than trusted. This stays self-contained
# (no purse-zv-json) because it runs at bootstrap, before ~/.local/bin is
# guaranteed to be in place.
_zv_skip() { echo "   $* — continuing without LENTICEL_TOKEN" >&2; return 1; }

_zv_get_token() {
  [[ -n "$ZV_SECRET_ID" ]] || return 1
  command -v zv &>/dev/null || return 1
  command -v jq &>/dev/null || return 1
  command -v timeout &>/dev/null || return 1
  local out
  out=$(timeout 5s zv get -id "$ZV_SECRET_ID" --not-safe --output json </dev/null 2>&1) \
    || { _zv_skip "zv failed or timed out"; return 1; }
  case "$out" in
    *"not logged in"*) _zv_skip "Zoho Vault: not logged in (zv login && zv unlock)"; return 1 ;;
    *"zv unlock"*)     _zv_skip "Zoho Vault is locked (zv unlock)"; return 1 ;;
  esac
  jq -re '.secret.secretData[] | select(.id == "password") | .value' <<< "$out" 2>/dev/null \
    || _zv_skip "no password field on Zoho Vault secret ${ZV_SECRET_ID}"
}

if [[ -z "${LENTICEL_TOKEN:-}" ]]; then
  if [[ "${CODESPACES:-}" == "true" ]]; then
    echo ""
    echo "⚠️  WARNING: Running in a GitHub Codespace but LENTICEL_TOKEN is not set."
    echo "   Fix: github.com → Settings → Codespaces → Secrets → New secret"
    echo "   Name: LENTICEL_TOKEN  |  Value: FRP_AUTH_TOKEN from lenticel server/.env"
    echo "   Then rebuild / reopen this Codespace."
    echo ""
  elif command -v zv &>/dev/null; then
    echo "Trying Zoho Vault (zv) non-interactively..."
    LENTICEL_TOKEN="$(_zv_get_token || true)"
  fi
fi

# ---- delegate to lenticel installer ----
LENTICEL_REPO="${LENTICEL_REPO:-avdi/lenticel}"
LENTICEL_BRANCH="${LENTICEL_BRANCH:-main}"

curl -fsSL "https://raw.githubusercontent.com/${LENTICEL_REPO}/${LENTICEL_BRANCH}/client/install-frpc.sh" \
  | LENTICEL_TOKEN="${LENTICEL_TOKEN:-}" \
    LENTICEL_SERVER="${LENTICEL_SERVER:-avdi.dev}" \
    bash
