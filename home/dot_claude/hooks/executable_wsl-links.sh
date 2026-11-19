#!/usr/bin/env bash
# Stop hook: list host-clickable file:// links for local paths in the final reply.
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

# Turns a host path ("//wsl.localhost/Ubuntu/x", "C:/x" or "/Users/x") into a file:// URI.
file_uri() {
  case $1 in
    //*)  printf 'file:%s\n' "$1" ;;
    /*)   printf 'file://%s\n' "$1" ;;
    *)    printf 'file:///%s\n' "$1" ;;
  esac | percent_encode_uri_path
}

in_devcontainer() { [ -n "${PURSE_HOST_WORKSPACE:-}" ]; }

host_workspace_name() { basename -- "$PURSE_HOST_WORKSPACE"; }

container_workspace() {
  local name; name=$(host_workspace_name)
  awk -v name="$name" '{ n = split($5, parts, "/"); if (parts[n] == name) { print $5; exit } }' /proc/self/mountinfo \
    | grep . || echo "/workspaces/$name"
}

# Prints the host-side URI for a container path; nothing when it is outside the workspace mount.
devcontainer_file_uri() {
  local workspace=$1 path=$2
  case $path in
    "$workspace") file_uri "$PURSE_HOST_WORKSPACE" ;;
    "$workspace"/*) file_uri "$PURSE_HOST_WORKSPACE${path#"$workspace"}" ;;
  esac
}

wsl_file_uri() { file_uri "$(wslpath -m -- "$1")"; }

link_for() {
  if in_devcontainer; then devcontainer_file_uri "$(container_workspace)" "$1"; else wsl_file_uri "$1"; fi
}

main() {
  in_devcontainer || running_under_wsl || exit 0
  local input cwd path uri
  input=$(cat)
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  : "${cwd:=$PWD}"

  local links=()
  while IFS= read -r path; do
    uri=$(link_for "$path"); [ -z "$uri" ] || links+=("$uri")
  done < <(final_reply "$input" | path_candidates | absolute_existing "$cwd" | awk '!seen[$0]++' | head -n "$MAX_LINKS")

  [ ${#links[@]} -gt 0 ] || exit 0
  printf '%s\n' "${links[@]}" | jq -Rsc '{systemMessage: ("Host links:\n" + .)}'
}

main
