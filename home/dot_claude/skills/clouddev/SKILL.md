---
name: clouddev
description: >
  Make a devcontainer-based project runnable by cloud agent platforms (Claude
  Code cloud, Cursor cloud agents, Devin, Augment Cosmos, Factory droids,
  Copilot coding agent, Codespaces) — the clouddev.yml manifest, the entrypoint
  script contract, publishing a dev image to a registry, and splitting
  docker-compose so backing services (Postgres, Redis, CouchDB, Vault) come up
  without the app container. Use when porting a project to a cloud agent
  platform, when a cloud agent can't run tests or boot the app because backing
  services are missing, when adding a platform adapter, or when deciding
  whether a platform is worth supporting at all.
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
| **Toolchain** | a dev image in a registry | the platform (or your setup script pulls it) |
| **Backing services** | a services-only compose file | **your** setup script, from inside the box |

The platform never sees your compose file. You run it yourself, from the box
the platform gave you:

```
platform provides:  a box with Docker + a checkout
your setup script:  docker compose -f <services compose> up -d
```

That is the whole trick. Everything below is bookkeeping around it.

Consequence for the local devcontainer: the `app` service becomes **optional**,
not deleted. Local behavior is unchanged; cloud simply doesn't start it.

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
  setup:         script/clouddev/setup
  services_up:   script/clouddev/services-up
  services_down: script/clouddev/services-down
  exec:          script/clouddev/exec
  shell:         script/clouddev/shell
  path:          script/clouddev/path
  verify:        script/clouddev/verify

services:
  compose: docker/compose.services.yml
  env:     docker/clouddev.env          # localhost-topology overrides

paths:                                   # omit entirely when they're identical
  host:      /workspace
  container: /workspaces/myproject

ports:
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
| `setup` | be idempotent and safe to re-run; leave the environment ready for `verify` | assume it can reach the network later — cold-start installs belong here |
| `services-up` | start backing services, **wait for health**, be idempotent | start the app |
| `services-down` | stop services, leave data volumes alone unless asked | |
| `exec` | run its argv in the dev environment; preserve the exit code; pass stdin through byte-exact; allocate a TTY only when `[ -t 0 ]`; rewrite paths by default (see below), with `--raw` to opt out | decide the TTY from the argument count; rewrite stdin; swallow a non-zero status behind a pipe |
| `shell` | start a login shell in the dev environment, **forwarding its argv** to that shell (`-c '…'`, a script path); **built on `exec`**, never on its own topology logic | duplicate what `exec` knows; force interactivity when stdin is a pipe |
| `path` | translate a path seen in dev-environment output into one the caller can open (`--reverse`, `--filter`); pass unmapped and relative paths through untouched; be the **identity function** when the paths are identical | guess, or mangle paths outside the mapped roots |
| `verify` | exit non-zero when the environment is broken; test one thing per declared capability | mutate the repo or leave state behind |

`setup` runs once per environment on most platforms — they snapshot the
filesystem afterward — so it can afford to be slow. `services-up` runs per
session, because a snapshot preserves disk, never running processes.

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
clouddev/path /workspaces/myproject/app/models/user.rb   # → /workspace/app/models/user.rb
clouddev/path --reverse spec/user_spec.rb                # → the path to hand to a command
clouddev/path --filter < rspec-output.txt                # rewrite a whole stream
```

Contract:

- One path per line on stdin or as argv; one translated path per line on
  stdout. Composable, no parsing ceremony.
- Default direction is **inbound**: "I saw this in output from the dev
  environment, give me the path I can open." `--reverse` goes the other way.
- A path that doesn't sit under either root passes through **unchanged** —
  `/usr/lib/ruby/...` is a real container path with no host equivalent, and
  silently mangling it is worse than returning it.
- Relative paths pass through unchanged.
- **Under the direct topology it is the identity function** — same shape as
  `exec` being `exec "$@"` there. Every project ships it; it just does nothing
  when there's nothing to do. That's what makes it safe for an agent to call
  unconditionally.

`--filter` is what `exec` uses internally, so there is one implementation of
the mapping rather than two.

#### Rewriting is `exec`'s default

Most tools an agent invokes — rspec, eslint, tsc, a coverage reporter, a
browser driver — have no idea they live in a path-mapped world and will happily
print paths the caller can't open. Asking every caller to remember to translate
is a rule that gets followed until the one time it matters. So `exec` rewrites
by default. Scoped:

| Direction | Default | Why |
|---|---|---|
| **argv, inbound** | always rewrite | cheap, unambiguous, no downside |
| **stdout/stderr, outbound** | rewrite **only when the stream is not a TTY** | preserves color, progress bars, and interactivity for a human |
| **stdin** | **never rewrite** | stdin is data — a SQL dump or a tarball must arrive byte-exact |

That last row is the line worth holding: **argv is a command, stdin is data.**

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

1. **Split the compose file.** Extract backing services into
   `docker/compose.services.yml` with no `app` service. The devcontainer's
   compose file `include`s it and adds `app`. Verify local dev is unchanged
   before going further.
2. **Publish the dev image.** Add the CI build/push job and confirm a pull
   works from a clean machine.
3. **Write the seven scripts** under `script/clouddev/`. Start with `exec` in
   direct form and `path` as the identity function; add the container forms
   only once a platform forces them.
4. **Write `clouddev.yml`.** Declare capabilities conservatively — claim
   `browser` only after `verify` proves it.
5. **Make `verify` real.** One check per capability. This is the artifact that
   tells you a platform works, so it must fail loudly when it doesn't.
6. **Generate adapters** for the platforms you actually use. See
   `references/adapters.md`. Adapters contain no logic — they call the
   manifest's scripts.
7. **Run `verify` on each platform** before trusting it with real work.

For a **new client project with no devcontainer**, build the devcontainer
first. This contract is a projection of a working devcontainer, not a
replacement for one.

## Anti-patterns

- **A native-install fallback for Docker-less platforms.** A second
  environment definition that never runs locally will rot, silently, and you'll
  discover it during a cloud session. Drop the platform instead.
- **Nix / devbox / devenv as the portable source of truth.** Every one of these
  platforms ships Docker; none ships Nix. Adopting Nix makes the project *less*
  portable and discards the devcontainer features ecosystem. Use Nix inside the
  Dockerfile if you want its guarantees — never as the contract.
- **Logic in adapter files.** They're generated. Anything conditional belongs
  in `setup` or `shell`, where it's testable locally.
- **Claiming capabilities `verify` doesn't check.** An unverified `browser`
  capability wastes a whole cloud session discovering it's false.
- **Baking dev secrets into the published image.** Dev secrets belong in the
  repo (if they're genuinely dev-only fakes) or in platform secret storage.
  An image in a registry outlives the decision to put them there.

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
