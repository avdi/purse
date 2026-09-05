# devcontainer-lookup.sh — find the running devcontainer for a workspace.
#
# Sourced by ~/.local/bin/dcsh and ~/.local/bin/dc. Defines functions only, and
# sets no shell options, so it is safe to source under any caller's flags.
#
# The devcontainer CLI matches containers by deriving a
# `devcontainer.local_folder` label from --workspace-folder. Two things defeat
# that: a container started by VS Code on Windows against a WSL workspace holds
# a UNC path (\\wsl.localhost\...) in the label while callers pass the Linux
# path; and one container serves every git worktree of a repository — they are
# all mounted inside it — while the label names only whichever worktree started
# it. So resolve the id here and pass it as --container-id, which skips
# local_folder matching entirely.

# Nearest ancestor of $PWD holding a devcontainer config; $PWD if there is none,
# leaving the devcontainer CLI to report the error.
devcontainer_find_workspace() {
  local dir
  dir="$(pwd)"
  while true; do
    if [[ -d "$dir/.devcontainer" || -f "$dir/.devcontainer.json" ]]; then
      echo "$dir"
      return
    fi
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  pwd
}

devcontainer_config_label() {
  docker inspect "$1" \
    --format '{{index .Config.Labels "devcontainer.config_file"}}' 2>/dev/null
}

# A container whose labels point at exactly this folder. The config_file label
# is a Linux path under the workspace even for VS Code/WSL containers, so it
# serves where local_folder doesn't.
devcontainer_detect() {
  local folder="$1" id
  id=$(docker ps -q \
    --filter "label=devcontainer.local_folder=$folder" 2>/dev/null | head -1)
  if [[ -n "$id" ]]; then echo "$id"; return 0; fi
  for id in $(docker ps -q --filter "label=devcontainer.config_file" 2>/dev/null); do
    if [[ "$(devcontainer_config_label "$id")" == "$folder/"* ]]; then
      echo "$id"
      return 0
    fi
  done
  return 1
}

# A container started from any *other* worktree of the same repository, which
# serves this worktree just as well.
# Prints "<container-id><TAB><that container's worktree>".
devcontainer_detect_sibling() {
  local folder="$1" id config worktree
  local -a worktrees=()
  mapfile -t worktrees < <(
    git -C "$folder" worktree list --porcelain 2>/dev/null |
      sed -n 's/^worktree //p'
  )
  [[ ${#worktrees[@]} -gt 0 ]] || return 1
  for id in $(docker ps -q --filter "label=devcontainer.config_file" 2>/dev/null); do
    config="$(devcontainer_config_label "$id")"
    for worktree in "${worktrees[@]}"; do
      [[ "$worktree" == "$folder" ]] && continue
      if [[ "$config" == "$worktree/"* ]]; then
        printf '%s\t%s\n' "$id" "$worktree"
        return 0
      fi
    done
  done
  return 1
}

# This workspace's container, else a sibling worktree's.
# Prints "<container-id><TAB><the container's workspace>".
devcontainer_resolve() {
  local folder="$1" id
  if id="$(devcontainer_detect "$folder")"; then
    printf '%s\t%s\n' "$id" "$folder"
    return 0
  fi
  devcontainer_detect_sibling "$folder"
}
