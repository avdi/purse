#!/bin/bash
# Upgrade git to latest on Linux (apt) or macOS/Linux (brew).
#
# git >= 2.48 is required for worktree.useRelativePaths.
# Run manually when needed.
#
# Strategy:
#   1. apt systems: try ppa:git-core/ppa (Ubuntu). Falls back to brew if the
#      PPA add fails (e.g. Debian/Codespaces which don't support Ubuntu PPAs).
#   2. brew available: brew install git.

set -euo pipefail

_git_ver="$(git --version 2>/dev/null | awk '{print $3}')"

if [ -n "$_git_ver" ] && dpkg --compare-versions "$_git_ver" ge 2.48 2>/dev/null; then
  echo "→ git ${_git_ver} >= 2.48, no upgrade needed"
  exit 0
fi

echo "→ git ${_git_ver:-missing} < 2.48; upgrading..."

_upgraded=false

if command -v apt-get >/dev/null 2>&1; then
  echo "  trying ppa:git-core/ppa..."
  sudo apt-get install -y --no-install-recommends software-properties-common
  if sudo add-apt-repository -y ppa:git-core/ppa 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y git
    _upgraded=true
  else
    echo "  ppa:git-core/ppa failed (not Ubuntu?); will try brew..."
  fi
fi

if ! $_upgraded; then
  if command -v brew >/dev/null 2>&1; then
    echo "  installing via brew..."
    brew install git
    _upgraded=true
  fi
fi

if ! $_upgraded; then
  echo "⚠️  Could not upgrade git: no supported method available (tried apt PPA, brew)" >&2
  exit 1
fi
