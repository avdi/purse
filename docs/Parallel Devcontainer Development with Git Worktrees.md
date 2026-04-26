---
tags: [devcontainer, git-worktree, parallel-development, infrastructure]
created: 2026-04-26
status: investigation
---

# Parallel Devcontainer Development with Git Worktrees

## Problem

Goal: run multiple parallel lines of development on the same project — multiple branches, multiple agents, isolated databases and processes — using **stock devcontainer definitions** with minimal host-side customization.

Constraints discovered through testing:

- VSCode's "open worktree as devcontainer workspace" feature is experimental, unreliable, and ~6–12 months from production-ready.
- The relative-worktree path support (`extensions.relativeWorktrees`) that would make this clean requires **git 2.48+** (Jan 2025), which is absent from Ubuntu 24.04 (ships 2.43), Debian stable, and most off-the-shelf devcontainer base images.
- Maintaining custom git builds on host *and* in every devcontainer image is a tax that defeats the "stock devcontainer" goal.
- Host-path-to-container-path identity mounting works but imposes more host layout control than is desirable across many projects.

## Why this is hard, mechanically

Git worktrees use three pointer files, and which ones are relative vs absolute matters enormously:

| File | Points to | Path style on stock git | Path style on git 2.48+ |
|---|---|---|---|
| Umbrella `.git` (gitfile) | `.bare/` | **Relative** (old, works everywhere) | Relative |
| Worktree `<wt>/.git` | `.bare/worktrees/<n>/` | **Absolute** | Configurable relative |
| `.bare/worktrees/<n>/gitdir` | `<wt>/.git` | **Absolute** | Configurable relative |

The umbrella gitfile uses the same mechanism as git submodules — relative paths have worked there for years (`gitrepository-layout(5)`).

The worktree internal pointers are the problem. They're absolute on stock git, which means:
- Host and container see the worktree at different paths → git breaks.
- `git worktree repair` rewrites them to whatever paths are correct **right now**, but they can't be simultaneously correct for both views.

This is what `extensions.relativeWorktrees` in git 2.48 fixes.

## Approaches Considered

### 1. Path-identity mount (host path == container path)

Mount `~/dev/myproject` to `~/dev/myproject` inside the container. Sidesteps the absolute-path problem entirely because there's only one set of paths.

- ✅ Works on stock everything.
- ✅ No `git worktree repair` needed.
- ❌ Imposes host directory structure that won't be tenable across the variety of projects worked on.
- ❌ Particularly awkward on macOS Docker Desktop and in Codespaces.

**Verdict:** Rejected — too much host control required.

### 2. VSCode experimental worktree-mounting flag + git 2.48 everywhere

The "official" forward path: each worktree opens as its own devcontainer, VSCode auto-mounts the parent `.git` repo, relative worktree paths make it all portable.

- ✅ Will be the right answer eventually.
- ❌ Experimental flag is unreliable today.
- ❌ Requires git 2.48 on host and in every container.
- ❌ Most upstream devcontainer base images don't have new enough git.

**Verdict:** Wait 6–12 months and revisit.

### 3. Umbrella mount + `git worktree repair` on container start

Each worktree opens as its own devcontainer workspace. The devcontainer config mounts the *umbrella* (parent of the worktree) into the container at a stable path like `/umbrella`, and runs `git worktree repair` on `postStartCommand` to fix the absolute paths to the container's view.

- ✅ Works on stock git (`worktree repair` has been in git since 2.30 / 2021).
- ✅ Each worktree gets its own devcontainer (real isolation: separate compose project name, separate DBs, separate ports).
- ✅ No host-path constraints.
- ✅ Can be made transparent to non-worktree users (see "Upstreaming" below).
- ⚠️ **After container repairs paths to container-absolute, host-side git operations on the worktree will be broken until repaired from the host.** Mitigation: discipline (do git ops inside the container) or a host direnv hook that runs `git worktree repair` on `cd` into the worktree.
- ⚠️ Some tools may cache absolute paths from `.git` (some IDE git integrations, some build-tool incremental caches). One-time wipes may be needed on first repair.

**Verdict:** This is the working approach for now.

### 4. Same approach but with git 2.48 + `relativeWorktrees`

The `.bare/` umbrella layout works as advertised once worktree internal pointers are relative — no `repair` gymnastics needed at all.

- ✅ Cleanest version of approach #3.
- ⚠️ Requires git 2.48 on host (mild — Ubuntu git-core PPA, Homebrew, etc.) and in container (devcontainer feature can install it).
- ❌ Imposes a non-trivial dependency: not all collaborators will have new git, and devcontainer images need a feature added.

**Verdict:** Migration target once git 2.48+ is broadly available. Until then, fall back to approach #3.

## The `.bare/` Umbrella Layout

The directory pattern that makes worktrees first-class:

```
~/dev/myproject/
├── .bare/                ← bare git repo (no working files)
│   ├── HEAD
│   ├── objects/
│   ├── refs/
│   └── worktrees/        ← per-worktree metadata
│       ├── feature-x/
│       └── feature-y/
├── .git                  ← FILE containing: "gitdir: ./.bare"
├── .devcontainer/        ← optional shared template (see Upstreaming)
├── feature-x/            ← worktree, peer of the others
│   ├── .git              ← FILE pointing to .bare/worktrees/feature-x/
│   └── (project files)
└── feature-y/
    ├── .git
    └── (project files)
```

Bootstrap:

```bash
mkdir myproject && cd myproject
git clone --bare git@github.com:org/repo.git .bare
echo "gitdir: ./.bare" > .git
# Fix fetch refspec so worktree fetches update remote-tracking branches
git --git-dir=.bare config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git --git-dir=.bare fetch origin
git worktree add main main
```

After bootstrap, `cd main && git status` works as if it were a normal clone. `git worktree add feature-x feature-x` creates additional peer worktrees.

Properties:

- No worktree is privileged. Any can be removed with `git worktree remove`.
- The umbrella `.git` → `.bare` link is **relative** and works on any git version.
- Worktree internal pointers are absolute on stock git; relative on git 2.48+ with `extensions.relativeWorktrees=true`.
- CLI git, lazygit, magit, VSCode git, JetBrains git: all fine.
- GitHub Desktop and some older IDE integrations may get confused.

## Devcontainer Overlay (Approach #3)

Designed to be transparent to non-worktree users — they get stock behavior unless they opt in via host environment variables.

### `.devcontainer/devcontainer.json` (committed, upstream-friendly)

```json
{
  "name": "myproject",
  "dockerComposeFile": [
    "docker-compose.yml",
    "${localEnv:MYPROJECT_COMPOSE_OVERRIDE:docker-compose.noop.yml}"
  ],
  "service": "dev",
  "workspaceFolder": "${localEnv:MYPROJECT_WORKSPACE_FOLDER:/workspace}",
  "workspaceMount": "${localEnv:MYPROJECT_WORKSPACE_MOUNT:source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached}",
  "postStartCommand": ".devcontainer/post-start.sh"
}
```

### `.devcontainer/post-start.sh` (committed)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Only act if this looks like a worktree layout: a .git FILE (not dir)
# pointing into a bare repo we can find above us.
if [ -f .git ] && grep -q "^gitdir:" .git; then
  gitdir=$(sed 's/^gitdir: *//' .git)
  # If the gitdir reference is broken from the container's perspective,
  # find the bare repo and repair.
  if [ ! -d "$gitdir" ]; then
    bare=$(find /umbrella -maxdepth 3 -type d -name ".bare" 2>/dev/null | head -1)
    if [ -n "$bare" ]; then
      git -C "$(dirname "$bare")" worktree repair "$(pwd)"
    fi
  fi
fi
```

### `.devcontainer/docker-compose.noop.yml` (committed)

Empty override so the second compose file path resolves to something valid when no override is requested:

```yaml
services:
  dev: {}
```

### Behavior matrix

| User | Env vars set | Result |
|---|---|---|
| Stock contributor | none | Workspace mounts at `/workspace` as normal. Post-start `.git` check fails (it's a directory, not a file), no-op. **Identical to stock devcontainer.** |
| Worktree user | `MYPROJECT_*` set | Umbrella mounts at `/umbrella`. Workspace folder points into the right worktree subdir. Post-start runs `git worktree repair`. Per-worktree compose overrides apply. |

### Worktree user host setup

Set in shell rc, or per-umbrella via direnv:

```bash
export MYPROJECT_WORKSPACE_MOUNT="source=${HOME}/dev/myproject,target=/umbrella,type=bind,consistency=cached"
export MYPROJECT_WORKSPACE_FOLDER="/umbrella/$(basename $PWD)"
export MYPROJECT_COMPOSE_OVERRIDE=".devcontainer/docker-compose.worktree.yml"
```

The worktree-specific compose override lives in the umbrella (gitignored, not committed) and adds per-worktree DB names, port offsets, queue namespaces, etc. Example:

```yaml
# ~/dev/myproject/.devcontainer/docker-compose.worktree.yml
services:
  dev:
    environment:
      WORKTREE_NAME: ${WORKTREE_NAME:-unknown}
      DATABASE_URL: postgres://postgres@db:5432/myapp_${WORKTREE_NAME:-unknown}
```

`WORKTREE_NAME` can be derived per-worktree via direnv `.envrc` files.

## Caveats and Honest Risks

1. **`${localEnv:VAR:default}` substitution with complex defaults containing `:` and `=` may be finicky.** Test before committing. Worst-case fallback: ship two devcontainer configs and use VSCode's multi-config picker.

2. **Heuristic worktree detection in post-start.sh.** Assumes `.bare/` convention and finds it via `find` under `/umbrella`. If someone uses a different worktree layout, the script no-ops harmlessly but provides no value.

3. **Host/container repair conflict.** After the container repairs paths to container-absolute, host-side git operations break until host-repaired. Plan to either:
   - Do all git ops inside the container (recommended).
   - Add a host-side direnv hook on `cd` to re-repair to host paths.

4. **Upstream PR pitch.** ~30 lines of devcontainer scaffolding for a workflow most contributors won't use. Frame as: "invisible to anyone who doesn't opt in via env vars; unblocks parallel-agent workflows for those who do." Whether maintainers accept this varies.

5. **`postStartCommand` runs every start, not just create.** Correct here because gitdir files can drift between starts. `postCreateCommand` would only run once and break later.

## Implementation in `purse` (Personal Dotfiles)

The dotfiles repo (`avdi/purse`) is already wired as a VSCode/Codespace auto-dotfiles target via `install.sh`, which installs chezmoi if needed and runs `chezmoi apply`. This means: anything added to purse gets installed **automatically inside every devcontainer that opts in** to dotfiles, with zero project cooperation.

This is the leverage point that lets us push almost everything off the project's plate.

### Architecture: three implementation tiers

The same `.bare/` umbrella + repair strategy admits three implementation shapes, in increasing order of project independence:

**Tier A — Project ships parameterized devcontainer.** Original approach from the "Devcontainer Overlay" section above. Best isolation (per-worktree containers with full project-specific config), but requires upstream cooperation. Use this for projects you control or can PR to.

**Tier B — Purse drops an overlay file into each worktree.** Per-worktree containers, project's devcontainer config gets overridden by a worktree-root `.devcontainer.json` file dropped by `wt-add`. Globally gitignored. Project ships nothing; purse ships the overlay template and the script that places it.

**Tier C — Shared umbrella container, attach from N windows.** One container at the umbrella level, every VSCode window for any worktree attaches to it. Per-worktree isolation comes from direnv-derived env (`WORKTREE_NAME`, port offsets, namespaced `DATABASE_URL`). Loses per-worktree-container isolation but uses the most stock machinery and is the simplest to debug. Best for spike work and projects whose devcontainer is generic enough to host at the umbrella level.

All three tiers share the same purse-managed shell hooks, scripts, and direnv libraries. Only the devcontainer wiring differs.

### Layout in purse

Following purse's existing chezmoi conventions (`home/` source root, `dot_X` → `~/.X`, `executable_X` for exec bit, `run_once_` and `run_onchange_` script prefixes):

```
home/
├── dot_config/
│   ├── shell/
│   │   ├── env.sh                          ← existing
│   │   ├── aliases.sh                       ← existing
│   │   └── worktree.sh                      ← NEW: shell hooks (sourced from rc)
│   ├── git/
│   │   └── ignore                           ← NEW or extend: global excludes
│   ├── direnv/
│   │   └── lib/
│   │       └── worktree.sh                  ← NEW: worktree_isolate() function
│   └── worktrees/
│       ├── devcontainer-overlay.json.tmpl   ← NEW: template for Tier B
│       └── compose-override.yml.tmpl        ← NEW: per-worktree compose
├── dot_local/
│   └── bin/
│       ├── executable_wt-clone              ← NEW: bootstrap umbrella
│       ├── executable_wt-add                ← NEW: add worktree + drop overlay
│       ├── executable_wt-rm                 ← NEW: remove worktree
│       └── executable_wt-repair             ← NEW: idempotent path repair
├── .chezmoidata/
│   └── packages.yaml                         ← extend: add git-core PPA / brew
└── run_once_setup-shell.sh                   ← existing: source worktree.sh too
```

### Key file sketches

**`home/dot_local/bin/executable_wt-repair`** — runs inside containers and on host; idempotent and fast enough to invoke from shell init.

```bash
#!/usr/bin/env bash
# Idempotent worktree path repair. Bails out instantly if not in a worktree.
set -eu
[ -f .git ] || exit 0
grep -q "^gitdir:" .git || exit 0
gitdir=$(sed 's/^gitdir: *//' .git)
[ -d "$gitdir" ] && exit 0   # already correct, no-op
d=$(pwd)
while [ "$d" != "/" ]; do
  if [ -d "$d/.bare" ]; then
    git -C "$d" worktree repair "$(pwd)" 2>/dev/null || true
    exit 0
  fi
  d=$(dirname "$d")
done
```

**`home/dot_config/shell/worktree.sh`** — sourced by rc files (wired in via the existing `run_once_setup-shell.sh` mechanism). Triggers `wt-repair` on shell init when the cwd is inside a `.bare/` umbrella's worktree.

```bash
# Run wt-repair on shell init if we're in a worktree. Fast, idempotent.
# Adds negligible overhead because wt-repair bails immediately when not in
# a worktree.
command -v wt-repair >/dev/null && wt-repair
```

A more sophisticated variant uses a chpwd hook (zsh) or PROMPT_COMMAND (bash) to re-run on `cd`, but shell-init alone is usually enough because each VSCode terminal opens fresh in the workspace dir.

**`home/dot_config/direnv/lib/worktree.sh`** — provides `worktree_isolate()` for project `.envrc` files to opt into namespaced DBs/ports.

```bash
worktree_isolate() {
  export WORKTREE_NAME="${WORKTREE_NAME:-$(basename "$PWD")}"
  # Stable port offset 0-99 derived from worktree name
  export PORT_OFFSET=$(( $(echo -n "$WORKTREE_NAME" | cksum | cut -d' ' -f1) % 100 ))
  # Caller can use $WORKTREE_NAME to namespace DATABASE_URL etc.
}
```

A project's `.envrc` (committed, project-friendly) calls it conditionally:

```bash
# In project repo .envrc
if declare -f worktree_isolate >/dev/null; then
  worktree_isolate
  export DATABASE_URL="postgres://postgres@db:5432/myapp_${WORKTREE_NAME}"
fi
```

Without purse installed, `worktree_isolate` doesn't exist, the block is skipped, and the project gets default behavior. With purse, isolation happens automatically.

**`home/dot_config/git/ignore`** — global excludes so dropped overlay files never show up in `git status` on any project.

```
.devcontainer.json
.envrc.local
```

Git already reads `~/.config/git/ignore` per the XDG Base Directory spec, no `core.excludesFile` setting required.

**`home/dot_local/bin/executable_wt-clone`** — bootstrap an umbrella.

```bash
#!/usr/bin/env bash
set -euo pipefail
url="$1"
name="${2:-$(basename "$url" .git)}"
mkdir "$name" && cd "$name"
git clone --bare "$url" .bare
echo "gitdir: ./.bare" > .git
git --git-dir=.bare config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git --git-dir=.bare fetch origin
default=$(git --git-dir=.bare symbolic-ref --short HEAD)
git worktree add "$default" "$default"
echo "Umbrella ready at $(pwd). Default worktree: $default"
```

**`home/dot_local/bin/executable_wt-add`** — adds a worktree and drops the Tier B overlay if requested.

```bash
#!/usr/bin/env bash
set -euo pipefail
# Run from umbrella root.
branch="$1"
dir="${2:-$branch}"
mode="${WT_MODE:-tier-c}"   # tier-b or tier-c

git worktree add "$dir" "$branch" 2>/dev/null || git worktree add -b "$branch" "$dir"

case "$mode" in
  tier-b)
    cp ~/.config/worktrees/devcontainer-overlay.json "$dir/.devcontainer.json"
    ;;
  tier-c)
    # No per-worktree devcontainer file; expects umbrella-level container.
    ;;
esac
echo "Worktree $dir ready (mode: $mode)"
```

### Cross-platform considerations

Purse supports Linux/macOS/Windows. The worktree workflow is fundamentally Linux-container-centric, so:

- `wt-*` scripts and `worktree.sh` should be gated for non-Windows hosts in chezmoi templates: `{{ if ne .chezmoi.os "windows" }}` wrapping the whole script (returning empty makes chezmoi skip applying the file).
- Windows users running WSL get the Linux behavior automatically because chezmoi inside WSL reports `linux`.
- Native Windows host without WSL is unsupported for this workflow. That matches reality — devcontainers on native Windows host without WSL is itself a rough path.

### Timing caveat: dotfiles install vs project setup

VSCode's "Dev Containers: install dotfiles" hook runs `install.sh` (and therefore `chezmoi apply`) **after** the container's `postCreateCommand` and `postStartCommand`. This means:

- If a project's `postCreateCommand` runs `git status` or any git operation in the worktree, it will see broken paths because `wt-repair` hasn't been installed yet.
- The shell-init hook catches it on the first interactive terminal (which is fine for hand-driven work).
- VSCode's git extension reads git state at workspace open and may show spurious errors initially. They clear on first reload.

Mitigations:
- Tier A's project-side `postStartCommand` runs `wt-repair` directly using a script committed to the project, sidestepping the timing issue entirely. (The script can call out to `~/.local/bin/wt-repair` if purse is installed, otherwise fall back to inline logic.)
- For Tiers B/C, the dropped/umbrella `.devcontainer.json` overlay's `postStartCommand` can run `wt-repair` directly — but this requires `wt-repair` to be in the image already. Two options:
  1. Ship `wt-repair` as a dedicated devcontainer Feature pulled by the overlay's `features` block.
  2. Have the overlay's `postStartCommand` install just `wt-repair` (a single shell script, ~20 lines) inline before invoking it.

Option 2 is uglier but avoids needing to publish a feature. Option 1 is the right long-term shape if this pattern stabilizes.

## Recommended Build Order

1. **Bootstrap one project** with the `.bare/` umbrella layout via `wt-clone`, no devcontainer involvement. Get muscle memory for `git worktree add/list/remove` against a bare umbrella.
2. **Add the purse pieces incrementally:**
   - First `wt-repair` + `worktree.sh` shell hook + global gitignore entries. Verify shell init behavior on host.
   - Then `worktree_isolate` direnv lib + a test project `.envrc` that uses it.
   - Then `wt-clone`/`wt-add`/`wt-rm` scripts.
3. **Pick a tier and try it on one project.** Tier C is the lowest-risk starting point — a single shared container, attach from multiple windows, validate that direnv-driven isolation actually keeps processes from stepping on each other.
4. **Promote to Tier B** if per-worktree-container isolation turns out to matter (heavy build caches, language servers that don't multiplex, etc.) by adding the overlay drop to `wt-add`.
5. **Promote selected projects to Tier A** by upstreaming the parameterized devcontainer config — but only after Tier B is proven in your own use.
6. **Migrate to git 2.48 + `relativeWorktrees`** when the dependency is tolerable across host and container. At that point the `wt-repair` gymnastics can be retired entirely.

## Open Questions

- Can `${localEnv:...}` substitutions reliably handle the complex compose override pattern in Tier A, or does it need to be split into multiple env vars or a multi-config picker approach? Needs hands-on testing.
- For projects with existing committed `.devcontainer/devcontainer.json` (folder form): does a worktree-root `.devcontainer.json` (file form) take precedence, get ignored, or trigger a VSCode picker prompt? Tier B depends on this. Spec is ambiguous; needs empirical verification.
- Should `wt-repair` ship as a dedicated devcontainer Feature so Tier B/C overlays can declare it via `features:` and have it baked in, or stay as a chezmoi-installed script that requires the dotfiles install to run first?
- Direnv integration: should `worktree_isolate` be invoked automatically by an umbrella-level `.envrc` (so all worktrees inherit it via direnv's `source_up`-style mechanism), or only by explicit per-project opt-in? Auto is more magical but harder to reason about when things go wrong.
- Cross-platform behavior: macOS Docker Desktop's mount consistency story may need different `consistency=` defaults than Linux. Codespaces behavior should be tested separately.
- Should there be a corresponding cleanup hook in `wt-rm` that drops the worktree's namespaced database, or is leaving stale DBs around (named by worktree) acceptable for a workflow where worktrees are short-lived?

## Sources

This writeup is based on:
- The devcontainer.json reference spec (containers.dev) for `workspaceMount`, `workspaceFolder`, `${localEnv:VAR:default}` substitution, and `postStartCommand` semantics.
- VSCode Dev Containers docs for the dotfiles-in-container feature (`dotfiles.repository`, install command, run timing).
- `git-worktree(1)` and `gitrepository-layout(5)` for the gitfile and worktree pointer mechanics.
- The git 2.48 release notes for `extensions.relativeWorktrees`.
- The `avdi/purse` repo README and `install.sh` for the existing dotfiles conventions and the chezmoi source layout.
- chezmoi documentation for naming conventions (`dot_`, `executable_`, `run_once_`, `run_onchange_`, `.tmpl`) and template expansion semantics.
- Direct testing reports (yours) on the current state of VSCode's experimental worktree-mounting feature and stock-distro git versions.

Claims about how the pieces compose are reasoned from the specs, not from having watched this run in production for months. The Tier B precedence question (`.devcontainer.json` vs `.devcontainer/devcontainer.json`) and the dotfiles-install-vs-postCreate timing ordering are the two pieces I'd verify empirically before committing to a particular shape. Treat as a working hypothesis to validate, not as proven recipe.
