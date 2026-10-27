---
name: exec-prefix
description: >
  Build a `script/exec` that works as one universal prefix for project
  commands, on the host, inside a devcontainer, in CI, and on cloud agent boxes,
  so every command gets the right environment (starting the container first when
  it must). Covers the two markers, the detection order, fail-open behavior,
  PATH hygiene, crossing variables, exit codes, per-script stances, and how
  agent hooks reach the environment. Use when adding or fixing `script/exec` in
  a project, when commands behave differently on host and in the container, when
  a commit or edit hook breaks outside the container, or when documenting
  "how do I run X here".
---

## The goal

Every project command is written the same way, wherever the caller sits:

```sh
script/exec bundle exec rspec spec/models
script/exec RAILS_ENV=test script/dummy-rails db:prepare
script/exec bundle exec rake lint
```

The caller never decides "am I in the container?". `script/exec` decides, and
it is the one place that chooses the environment. Scripts do not wrap
themselves; the caller writes the prefix. Docs, hooks, CI steps and cloud
manifests all use the same prefix.

## Two markers, never PATH or hostname

Guessing from PATH or hostname goes wrong in ways that are hard to see (a
version manager's shim puts the wrong Ruby first and nothing complains). Two
explicit markers decide instead:

| Marker | Set by | Meaning |
|---|---|---|
| `<PROJECT>_ENV=container\|native` | compose files, CI workflow, a cloud environment's own config | A project environment exists on this box, of this kind. |
| `SCRIPT_EXEC_ACTIVE=1` | `script/exec` only | The environment is already established for this process tree. |

Only the value `1` counts for `SCRIPT_EXEC_*` markers. `SCRIPT_EXEC_ACTIVE=true`
or `=0` must not match; a stray empty or false value that counted as set would
skip the environment silently.

A workflow's `env:` reaches only that workflow's steps, never an agent session.
A cloud agent's marker goes in the cloud environment's own configuration.

## Path order

```
nested   SCRIPT_EXEC_ACTIVE=1   run the command unchanged
bypass   SCRIPT_EXEC_BYPASS=1   run as the caller's environment has it (say so on stderr)
inside   <PROJECT>_ENV set, or detected: establish the environment, then run
outside  re-enter through script/exec in the container, then run there
```

`outside` is taken only when asked (`SCRIPT_EXEC_DOCKER=1`, or the cloud
topology says container) or when detection finds no toolchain and docker exists.

### Detection, with `<PROJECT>_ENV` unset

```bash
detect_environment() {
  if inside_a_container;        then project_env=container
  elif container_was_asked_for; then project_env=outside
  elif toolchain_present;       then project_env=native      # ruby and bundle on PATH
  elif command -v docker >/dev/null; then project_env=outside
  else
    note "no ruby toolchain and no docker found; running natively, so expect the command to say what is missing"
    project_env=native
  fi
}
```

`inside_a_container` is `[[ -f /.dockerenv || $DEVCONTAINER == true || -n $REMOTE_CONTAINERS ]]`.
Make the marker file overridable by env var so specs can fake it.

An unrecognised `<PROJECT>_ENV` value is noted on stderr and detected over, not
refused.

## Fail open

An early version of this pattern exited 64 from any "guarded"
script not started through it, and wedged every environment that had never heard
of the marker (an older devcontainer, a host with a working Ruby, a fresh cloud
box). It was reverted and rebuilt fail-open. The rule:

- With nothing said, run the command natively. An environment that predates the
  marker works unchanged.
- No toolchain and no docker: still run natively, with a one-line note. The
  command then reports what is missing in its own words, which beats a wrapper
  error.
- Exit codes of the script's own are only for a run that cannot happen:
  `64` no command, `65` working directory the container does not mount,
  `69` the container route was taken and no container is available (or may be
  started).
- Per-script guards print `foo: not started through script/exec` on stderr and
  carry on. They never exit.

## Establishing the environment (the `inside` path)

Sanitize PATH, then export both markers and exec:

```bash
export <PROJECT>_ENV=$project_env SCRIPT_EXEC_ACTIVE=1
PATH=$(established_path)
```

`established_path`:

- drops version-manager shim and install entries (`*/mise/shims`,
  `*/mise/installs/*`) and another checkout's `script/` directory (a worktree
  can inherit its sibling's);
- on `container`, puts the image's Ruby bin first (`/usr/local/bin` when it has
  a `ruby`);
- appends this checkout's `script/`;
- **keeps the caller's PATH if the rewrite would leave no Ruby.** Surgery that
  loses the only Ruby is worse than no surgery. Check with
  `PATH=$candidate command -v ruby`.

Leading `VAR=val` arguments mean `env VAR=val command`:

```bash
run_command() {
  [[ ${1:-} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && exec env "$@"
  exec "$@"
}
```

## Reaching a container (the `outside` path)

For a devcontainer:

```bash
id=$(docker ps --quiet --filter "label=devcontainer.local_folder=$root" | head -n1)
[[ -n $id ]] || { start_devcontainer; id=$(...); }       # unless SCRIPT_EXEC_NO_START=1 (exit 69)
exec docker exec "${tty_flags[@]}" -w "$container_cwd" "$id" \
  env "${assignments[@]}" "$container_root/script/exec" "$@"
```

- Find the container by its `devcontainer.local_folder` label, so each worktree
  gets its own. Start it with `devcontainer up --workspace-folder "$root"` when
  down; no `devcontainer` CLI means exit 69 with a message.
- Re-enter through `script/exec` inside, so the `inside` path (PATH hygiene,
  markers) runs there too.
- Map paths: the devcontainer mounts the checkout's parent at `/workspaces`.
  Translate both the working directory and the script path; a directory outside
  the mount is exit 65.
- TTY only when both stdin and stdout are terminals (`-it` vs `-i`), so piped
  use and hooks keep working. Signals are not forwarded without a TTY; say so in
  the header.
- Cross only an allowlist of the caller's environment: `RAILS_ENV`, `CI`, paid-
  API opt-ins, and `SCRIPT_EXEC_*`, minus the markers that choose the route
  (`SCRIPT_EXEC_DOCKER`, the container-marker override), which describe this box,
  not the container. Never forward the whole environment.
- For a cloud platform with its own container topology
  (`CLOUDDEV_TOPOLOGY=container`), route through that platform's exec wrapper
  instead. See the `clouddev` skill.

## Variables callers get

| Variable | Effect |
|---|---|
| `SCRIPT_EXEC_DOCKER=1` | Run in the devcontainer through docker, whatever the box has. |
| `SCRIPT_EXEC_NO_START=1` | Never start a container; exit 69 when none runs. Every hook sets it. |
| `SCRIPT_EXEC_BYPASS=1` | Run as the caller's environment has it, for an unusual run such as testing a script on the host. |

## Script stances

Every file under `script/` declares one stance in a `# script-stance:` comment
among its first lines, and a lint (`rake lint:script_stances`) enforces it:

| Stance | Meaning |
|---|---|
| `guarded` | Needs the project environment. Notes "not started through script/exec" on stderr and carries on. Carries the guard lines verbatim. |
| `host-only` | Talks to Docker or the host (starts the container, publishes images). Runs outside the environment; no guard. |
| `portable` | Works anywhere (hook shims, `script/exec` itself). No guard. |

The lint compares guard lines character for character, so copies cannot drift:

```bash
[[ ${SCRIPT_EXEC_ACTIVE:-} == 1 || ${SCRIPT_EXEC_BYPASS:-} == 1 ]] || echo "${0##*/}: not started through script/exec" >&2
```

A new script with no stance fails lint. That is what keeps the tree honest
as scripts are added.

## Hooks reach the environment through it too

- **Pre-commit hook** (an agent's `PreToolUse` on Bash): runs the linters
  through `script/exec` with `SCRIPT_EXEC_NO_START=1`, in a login shell so a
  version manager activates the pinned Ruby. It must not start a container as a
  side effect of a commit. When the checkout has no `script/exec`, or it exits
  64/65/69 (it could run nothing), lint with the caller's own `bundle` instead.
  Lint fails the commit only by failing.
- **Post-edit lint hook**: resolves the edited file's own git toplevel and runs
  there, against that worktree's Gemfile, so autocorrect edits that worktree's
  file. Ignore files in no worktree of the project. A hook that uses the
  session's cwd lints the wrong checkout.
- **SessionStart hook**: one bare call to the boot script, the same on every
  platform.
- Hook command-pattern matching belongs in the hook script, not in the agent's
  matcher: matchers match tool names only, and other agents ignore Claude Code's
  `if` field. Fail open on anything not positively identified as a commit.

## Specs

Spec the script hermetically with fake `docker`, `devcontainer`, `ruby` on a
temp PATH. Clear every ambient marker first (`<PROJECT>_ENV`, `SCRIPT_EXEC_*`,
`CI`, `DEVCONTAINER`), or CI's environment changes the path an example takes.
Cases worth having:

```
asks for a command when given none           (64)
counts only 1 for each marker
nested: runs unchanged, never touches docker
bypass: says so, runs unchanged
inside: marks the tree established; image Ruby first; shims dropped;
        other checkout's script/ dropped; keeps PATH if that leaves no Ruby
passes stdin and the exit status through; leading VAR=val means env
unset env: native when toolchain present even with docker; note + native
        when neither; devcontainer when no toolchain and docker exists
asked for container with no docker           (69)
outside: runs through script/exec in the container at the mapped directory;
        carries SCRIPT_EXEC_* across; 65 outside the mount;
        container down: 69 with NO_START, else starts it and runs
clouddev container topology: boots, then runs there; 69 with NO_START
```

## Adopting it in a project

1. Write `script/exec`, with the project's marker name (`<PROJECT>_ENV`).
2. Add stance headers to every script, the guards to the `guarded` ones, and the
   `script_stances` lint to the project's lint task.
3. Put the prefix on every command in docs, `AGENTS.md`, CI steps, compose
   `command:`s, the cloud manifest's `exec`, and hooks.
4. Set the marker where it belongs: compose files (`container`), CI workflow
   (`native`), cloud environment config (`native` or the topology value).
5. Make the devcontainer's create step fail on `.ruby-version` drift rather than
   install a second Ruby.
6. Add the specs above.

## Anti-patterns

- Choosing the environment from PATH, hostname, or "is `ruby` on PATH?" alone.
- Guarded scripts that `exit` when not started through the wrapper. Note and
  carry on.
- Rewriting PATH without checking a Ruby survives.
- Forwarding the caller's whole environment into the container.
- Starting a container from a commit hook.
- A hook that lints or runs in the session's cwd rather than the edited file's
  checkout.
- Each script wrapping itself in `script/exec`. The caller writes the prefix.
- Treating any non-empty marker value as set.
