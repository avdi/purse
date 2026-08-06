---
name: clouddev
description: >
  Make a devcontainer-based project runnable by cloud agent platforms (Claude
  Code cloud, Cursor cloud agents, Amp orbs, Copilot cloud agent, Augment
  Cosmos, Devin, Factory droids, Jules, Codespaces) — the platform tier model,
  the prepare/boot phase split every snapshotting platform imposes, the
  clouddev.yml manifest and its entrypoint scripts, path mapping between the
  agent's box and the dev environment, publishing a dev image to a registry,
  and splitting docker-compose so backing services (Postgres, Redis, CouchDB,
  Vault) come up without the app container. Use when porting a project to a
  cloud agent platform, when a cloud agent can't run tests or boot the app
  because backing services are missing, when adding a platform adapter, or when
  deciding whether a platform is worth supporting at all.
---

## The problem

Cloud agent platforms hand you a Linux box and a checkout and assume the
project's commands just work. That assumption holds for a single-process app
with no state. It fails for anything with backing services — a database, a
queue, a secrets store, a document store.

You have already solved this locally with a devcontainer. This skill is how
that work gets reused instead of re-derived per platform.

## The core insight

**Every platform's customization hook is single-image. None of them reads a
compose file.** Only devcontainer-native platforms (Codespaces, Gitpod/Ona,
Coder, Daytona) read `dockerComposeFile`.

So split the two concerns the devcontainer conflates:

| Concern | Artifact | Consumed by |
|---|---|---|
| **Toolchain** | a dev image in a registry | the platform (or your prepare script pulls it) |
| **Backing services** | a services-only compose file | **your** boot script, from inside the box |

The platform never sees your compose file. You run it yourself, from the box
the platform gave you:

```
platform provides:  a box with Docker + a checkout
your boot script:   docker compose -f <services compose> up -d
```

That is the whole trick. Everything below is bookkeeping around it.

Consequence for the local devcontainer: the `app` service becomes **optional**,
not deleted. Local behavior is unchanged; cloud simply doesn't start it.

The split pays a second time on Copilot, whose runner refuses `container:` but
honors an Actions **`services:`** block — which is exactly the services half of
a compose file, transcribed.

## Establish the tier first

Tier decides how much any of this costs. Do this before writing a line.

| Tier | Meaning | Cost |
|---|---|---|
| **0** | Bring your own machine | **nothing** — your devcontainer runs unmodified |
| **1** | Platform accepts your image | image-first; direct topology |
| **2** | Their image, real hooks for both phases | container topology; both phases attach |
| **3** | Their image, no usable per-session hook | `boot` must self-install or be agent-invoked |
| **4** | No contract to target | document as unsupported; do not work around it |

Tier 0 is far more available than the marketing suggests: Devin Outposts,
Factory BYOM, Coder (self-host-only), a self-hosted GitLab runner, Codespaces
via `gh codespace ssh`, or simply a headless agent CLI in your own CI —
`claude -p`, `droid exec`, `devin -p`, Junie headless are all the same shape.
When a stack is heavy, reaching for tier 0 beats fighting a tier 3 platform.

**One platform is worth singling out.** Ona (formerly Gitpod) has already built
this convention: `devcontainer.json` including `dockerComposeFile`, plus
`.ona/automations.yaml` whose triggers (`prebuild`, `postDevcontainerStart`,
`postEnvironmentStart`, `beforeSnapshot`) are the phase model with names on
them. When designing an adapter, read Ona's schema first — it is the closest
thing to a reference implementation.

See `references/platforms.md` for the full matrix.

## The two phases

Platforms disagree about almost everything except this: provisioning splits
into work whose **output is disk** and work that leaves **processes running**.
They snapshot the first and discard the second. Cursor states it plainly:

> *"Builds preserve disk state only. Running processes, exported shell
> variables, and in-memory caches don't continue into an agent run."*

| Phase | Output | Runs | Contains |
|---|---|---|---|
| **`prepare`** | disk | once per snapshot | deps, image pulls, builds, cache warming |
| **`boot`** | processes | every session | daemon start, `compose up`, dev servers |

**This is the line the devcontainer spec already drew.** Codespaces and Ona both
cut their prebuild at exactly the same place:

| Phase | devcontainer lifecycle commands |
|---|---|
| `prepare` | `onCreateCommand`, `updateContentCommand` |
| `boot` | `postCreateCommand`, `postStartCommand`, `postAttachCommand` |

Codespaces states it flatly: *"No `postCreateCommand` commands are run during
the creation of a prebuild."* So on devcontainer-native platforms the mapping is
free — you are not inventing a split, you are naming one that exists.

**The invariant that makes this portable:**

> `prepare` then `boot`, in sequence, must always be a valid full provisioning.

Platforms split them (Cursor `install`/`start`, Amp `setup`/`resume`, Cosmos
`provision_script`/`on_startup.sh`). Copilot has **only** a per-session hook and
calls both. Devin has **only** build-time hooks and calls `prepare`, leaving
`boot` to install itself. So neither script may assume the other ran in a
different process, and `prepare` must be safe to run immediately before `boot`.

### How `boot` attaches

Four modes. A project's adapter picks one per platform.

| Mode | Platforms | Mechanism |
|---|---|---|
| platform invokes per session | Cursor `start`, Amp `.agents/resume`, Claude Code `SessionStart`, Cosmos `on_startup.sh`, Copilot setup steps | direct call |
| **self-install** | Devin | `prepare` installs a systemd unit that fires on VM boot |
| **agent-invoked** | Jules, Factory managed | `AGENTS.md` tells the agent to run it — instruction, not guarantee |
| **persistent** | Factory managed Droid Computers | memory snapshot; runs **once, ever** |

Self-install is a real requirement on `boot`, not a footnote: it has to work as
a service unit, not only as a script something calls.

### Supervised service slots are a separate primitive

Three platforms offer a slot for long-running processes that is **not** a
lifecycle hook: Amp's `.amp/services.yaml`, Ona's `.ona/automations.yaml`
`services:`, Cursor's `terminals`. All supervisor- or tmux-backed, all visible
to the agent, all surviving pause/resume where a hook's children would not.

They invert `boot`'s contract, and the conflict is real:

| Platform | Requirement |
|---|---|
| Amp `.agents/resume` | **return within 10s** |
| Ona `commands.start` | **must block** — `docker compose up -d` exits and the service is marked Stopped |

These are different slots, not a contradiction. Where a supervised slot exists,
put the blocking foreground process there and give it a readiness probe; keep
`boot` for the fire-and-return case. Ona's `commands.ready` is the model — it
gates the Starting→Running transition *and* gates prebuild snapshotting.

### `boot` has a time budget

| Platform | Budget |
|---|---|
| Amp `.agents/resume` | **10 seconds**, then the agent starts anyway |
| Factory `SessionStart` | 60s default |
| Copilot | 59 min total, shared with the actual work |

So `boot` returns fast and health-gates in the background, writing progress to a
log `verify` can poll. A `boot` that blocks on four healthchecks races the
agent's first turn.

### Everything network-touching goes in `prepare`

Three platforms restrict the network **during the agent run but not during
provisioning**. Copilot is explicit:

> *"The firewall only applies to processes started by the agent via its Bash
> tool. It does not apply to … processes started in configured Copilot setup
> steps."*

Codex air-gaps the agent phase by default; Claude Code cloud applies access
levels to the session. A lazily-pulled image or a mid-task `bundle install`
fails — and on Copilot it fails by quietly appending a warning to the PR body.

### A shell setup script is the universal lowest common denominator

Every platform surveyed — across every tier — accepts *some* shell script at
provisioning time, and they all have the same shape: `.openhands/setup.sh`,
Amp's `.agents/setup`, Cursor's `install`, GitLab's `setup_script`, Codegen's
Setup Commands, Jules' one text box, Copilot's `steps`. That is why the manifest
declares script *paths* rather than inlining commands: the paths are the
portable part, and every adapter is a pointer at one.

Corollary: **most platforms do not read `devcontainer.json`.** Only the
devcontainer-native ones do (Codespaces, Ona, Coder's Dev Containers
integration, Gitpod-lineage tooling). Everywhere else your devcontainer is a
source of truth you *project from*, never a thing the platform consumes.

### `prepare` output is world-readable

Files written during `prepare` are baked into a snapshot that other sessions —
and on Cosmos, other **users** — boot from. Devin and Cosmos both warn about it.
Generate dev-only credentials in `boot`; never write a token in `prepare`.

## The contract

One visible anchor at the repo root. Everything else is declared, so projects
with different layouts adopt without moving files.

```yaml
# clouddev.yml
clouddev_version: 1

image: ghcr.io/acme/myproject-dev
image_tag_files:                       # content hash inputs for the tag
  - .devcontainer/Dockerfile
  - Gemfile.lock
  - yarn.lock
  - .ruby-version
  - .node-version

capabilities: [test, serve, browser, jobs]

scripts:
  prepare:  script/clouddev/prepare      # once per snapshot; output is disk
  boot:     script/clouddev/boot         # every session; output is processes
  refresh:  script/clouddev/refresh      # periodic; cheap and idempotent
  halt:     script/clouddev/halt
  exec:     script/clouddev/exec
  shell:    script/clouddev/shell
  path:     script/clouddev/path
  verify:   script/clouddev/verify

services:
  compose: docker/compose.services.yml
  env:     docker/clouddev.env          # localhost-topology overrides

paths:                                   # omit entirely when they're identical
  host:      /workspace
  container: /workspaces/myproject

ports:                                   # adapters map these to platform ingress
  app:  3000
  vite: 3036
```

`clouddev_version` lets the contract evolve without breaking adopted projects.

YAML, not TOML: repos in this space already carry JSON and YAML (compose,
workflows, devcontainer.json). A third format buys nothing.

### capabilities

The honest list of what the project can actually do on a cloud box. Adapters
and humans both read it; a project that can't do browser QA remotely says so
rather than failing halfway through a QA pass.

| Value | Means |
|---|---|
| `test` | the test suite runs green |
| `serve` | the app boots and answers HTTP |
| `browser` | headless (or Xvfb-backed) browser automation works |
| `jobs` | background workers run and drain a queue |

### Script contract

| Script | Must | Must not |
|---|---|---|
| `prepare` | be idempotent; do **all** network work (image pulls, dependency installs, cache warming); leave only disk behind | start any process — it will be discarded; write a credential to disk |
| `boot` | start backing services; **return fast** (10s budget on Amp), health-gating in the background to a log; be idempotent; work when installed as a **systemd unit**, not only when called | block on healthchecks; assume the network is reachable |
| `refresh` | be cheap and idempotent — `git fetch`, dependency top-up | do anything that belongs in `prepare` |
| `halt` | stop services, leave data volumes alone unless asked | |
| `exec` | run its argv in the dev environment; preserve the exit code; pass stdin through byte-exact; allocate a TTY only when `[ -t 0 ]`; rewrite paths by default (see below), with `--raw` to opt out | decide the TTY from the argument count; rewrite stdin; swallow a non-zero status behind a pipe |
| `shell` | start a login shell in the dev environment, **forwarding its argv** to that shell (`-c '…'`, a script path); **built on `exec`**, never on its own topology logic | duplicate what `exec` knows; force interactivity when stdin is a pipe |
| `path` | translate a path seen in dev-environment output into one the caller can open; take paths as argv or rewrite a stream on stdin; pass unmapped and relative paths through untouched; exit 0 always; be the **identity function** when the paths are identical | guess, canonicalize, or touch anything outside the declared roots |
| `verify` | exit non-zero when the environment is broken; **fail loudly**; test one thing per declared capability | mutate the repo or leave state behind |

`verify`'s loudness is not a style preference. On Copilot a non-zero exit in
setup **skips the remaining steps and starts the agent anyway** — a silently
half-built environment that fails later in ways that look like code bugs.
`AGENTS.md` must tell the agent to run `verify` before trusting the box.

### `refresh` is a real third phase

Five platforms independently rebuild a warm snapshot on a timer: Cosmos 12h
(opt-in), Devin ~24h, Cursor's staleness threshold 24h, Amp's snapshot reuse
24h, Claude Code cloud ~7 days. `refresh` is what runs then — cheap, idempotent,
keeps the snapshot current without redoing `prepare`.

Where a platform has no refresh hook, it is simply never called. Nothing else
changes.

## `exec` is the seam

`exec` is the only script that knows the topology. Nothing else branches.

```bash
# direct topology — the agent's box IS the dev environment
exec "$@"
```

```bash
# container topology — the dev environment is a container the agent talks to
[ -t 0 ] || no_tty=-T
exec docker compose -f docker/compose.services.yml exec ${no_tty:-} app "$@"
```

Decide the TTY from `[ -t 0 ]`, never from the argument count. Without `-T`
under a non-interactive caller Compose demands a TTY and the script dies; with
a forced `-T` an interactive session gets no line editing.

| Topology | Use when | Service hostnames | Cost |
|---|---|---|---|
| **direct** | the platform accepts your image | `localhost:<published>` — needs the env overlay | none |
| **container** | the platform's base image is fixed | compose service names, unchanged | a wrapper on every command; browser runs inside the container while the agent watches from outside |

Prefer direct. Use container only where the platform refuses a custom base
image.

Everything a project already has — `bin/dev`, a `serve` script, `rspec` — is
invoked *through* `exec` and needs no modification.

`shell` is then a one-liner built on `exec`, identical in both topologies —
which is why it never needs its own topology knowledge:

```bash
exec "$(dirname "$0")/exec" bash -l "$@"
```

Forwarding `"$@"` means `shell -c 'rake db:migrate'` and `shell some-script.sh`
both work, and inherit the shell's own semantics rather than a reinvented
subset.

**Both scripts must pipe cleanly from outside.** stdin, stdout, and stderr pass
straight through, and the exit code is the inner command's:

```bash
echo 'User.count' | clouddev/exec rails console      # stdin consumed inside
clouddev/exec rspec > out.txt 2> err.txt             # streams separated
clouddev/exec false; echo $?                         # 1
cat setup.sql | clouddev/shell                       # bash reads stdin as a script
```

That last case is why `shell` forwards rather than forcing interactivity: with
a piped stdin `bash -l` reads commands from it, which is the behavior a caller
already expects. No special-casing needed.

### Path mapping — the failure everyone forgets

Under the **container** topology the agent edits files on the host and runs
commands inside a container. If the repo sits at a different absolute path on
each side, every path crossing that boundary is wrong — and it fails *late*,
in ways that read as unrelated bugs:

- **Inbound**: the agent passes `/workspace/spec/user_spec.rb`; the container
  has it at `/workspaces/myproject/spec/user_spec.rb`. File not found.
- **Outbound** (worse, because it looks like the tool is broken): a stack
  trace, lint report, JUnit XML, coverage file, or Playwright screenshot path
  names the *container's* path. The agent tries to open it on the host and gets
  nothing.
- **git worktrees**: a worktree's `.git` file holds an **absolute** gitdir
  path. Mounted at a different path, git inside the container fails outright —
  which takes out any worktree-based workflow.

**Rule: mount the repo at the same absolute path on both sides.** This deletes
the entire class of problem rather than managing it. It costs nothing:

```yaml
# in the services compose file, for the app service
volumes:
  - ${CLOUDDEV_HOST_ROOT}:${CLOUDDEV_HOST_ROOT}
working_dir: ${CLOUDDEV_HOST_ROOT}
```

`exec` then also forwards the **caller's cwd**, so relative paths work when
invoked from a subdirectory:

```bash
exec docker compose exec ${no_tty:-} -w "$PWD" app "$@"
```

When identical paths are genuinely impossible — a platform that dictates the
checkout location *and* an image that dictates its own — declare the mapping:

```yaml
# clouddev.yml
paths:
  host:      /workspace          # where the platform put the checkout
  container: /workspaces/myproject
```

#### `path` — "what is *my* path to the path I'm looking at?"

Automatic stream rewriting is not enough, because the question arrives after
the fact: an agent reads a stack trace, a test failure, a coverage report, a
screenshot location, and needs to open the file. Give it something to ask.

```bash
path PATH...            # each arg is a path; one translated path per line
path                    # no args: read stdin, rewrite occurrences in-stream
path --to-container …   # opposite direction
```

**Two modes, distinguished by whether there are arguments** — no flag needed,
because the semantics genuinely differ:

| Mode | Unit of translation | Use |
|---|---|---|
| argv | the whole token is a path | `path "$(cat .last-failure)"` |
| stdin | occurrences *within* each line | `exec --raw rspec 2>&1 \| path` |

Arguments win when both are present; stdin is ignored, not an error.

**Direction.** Default is `--to-host`: *"I saw this in output from the dev
environment — give me the path I can open."* That is the question that actually
gets asked. `--to-container` exists mainly for `exec`'s own internals; an agent
passing a path to a command never needs it, because `exec` already rewrites
argv. Named for the two `paths:` keys rather than `--reverse`, which is
unanswerable at a call site.

Contract:

- **Exit 0 always.** Pass-through is a legitimate outcome, not an error.
- Only absolute paths prefixed by a declared root, at a path-component
  boundary, are translated. Everything else — relative paths, absolute paths
  outside the roots — passes through **unchanged**. See *What gets rewritten*
  below; `path` and `exec` share one implementation, so they cannot drift.
- **No canonicalization.** Never `realpath`, no `~` expansion, no `..`
  collapsing, trailing slashes preserved. Resolving a symlink can walk you out
  of the declared root and yield a path that is correct but useless.
- **Under the direct topology it is the identity function** — same shape as
  `exec` being `exec "$@"` there. Every project ships it; it does nothing when
  there is nothing to do. That is what makes it safe for an agent to call
  unconditionally.

Two edges worth knowing:

**Stack-trace suffixes work for free.** Prefix-only rewriting leaves the tail
of the token intact, so there is no `:LINE:COL` parsing anywhere:

```
path /workspaces/myproject/app/models/user.rb:42:in 'call'
  → /workspace/app/models/user.rb:42:in 'call'
```

Agents paste these constantly. It matters that it falls out of the design
rather than being a special case.

**`file://` URLs translate only in stdin mode**, where occurrence-anywhere
matching catches the embedded path; argv mode's prefix check won't match
`file:///workspaces/…`. An acceptable asymmetry, but one to know rather than
discover.

#### Rewriting is `exec`'s default

Most tools an agent invokes — rspec, eslint, tsc, a coverage reporter, a
browser driver — have no idea they live in a path-mapped world and will happily
print paths the caller can't open. Asking every caller to remember to translate
is a rule that gets followed until the one time it matters. So `exec` rewrites
by default. Scoped:

| Direction | Default | Why |
|---|---|---|
| **argv, to-container** | always rewrite | cheap, unambiguous, no downside |
| **stdout/stderr, to-host** | rewrite **only when the stream is not a TTY** | preserves color, progress bars, and interactivity for a human |
| **stdin** | **never rewrite** | stdin is data — a SQL dump or a tarball must arrive byte-exact |

That last row is the line worth holding: **argv is a command, stdin is data.**

**What gets rewritten — the whole rule:**

> An absolute path whose prefix is exactly one of the two declared roots, at a
> path-component boundary. Nothing else, ever.

Everything that follows from that:

- **Relative paths are never touched.** They're already correct on both sides,
  because `exec` forwards the caller's cwd. Rewriting them would be guessing.
- **Absolute paths outside the roots pass through unchanged.**
  `/usr/lib/ruby/3.3.0/set.rb` is a real path in the container with no
  counterpart outside it; returning it honestly beats inventing a host path
  that doesn't exist.
- **The boundary must be a path component.** With a root of `/arglebarf`,
  rewrite `/arglebarf` and `/arglebarf/app/x.rb`; leave `/arglebarfle/x.rb`
  alone. A naive substring match gets this wrong and the damage is silent.
- **No inference.** No basename matching, no "this looks like a file in the
  repo," no filesystem probing to see which candidate exists. A declared
  prefix or nothing.

That conservatism is precisely what earns the default. The rewrite can only
ever act on strings whose meaning is already known, so leaving it on costs
nothing in the cases it doesn't understand.

Escape hatches, both needed in practice:

- `exec --raw …` — no rewriting at all. Required for binary output
  (`exec --raw cat shot.png > shot.png`), because a stream filter will corrupt
  it and no heuristic detects binary reliably.
- `CLOUDDEV_NO_REWRITE=1` — global off, for debugging the rewriting itself.

Implementation notes that matter more than they look:

- **Line-buffer the filter** (`sed -u`, or `perl -pe` with `$| = 1`). A
  block-buffered filter makes long-running commands look hung.
- **Preserve the exit code** through the pipe — `PIPESTATUS`, or `set -o
  pipefail` plus care. Getting this wrong turns every failure into a silent
  success, which is the worst possible bug in a script agents trust.
- **Longest root first** if the two roots nest.
- **Skip the pipe entirely when `paths` is absent.** No filter process, no
  buffering question, no exit-code juggling — the preferred configuration stays
  the simplest one.

Still prefer identical paths. Rewriting can't reach inside binary artifacts,
JSON reports, or a screenshot's embedded metadata, and it will mangle output
that legitimately contains the container path. `path` and the default rewrite
are what you use once you've lost that argument — not a reason to stop trying
to win it.

Under the **direct** topology none of this applies — one filesystem, one path.
A real argument for preferring it.

### The env overlay

App config typically hardcodes the compose-network topology:

```
POSTGRES_HOST=postgresql
COUCHDB_URL=http://couchdb:5984
REDIS_URL=redis://redis:6379/0
```

Those names resolve only inside the compose network. Under the **native**
topology the agent is outside it, reaching published ports on `localhost`. That
is what `services.env` in the manifest is for: one overlay file selected by
`shell`. Many projects already have a `docker-compose.override.expose-ports.yml`
or similar — reuse it rather than inventing a parallel one.

## Ingress — reaching the running app

`ports:` in the manifest says which ports matter. It does not make them
reachable, and every platform solves that differently:

| Platform | Mechanism |
|---|---|
| Amp | **portals** — authenticated `*.onamp.dev` URLs; hairpin inside the orb so `$PUBLIC_URL` works |
| Cursor | `ports` array in `environment.json`, "similar to devcontainers port forwarding" |
| Factory | `droid computer port-forward <name> <mappings>` |
| Cosmos | **egress-only.** `auggie cloud tunnel open --port 3000` exists but is undocumented |
| Copilot, Devin, Jules | nothing documented |

Two constraints worth designing around before you need them:

- **Amp: cross-origin between two portal hosts is unsupported** — preflights
  don't carry portal auth. A frontend-plus-API stack must be reached through one
  proxying dev server, not two URLs.
- **Cosmos is ingress-free by contract.** A browser-QA story there rests on an
  undocumented CLI command.

So: declare `browser` as a capability only per-platform, and never assume a URL
exists. On a platform with no ingress, browser QA runs *inside* the box against
`localhost` and reports via screenshots, not via a link you open.

## `AGENTS.md` is the fallback adapter

Read by Devin, Jules, Amp, Factory, Copilot, and Cosmos. On tier 3 and tier 4
it is the **only** lever — no hook will run your scripts, so the agent has to.

Every adopting project documents its entrypoints there:

```markdown
## Environment

This project uses the clouddev contract (`clouddev.yml`).

- `script/clouddev/boot` — start backing services. **Run this first** if
  Postgres/Redis/CouchDB/Vault aren't up.
- `script/clouddev/verify` — prove the environment works. Run it before
  trusting a green test run.
- `script/clouddev/exec <cmd>` — run a command in the dev environment.
- `script/clouddev/path <p>` — translate a path from tool output into one you
  can open.
```

It's instruction, not execution, so it degrades to "the agent probably runs
it." That is still strictly better than nothing and costs one paragraph.

Amp offers a cleaner variant: `.agents/setup` writes orb-only guidance into
`~/.config/amp/AGENTS.md`, keeping platform specifics out of the committed file.

## Publishing the dev image

The Dockerfile is already the single source of truth for the toolchain. Publish
its build so platforms can consume it directly.

**Tag on content, not on commits** — otherwise every push rebuilds a multi-GB
image:

```
hash(image_tag_files)  →  ghcr.io/acme/myproject-dev:env-<hash>
                        + a moving :main tag for humans and adapters
```

CI builds when those files change, plus a scheduled rebuild (weekly is fine)
to pick up base-image security updates.

**Toolchain-only, not deps-baked.** Every target platform has a snapshot or
cache layer, so `bundle install` / `npm ci` runs once per environment, not per
session. Baking dependencies buys little and splits local from cloud behavior
(gems and node_modules usually live in named volumes locally, not in the image).

Two constraints to plan for up front:

- **Private registry auth.** A private repo's dev image is private too. Each
  platform needs a registry token as a secret. Some platforms accept only
  *public* images — check `references/platforms.md` before counting on it.
- **Architecture.** Build `linux/amd64`. Add `arm64` only once a target
  platform is confirmed to run ARM; multi-arch builds cost real CI time.

Side benefits worth having anyway: fast local cold builds, and something for
Codespaces prebuilds to snapshot.

## Adopting a project

0. **Establish the tier** of each platform you care about, from
   `references/platforms.md`. If everything you need is tier 0, stop — point it
   at your machine and you're done.
1. **Split the compose file.** Extract backing services into
   `docker/compose.services.yml` with no `app` service. The devcontainer's
   compose file `include`s it and adds `app`. Verify local dev is unchanged
   before going further.
2. **Publish the dev image.** Add the CI build/push job and confirm a pull
   works from a clean machine.
3. **Write the eight scripts** under `script/clouddev/`. Start with `exec` in
   direct form and `path` as the identity function; add the container forms
   only once a platform forces them.
4. **Write `clouddev.yml`.** Declare capabilities conservatively — claim
   `browser` only after `verify` proves it, on that platform.
5. **Make `verify` real.** One check per capability, failing loudly. This is
   the artifact that tells you a platform works.
6. **Document the entrypoints in `AGENTS.md`.** On tier 3 and 4 this is the
   whole adapter.
7. **Generate adapters** for the platforms you actually use. See
   `references/adapters.md`. Adapters contain no logic — they call the
   manifest's scripts.
8. **Run `verify` on each platform** before trusting it with real work.

For a **new client project with no devcontainer**, build the devcontainer
first. This contract is a projection of a working devcontainer, not a
replacement for one.

### Two hazards to plan around before you start

**Provisioning config is often default-branch-only.** GitLab: *"The
configuration file is read-only from the project's default branch. Files
committed to other branches are ignored, even when a flow runs from those
branches."* Copilot requires `copilot-setup-steps.yml` on the default branch.
Cursor builds from the environment's default branch.

So on three platforms you **cannot iterate on provisioning in a branch** —
every tweak is a merge to main. Bringing up a four-service stack by trial and
error that way is brutal. Mitigations, in order of preference: make `prepare`
and `boot` runnable locally so nearly all iteration happens off-platform; keep
the platform-side adapter a one-line call so it rarely changes; land the
adapter early, before the scripts it calls are finished.

**"Devcontainer-native" is not binary.** Coder's envbuilder publishes a spec
support matrix in which `dockerComposeFile`, `service`, `runServices`,
`initializeCommand`, `postAttachCommand`, `mounts`, and `forwardPorts` are all
🔴 unsupported — while its other devcontainer path (built on
`@devcontainers/cli`) almost certainly does support compose but never says so in
the docs. Check the matrix, not the label.

### Probe an unknown platform before designing for it

Several platforms leave the decisive facts undocumented. These four commands
answer them in one session and cost nothing:

```bash
docker info && docker compose version   # is nested Docker real?
id && sudo -n true                      # can prepare install packages?
pwd && git rev-parse --show-toplevel    # where did the checkout land?
env | grep -c YOUR_SECRET_NAME          # are secrets visible in this phase?
```

Currently unanswered by documentation and worth probing: nested Docker on
**Cosmos** and **Factory managed** (Factory's answer decides whether its
memory-snapshot persistence is usable at all), Docker on **Devin** and
**Jules**, and prepare-phase secret visibility on **Cosmos**, **Jules**, and
**Amp**.

## Anti-patterns

- **A native-install fallback for Docker-less platforms.** A second
  environment definition that never runs locally will rot, silently, and you'll
  discover it during a cloud session. Drop the platform instead.
- **Nix / devbox / devenv as the portable source of truth.** Every one of these
  platforms ships Docker; none ships Nix. Adopting Nix makes the project *less*
  portable and discards the devcontainer features ecosystem. Use Nix inside the
  Dockerfile if you want its guarantees — never as the contract.
- **Logic in adapter files.** They're generated. Anything conditional belongs
  in `prepare` or `exec`, where it's testable locally.
- **Claiming capabilities `verify` doesn't check.** An unverified `browser`
  capability wastes a whole cloud session discovering it's false.
- **Baking dev secrets into the published image.** Dev secrets belong in the
  repo (if they're genuinely dev-only fakes) or in platform secret storage.
  An image in a registry outlives the decision to put them there.
- **Starting a process in `prepare`.** It will be snapshotted away on six of
  the platforms here, and the failure looks like "the database is down" rather
  than "you used the wrong phase."
- **A `boot` that blocks until healthy.** Amp gives it 10 seconds. Return, then
  health-gate in the background where `verify` can poll it.
- **Fighting a tier 3 platform when tier 0 is available.** Devin Outposts,
  Factory BYOM, Coder, a self-hosted runner, or simply `claude -p` / `droid
  exec` / `devin -p` in your own CI. A heavy stack on a managed box with no
  session hook is a losing position you chose.
- **Provisioning by prompt.** Antigravity's documented way to prepare an
  environment is to send the agent an interaction telling it to install things,
  then fork the resulting environment id. Codegen, Jules, and Factory managed
  push you the same direction by omission. It is non-deterministic,
  unreviewable, costs tokens, and cannot be diffed. Treat it as the floor you
  land on when a platform gives you nothing — never as a design.
- **Assuming a secrets mechanism reaches a non-HTTP client.** Antigravity
  injects credentials as HTTP headers at an egress proxy — *"never exposed
  inside the sandbox as environment variables or files."* Postgres wire and
  Redis RESP get nothing. Check that a platform's secret path can reach your
  actual clients before assuming the stack works.

## Platform facts decay

Every platform in `references/platforms.md` ships changes monthly. Each entry
carries a **checked date and a documentation URL**. Before relying on an entry
for a decision that costs real time — especially "can this platform take my
image?" — re-read the linked doc and update the date.

Treat a stale entry as unknown, not as true.

## References

- `references/platforms.md` — per-platform capability matrix: base image
  control, nested Docker, customization hook, network model.
- `references/adapters.md` — adapter templates, one per platform.
