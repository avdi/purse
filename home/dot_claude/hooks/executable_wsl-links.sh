#!/usr/bin/env bash
# Stop hook: list Windows-clickable file:// links for local paths in the final reply.
set -euo pipefail

MAX_LINKS=10

running_under_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] && command -v wslpath >/dev/null; }

final_reply() {
  local input=$1 transcript
  jq -r '.last_assistant_message // empty' <<<"$input" | grep . && return 0
  transcript=$(jq -r '.transcript_path // empty' <<<"$input")
  [ -r "$transcript" ] || return 0
  jq -rs '
    (map(.type == "user" and (.message.content | type == "string")) | rindex(true) // -1) as $last_prompt
    | .[$last_prompt + 1:] | map(select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text) | join("\n")
  ' "$transcript"
}

path_candidates() {
  sed -E 's#[A-Za-z][A-Za-z0-9+.-]*://[^[:space:])>]+##g' \
    | grep -oP '(?<![\w:/.@-])(~|\.{1,2})?/?[\w.@+-]+(/[\w.@+-]+)+(?=[:\s)`"'"'"',.;]|$)|(?<![\w:/.@-])(~|\.{1,2})?/[\w.@+-]+(?=[:\s)`"'"'"',.;]|$)' \
    || true
}

absolute_existing() {
  local cwd=$1 candidate path
  while IFS= read -r candidate; do
    path=${candidate/#\~/$HOME}
    case $path in /*) ;; *) path="$cwd/$path" ;; esac
    [ -e "$path" ] && realpath -- "$path"
  done
}

percent_encode_uri_path() { sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/#/%23/g' -e 's/?/%3F/g'; }

windows_file_uri() {
  local mixed
  mixed=$(wslpath -m -- "$1")
  case $mixed in
    //*) printf 'file:%s\n' "$mixed" | percent_encode_uri_path ;;
    *)   printf 'file:///%s\n' "$mixed" | percent_encode_uri_path ;;
  esac
}

main() {
  running_under_wsl || exit 0
  local input cwd path
  input=$(cat)
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  : "${cwd:=$PWD}"

  local links=()
  while IFS= read -r path; do
    links+=("$(windows_file_uri "$path")")
  done < <(final_reply "$input" | path_candidates | absolute_existing "$cwd" | awk '!seen[$0]++' | head -n "$MAX_LINKS")

  [ ${#links[@]} -gt 0 ] || exit 0
  printf '%s\n' "${links[@]}" | jq -Rsc '{systemMessage: ("Windows links:\n" + .)}'
}

main
