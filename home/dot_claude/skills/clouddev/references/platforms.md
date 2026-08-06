# Platform capability matrix

**Every entry carries a checked date. Treat a stale entry as unknown, not as
true.** These platforms ship changes monthly; re-read the linked doc before
making a decision that costs real time.

All entries below checked **2026-08-06**.

## Tiers

Tier decides how much the contract costs you. Establish it first.

| Tier | Meaning | Platforms |
|---|---|---|
| **0** | Bring your own machine — your box, your image | Devin Outposts, Factory BYOM, **Coder**, **Codespaces via `gh codespace ssh`**, self-hosted GitLab runner, self-hosted OpenHands, and any headless agent CLI in your own CI (`claude -p`, `droid exec`, `devin -p`, Junie headless) |
| **1** | Platform accepts your image | **Ona**, Cursor, Gitpod-lineage/Coder devcontainer paths, Augment Cosmos, GitLab external agents |
| **2** | Their image, real hooks for both phases | Claude Code cloud, Amp orbs, Copilot cloud agent, GitLab native flows |
| **3** | Their image, no usable per-session hook | Devin (managed), Jules, Factory managed, Codegen |
| **4** | No contract to target | Codex cloud, Kiro Web, Amazon Q in GitHub, Antigravity, Replit, OpenHands Cloud, Daytona |

Tier 0 costs nothing — your devcontainer runs unmodified. Tier 4 should be
documented as unsupported rather than worked around.

**Non-targets** (agents execute on *your* compute, so there is nothing to
adapt): Zed (ACP agents run as subprocesses of the client), JetBrains Junie
(*"executes entirely on your GitHub runners"*), Devin CLI `devin -p`, Goose,
Aider, Cline, OpenCode. These are tier 0 by construction.

## Summary

| Platform | Tier | Base image | Nested Docker | Prepare hook | Boot hook | Checkout path |
|---|---|---|---|---|---|---|
| **Ona** (ex-Gitpod) | 1 | **yours, devcontainer + compose** | yes, documented idiom | `prebuild` trigger | `postDevcontainerStart` / `postEnvironmentStart` | `/workspaces/<repo>` |
| Codespaces | 0/1 | **yours**, devcontainer-native | yes, DinD documented | `onCreate` + `updateContent` | `postCreate` / `postStart` | `/workspaces` |
| Coder | 0 | **yours** (Terraform) | yes, four documented methods | `startup_script` | `startup_script` | yours |
| GitLab Duo (external agent) | 1 | **yours** (`image:`) | undocumented | `commands:` | `commands:` | not documented |
| GitLab Duo (native flow) | 2 | **yours** (`image:`) | undocumented | `setup_script` | `setup_script` | not documented |
| OpenHands (self-hosted) | 0/1 | your base, rebuilt as agent-server | **no** — not provisioned | `.openhands/setup.sh` | same script | `/workspace/project[/<conv>]/<repo>` |
| Claude Code cloud | 2 | fixed | **yes**, preinstalled | setup script | `SessionStart` hook | not documented |
| Cursor cloud agents | 1 | **yours** (Dockerfile) | yes, needs config | `install` | `start` + `terminals` | not documented |
| Amp (orbs) | 2 | fixed Debian 12 | yes, you install it | `.agents/setup` | `.agents/resume` (**10s**) | `/home/user/workspace/repo` (observed) |
| Copilot cloud agent | 2 | runner (or `snapshot`) | **`services:`**, not compose | — (none) | `copilot-setup-steps.yml` | `/workspace` (agent) |
| Augment Cosmos | 1 | any registry, **incl. private** | **probably not** | `provision_script` | `on_startup.sh` | `/workspace/{org}/{repo}` |
| Devin (managed) | 3 | fixed Ubuntu 22.04 | undocumented | `initialize`/`maintenance` | **none** | `~/repos/<name>` |
| Factory (managed) | 3 | fixed | **undocumented** | none | `SessionStart` (60s) | you set it |
| Jules | 3 | fixed Ubuntu 24.04 | binaries present, daemon unverified | one text box | **none** | `/app` (community) |
| Codegen | 3 | fixed (uv/bookworm) | undocumented | Setup Commands (UI) | **none** | not documented |
| Codex cloud | 4 | fixed `universal` | **no** | setup script | none | — |
| Daytona | 4 | any image | yes, DinD images | **none** | **none** | configurable |
| Replit | 4 | Nix, no image | **no** | `packager.afterInstall` | Workflows | not documented |
| OpenHands Cloud | 4 | no self-serve BYO | undocumented | `.openhands/setup.sh` | same script | `/workspace/project/…` |
| Antigravity (Gemini API) | 4 | fixed Ubuntu | **no** | **none** | **none** | `target` per source |

## Cross-platform patterns

These held across enough platforms to be treated as rules, not quirks.

### Snapshots preserve disk, never processes

Claude Code cloud, Cursor, Amp, Devin, Cosmos, Jules, Codespaces, Ona, and
Codegen all snapshot the filesystem after provisioning and boot fresh from it. Cursor states it
outright: *"Builds preserve disk state only. Running processes, exported shell
variables, and in-memory caches don't continue into an agent run."*

**One exception: Factory managed Droid Computers.** They suspend and resume
with *"full filesystem and memory snapshots, so local services can continue
running as if they never paused."* The only platform where `boot` runs once
ever.

### Network work belongs in prepare

Three platforms restrict the network *during the agent run* but not during
provisioning:

- **Copilot** — *"The firewall only applies to processes started by the agent
  via its Bash tool. It does not apply to … processes started in configured
  Copilot setup steps."* Blocked requests append a warning to the PR body.
- **Codex** — internet during setup, air-gapped agent phase by default.
- **Claude Code cloud** — access levels apply to the session; Docker Hub is in
  the Trusted defaults.
- **GitLab** — *"`setup_script` commands run before SRT is applied and execute
  outside it."* Unrestricted in setup, Anthropic SRT sandbox during the run.

Four platforms, four independent derivations. Anything lazily fetched at agent
time fails. Pull images, install gems, and warm caches during prepare.

### Provisioning config is often default-branch-only

GitLab: *"read-only from the project's default branch. Files committed to other
branches are ignored, even when a flow runs from those branches."* Copilot
requires `copilot-setup-steps.yml` on the default branch. Cursor builds from the
environment's default branch.

You cannot iterate on provisioning in a branch on any of the three. Keep the
platform-side adapter a one-line call, and do the iteration locally.

### Prebuilds get org/project secrets, never user secrets

Stated as a design invariant by both **Ona** (*"prebuilds run without user
context"*) and **Cursor** (user secrets unavailable during Builds); Devin
scrubs "build only" secrets before snapshotting. Undocumented on Cosmos, Jules,
and Amp. Anything `prepare` needs must be org- or project-scoped.

### Boot hooks have time budgets

| Platform | Budget |
|---|---|
| Amp `.agents/resume` | **10 seconds**, then Amp proceeds anyway |
| Factory `SessionStart` | 60s default timeout |
| Copilot | 59 min total, shared with the actual work |
| Devin build step | 1 hour per step |

`boot` must return fast and health-gate in the background, or it races the
agent's first turn.

### A periodic refresh phase exists nearly everywhere

| Platform | Cadence |
|---|---|
| Cosmos `on_refresh.sh` | 12h, opt-in |
| Devin rebuild | ~24h |
| Cursor staleness threshold | 24h default, `0` = always |
| Amp snapshot reuse | 24h |
| Claude Code cloud cache | ~7 days |

Third real phase, distinct from prepare and boot: cheap, idempotent, keeps a
warm snapshot current.

### Files written during prepare get baked into the snapshot

Devin and Cosmos both warn about this explicitly. Cosmos: *"Putting sensitive
information or credentials into an environment through environment variables
**or files** will allow any user or agent that starts a session with the
environment to access those secrets."* Generate dev-only credentials in `boot`,
never in `prepare`.

### Secret availability during prepare is the recurring unknown

Documented as a phase split on Cursor (user-scoped secrets are **not**
available during Builds) and Devin ("build only" secrets are scrubbed before
snapshot). **Undocumented** on Cosmos, Jules, and Amp. If prepare needs a
credential — private gem host, private registry — verify before designing
around it.

### `AGENTS.md` is the universal fallback adapter

Read by Devin (`knowledge`), Jules, Amp (plus `~/.config/amp/AGENTS.md`),
Factory (*"Droid automatically reads this file"*), Copilot, and Cosmos. On
tier 3 and 4 it is the *only* lever. It's instruction rather than execution, so
it degrades to "the agent probably runs it" — still better than nothing.

## Per-platform notes

### Ona (formerly Gitpod) — tier 1 — **the reference implementation**
<https://ona.com/docs/ona/configuration/devcontainer/overview.md> ·
<https://ona.com/docs/ona/reference/automations-yaml-schema.md>

The only surveyed platform that is genuinely devcontainer-native *for agents*.
Full spec support **including `dockerComposeFile`, single- or multi-container**,
plus `.ona/automations.yaml` for the layer the devcontainer spec has no hook
for. `.gitpod.yml` is gone from the docs entirely — not deprecated, absent.

Triggers, which are the phase model with names on them:

| Trigger | Fires |
|---|---|
| `prebuild` | prebuild only; **no user secrets** |
| `postDevcontainerStart` | user env only, never prebuild |
| `postEnvironmentStart` | every start or resume |
| `postMachineStart` | after VM boot, before dev container ready (`runsOn: machine`) |
| `beforeSnapshot` | after prebuild tasks, before snapshot (tasks only) |
| `manual` | on demand |

Documented idiom: put the same task on **both** `prebuild` and
`postDevcontainerStart` so it bakes into the snapshot *and* re-runs on rebuild.

Services carry `commands.start` (**must block** — `docker run -d` marks the
service Stopped), `commands.ready` (polled to exit 0; gates Starting→Running
*and* gates prebuild snapshotting), `commands.stop`. `dependsOn` chains tasks.
`prebuildRequiresSuccess: true` makes a failing task fail the prebuild.

**The constraint that will bite a compose-based project:**

> *"**Required:** Set `network_mode: host` on all services. Without this,
> services attempt to bridge networks, which can lock you out of your dev
> container with no way to recover except deleting the environment."*

Service-name DNS collapses to a flat localhost port namespace — exactly what the
manifest's `services.env` overlay is for, except mandatory here. Getting it
wrong is **irrecoverable**, not a soft failure.

Other sharp edges:
- **Build-time secrets don't work with compose-based dev containers** ("not yet
  supported"). Choose between compose and BuildKit secret mounts.
- **Untracked git changes made during prebuild are cleared on env start** — Ona
  re-fetches from the remote. Generated artifacts must be gitignored or written
  outside the workspace folder.
- Prebuilds **expire after 7 days**, daily schedule only, one active per
  environment class. Prebuild timeout 1h default (5m–2h), snapshot 4h, overall
  6h.
- Prebuild gets **org + project secrets, never user secrets** — same invariant
  as Cursor.
- Auto-stop 30 min default; **"an agent is running" counts as activity** but
  background processes and port traffic do not — use
  `ona environment keep-alive --pid` for long jobs.
- Registry secrets take hostname + username + password; ECR/GAR have native IAM
  paths; Ona auto-runs `docker login` inside the environment when a docker CLI
  is present.
- CLI is a first-class external-agent surface: `ona environment
  create|exec|ssh|stop|delete`, `-o json`, exit-code propagation. `exec` runs
  inside the dev container via API, not SSH.
- Self-hosted runners in your own AWS/GCP VPC (Enterprise) move this to tier 0.

### Codespaces — tier 0/1 — great runtime, **no agent product**

Grepping all 214 Codespaces doc files for `agent` returns exactly one hit, about
`ssh-agent`. There is no agent session product, no agent API, no "run an agent
in this codespace" surface. Copilot in a codespace is the ordinary editor
extension, and **Copilot's cloud agent cannot even read Codespaces secrets** —
it runs on Actions runners.

So Codespaces is a first-rate devcontainer host with zero agent help: `gh
codespace ssh` in and run your own agent. That is tier 0 and needs no adapter.

Prebuild boundary is the canonical one: *"performing setup operations up to and
including any `onCreateCommand` and `updateContentCommand`… **No
`postCreateCommand` commands are run during the creation of a prebuild.**"*

Dedicated private VM per codespace with full root, DinD explicitly relied on
(private-image pulls at runtime are documented). Private registry via
`<PREFIX>_CONTAINER_REGISTRY_SERVER`/`_USER`/`_PASSWORD` secrets; ECR
special-cased. Outbound internet open, no egress allowlist feature; **enabling
org IP allow lists disables codespace creation entirely**.

Checkout is **dictated**: `/workspaces` on the host VM, bind-mounted in. Only
`/workspaces` survives a rebuild. Codespaces secrets are **not** available
during image build or in features — only after the container is running.

`dockerComposeFile` is supported by reference to containers.dev; GitHub
publishes **no first-party compose guidance**, so you're on spec-implementation
behavior alone.

### Coder — tier 0 — self-hosted, but ignore its agent layer
<https://coder.com/docs/admin/integrations/devcontainers/integration>

AGPL, self-host-only, no managed cloud — so effectively BYO machine at zero
marginal support cost. Terraform templates; hooks are
`coder_agent.startup_script` / `shutdown_script` and `coder_script` with
`run_on_start`/`run_on_stop`. Nested Docker is treated as a first-class problem
with four documented approaches: **Sysbox**, **Envbox**, **rootless Podman**,
socket mounting.

**Two devcontainer paths with different spec coverage** — check the matrix, not
the label:

- **Dev Containers Integration** (current direction, `@devcontainers/cli` +
  `coder_devcontainer` resource): compose support is **strongly implied but
  never stated** — the docs never say "compose". Spike before committing.
- **Envbuilder**: `dockerComposeFile`, `service`, `runServices`,
  `initializeCommand`, `postAttachCommand`, `mounts`, `forwardPorts` all
  **🔴 unsupported**. Compose is flatly out.

**Ignore the agent layer.** Coder Tasks moves to Extended Support 2026-06-02 and
is **removed in v2.37 (2026-09-01)**. Its replacement, Coder Agents, is
deliberately *not* a wrapper: *"The workspace itself has no knowledge of AI. It
is standard compute infrastructure — there are no LLM API keys, no agent
harnesses, and no special software installed."* A Coder workspace is a dev
machine; `coder ssh` in and run whatever agent you like.

Optional **Agent Firewall** (process-level allowlist, nsjail/landjail) requires
the AI Governance Add-On as of v2.32.

### GitLab Duo Agent Platform — tier 1 (external) / 2 (native) / 0 (own runner)
<https://docs.gitlab.com/user/duo_agent_platform/flows/execution/>

Flows run as CI/CD jobs on GitLab Runner — hosted or yours. Runner must carry
tag `gitlab--duo`, must be an instance runner or top-level-group runner, and
must use a Docker-capable executor (`shell` unsupported).

**It does not read `.gitlab-ci.yml`.** GitLab generates the job; config is a
separate, narrower schema. Consequences:

- **No `services:` key.** GitLab CI's service-container model does *not* carry
  over — so unlike Copilot there is no transcribe-to-`services:` escape hatch.
- **Custom CI/CD variables are unavailable to native flows**, all types and
  scopes. The sanctioned secrets path is OIDC `id_tokens` to an external
  manager — which maps cleanly onto Vault.
- **`agent-config.yml` is read from the default branch only.**

`.gitlab/duo/agent-config.yml` keys: `image`, `setup_script`,
`network_policy.{allowed_domains,denied_domains,include_recommended_allowed,allow_all_unix_sockets}`,
`cache.{paths,key}`, `id_tokens`. Cache is the *only* persistence — no
snapshots.

**`.gitlab/duo/flows/*.yaml` (external agents) is the better target**: `image`,
`commands`, real CI/CD `variables`, `id_tokens`, and no SRT sandbox. Effectively
a bring-your-own-container primitive; `commands:` maps directly onto
`prepare` → `boot` → agent.

Network phase split is explicit: *"`setup_script` commands run before SRT is
applied and execute outside it."* Default SRT allowlist already includes
`localhost` and `host.docker.internal`.

Nested Docker **undocumented in both directions**; `allow_all_unix_sockets:
true` is the obvious socket lever and `privileged = true` on your own runner the
DinD lever. Private registry auth for `image:` is undocumented — likely a
runner-level `config.toml` concern.

Security note: flows run under the *triggering user's* composite identity, so
write access to `agent-config.yml` influences what runs in another user's runner
environment.

### OpenHands — tier 0/1 (self-hosted), tier 4 (Cloud)
<https://docs.openhands.dev/openhands/usage/advanced/custom-sandbox-guide>

Three surfaces: OSS self-hosted, Cloud (SaaS), Enterprise (k8s, commercial).
Docs moved to `docs.openhands.dev`; repo is now `OpenHands/OpenHands`; V0
"runtime" is being replaced by V1 "sandbox".

**The runtime container *is* the agent-server**, so you cannot supply an
arbitrary image — you rebuild the agent-server *onto* your base:

```
docker buildx build --build-arg BASE_IMAGE=my-base:latest --target binary \
  -f openhands-agent-server/openhands/agent_server/docker/Dockerfile ...
```

Then set **both** `AGENT_SERVER_IMAGE_REPOSITORY` and `AGENT_SERVER_IMAGE_TAG`
— missing either silently falls back to the default. No registry-credential
mechanism in OSS; the host must already be able to pull.

Repo conventions: `.openhands/setup.sh`, `.openhands/pre-commit.sh`,
`.openhands/hooks.json` (**deliberately Claude Code hooks-compatible** — same
scripts, different location), skills at `.agents/skills/`, plus `AGENTS.md`.
`devcontainer.json` is **not read**.

Two implementation details that matter and aren't in the prose:
- **`setup.sh` is `source`d, not exec'd** (`chmod +x && source`), cwd = project
  dir, **600s timeout** — so `export FOO=bar` persists into the agent's shell.
- **It re-runs on every conversation start**, even on a reused sandbox. It is a
  `boot` script, not a `prepare` script. Prebake expensive work into the image.

**No nested Docker in OSS** — the sandbox container is created with no
`privileged`, no `cap_add`, no socket mount. Best fit is to run your compose
stack *outside* the sandbox and reach it via `host.docker.internal`. Documented
in-sandbox `docker compose` exists only in **Enterprise 0.18.2+** (k8s, kernel
6.3+, userns remapping, no privileged mode).

Checkout is `/workspace/project/{repo}` — or
`/workspace/project/{conversation_id_hex}/{repo}` under any sandbox-grouping
strategy other than `NO_GROUPING`. **Don't hardcode it.**

**Cloud is a dead end**: no self-serve BYO image (`sandbox_spec_id` selects a
pre-provisioned spec; no public endpoint registers one), no documented Docker.

### Codegen / Replit / Daytona / Antigravity — tier 4

- **Codegen** — UI-configured Setup Commands, run once and filesystem-snapshotted;
  fixed image built from `ghcr.io/astral-sh/uv:python3.13-bookworm` with no
  database services; Docker availability undocumented; **ingress is a single
  fixed port 3000**. No devcontainer support.
- **Replit** — Nix workspace, not containers. `.replit` + `replit.nix`, no
  Dockerfile, **no Docker at all**. Managed Postgres exists; Redis/CouchDB/Vault
  have no documented story. Devcontainer investment transfers at zero.
- **Daytona** — OSS repo **unmaintained since June 2026** ("core development has
  moved to a private codebase"), no self-hosting page. Devcontainer support gone
  from the docs entirely. **No lifecycle hooks of any kind** — you write an
  orchestrator against the SDK. 4 vCPU / 8 GB / 10 GB cap, and volumes
  *"cannot support block storage access (databases)"*. Does document DinD images
  and compose, and hosts Devin Outposts.
- **Antigravity** — the IDE/CLI/SDK are **local-only**; the hosted surface is
  Gemini API Managed Agents, an API-driven ephemeral sandbox with no repo
  manifest, no setup hook, no image control, no Docker, no env vars, no
  terminal. Credentials are injected as **HTTP headers at an egress proxy**, so
  Postgres wire and Redis RESP get nothing at all. Google is also retiring
  Firebase Studio *into* the local IDE — a directional signal.

### Claude Code cloud — tier 2
<https://code.claude.com/docs/en/cloud-environments>

Base image not replaceable; supported paths are installing on top via setup
script, or *"run your own image as a container alongside Claude with `docker
compose`"* — the container topology. `docker`, `dockerd`, `docker compose` all
preinstalled. Postgres 16 and Redis 7 preinstalled but not running. Ruby
3.1/3.2/3.3 + rbenv, Node 20/21/22 via nvm.

Setup script runs once, then filesystem snapshot; re-runs on script or
allowed-host change, or after ~7 days. Network levels: None / Trusted / Full /
Custom. No human shell — the agent runs every command.

Map `boot` to a repo `SessionStart` hook, since the snapshot won't hold
running containers.

### Cursor cloud agents — tier 1
<https://cursor.com/docs/cloud-agent/setup.md> ·
<https://cursor.com/docs/cloud-agent/builds.md> ·
schema: <https://www.cursor.com/schemas/environment.schema.json>

`.cursor/environment.json`. Honored keys: `name`, `user`, `install`, `start`,
`terminals`, `ports`, `repositoryDependencies`, `build.dockerfile`,
`build.context`, `snapshot`, `agentCanUpdateSnapshot`. Resolution order: repo
file → personal saved environment → team saved environment. Builds use config
from the environment's **default branch**.

Three-phase: image build → `install` (once per Build) → `start` + `terminals`
(every session). `terminals` run in a **tmux shared with the agent**;
`terminals[].description` is *"displayed to the agent."*

**Nested Docker needs configuration, not just installation.** Default
`overlay2` fails inside their container layer — requires `fuse-overlayfs` in
`/etc/docker/daemon.json` plus `iptables-legacy`. Cursor's docs call this the
most likely silent breakage. `sudo service docker start` goes in `start`.

No `--privileged`, no ulimit control → **Vault needs `disable_mlock`**.

**Undocumented requirement, Cursor-staff-confirmed:** a custom image must
contain `git` (and `sudo`), because Cursor runs `git clone` *inside* your
container. Missing `git` gives an opaque failure after the clone step. Do not
`COPY` the project into the image.

Secrets: three types (Environment Variable / Runtime Secret / Build Secret) ×
three scopes (user / environment / team). **User secrets are unavailable during
Builds.** Known open bug: environment-scoped secrets aren't injected at
runtime; workaround is personal scope. Private registry auth for the base
image is not documented.

### Amp (orbs) — tier 2
<https://ampcode.com/manual/orbs>

Per-thread Debian 12 VMs. `.agents/setup` (once per snapshot, 24h reuse),
`.agents/resume` (**10s budget**), `.amp/services.yaml` (declarative supervised
services), `.amp/portals/*.json` (public HTTPS links).

Docker not preinstalled, but Amp documents the apt install itself including
`docker-compose-plugin`; daemon via `amp orb service start docker-daemon
--command 'sudo dockerd'`, everything under `sudo`. No custom image, no private
registry.

**Portals** are the ingress model: authenticated `*.onamp.dev` URLs that
hairpin inside the orb so `$PUBLIC_URL` works. **Cross-origin between two
portal hosts is unsupported** — a frontend+API stack must be proxied through
one dev server.

`AMP_ORB=1` set in every orb. 40GB disk on every size. Auto-pause after 5 min
idle. First-class terminal pane sharing the agent's tmux. Postgres and Redis
are in the base image; CouchDB and Vault are not.

### Copilot cloud agent — tier 2
<https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-environment>

Renamed from "coding agent"; `coding-agent` URLs 301 to `cloud-agent`.
**Copilot Workspace is dead** — host doesn't resolve, zero pages on
docs.github.com. **Agent HQ changes nothing**: third-party agents run on the
same runner and consume Actions minutes; `.github/agents/*.agent.md` has no
image or setup key.

`.github/workflows/copilot-setup-steps.yml`, on the default branch, single job
named exactly `copilot-setup-steps`. **Only six job keys honored** — `steps`,
`permissions`, `runs-on`, `services`, `snapshot`, `timeout-minutes` (max
**59**). Everything else silently ignored.

**`container:` is not honored and breaks the agent job** (exit 127 — the
Copilot action's helper scripts are referenced by host path). Container
topology is unavailable here.

**Actions `services:` is the supported backing-services path.** `docker
compose` appears nowhere in their docs. `services:` can't express `depends_on`,
build contexts, named volumes, or multi-network topology — Vault dev-mode and
CouchDB bootstrap each need a follow-up step.

Everything is per-session; cold runner each task. Only `actions/cache` and
`snapshot` custom **VM** images (org/enterprise, hours to build) carry over.

`.devcontainer/devcontainer.json` is **not read** — confirmed by grepping every
Copilot doc source; zero occurrences.

Agent working directory is **`/workspace`** with `HOME=/root`; the Actions
workspace is `/home/runner/work/<repo>/<repo>`. **The relationship between the
two is never documented.** Verify before assuming a file written in setup is
visible to the agent at the same path.

Secrets live in a dedicated **Agents** scope; the agent has no access to
Actions, Codespaces, or Dependabot secrets. A non-zero exit **skips remaining
setup steps and the agent starts anyway** — silent degradation, so `verify`
must fail loudly and the agent must be told to run it.

### Augment Cosmos — tier 1
<https://docs.augmentcode.com/cosmos/environments/cloud> ·
<https://docs.augmentcode.com/cli/cloud>

**Private registry pull IS supported** — via `auggie cloud registry-credential
set <name> --type dockerhub|generic|aws|gcp --scope user|tenant`. Stored under
a reserved `AUGMENT_REGISTRY_CREDENTIAL_<name>` prefix and consumed by the
control plane at pull time. **Documented nowhere on the docs site** (the word
"private" never appears in a registry context across 190 pages) — CLI only. The
credential-to-image binding mechanism is opaque; verify empirically.

Declarative bundle: `auggie cloud environment init|validate|diff|apply`,
`apiVersion: poseidon.augmentcode.com/v1alpha1`, `kind: EnvironmentBundle`.
GitOps-friendly and idempotent — the best adapter target of any platform here.
But the bundle has **no field** for hook scripts, provision script, or registry
credential; those are separate CLI operations.

Real three-phase model, CLI-only: `rebuild --provision-script` (pre-snapshot,
build time), `--vm-startup-script` (= `on_startup.sh`, every session),
`on_refresh.sh` (12h, opt-in). The web docs collapse this to two.

`environment update --script` applies incrementally to the current snapshot;
**`rebuild` is destructive** and rebuilds from the base image. Put all
provisioning in a committed `provision_script`, never in the terminal.

**Nested Docker: probably unavailable.** Zero mentions across the corpus; the
runtime appears to be Modal sandboxes; Tailscale requires
`--tun=userspace-networking` (no TUN device → unprivileged). **Test `docker
info` before designing around it.** If it fails, install services as native
packages in `provision_script` and start them from `on_startup.sh` — the base
image list includes Ruby 3.4.

Egress-only, no ingress. Undocumented escape hatches: `auggie cloud tunnel open
--port 3000` (loopback port exposure) and `auggie cloud desktop ensure`
(VNC/noVNC). Don't build a browser-QA story on an undocumented command without
testing it.

No `systemd`, no `supervisord` guaranteed — the base image contract is only
`bash` and `git`. Environment names are unique **org-wide**, so per-branch
environments collide.

Cosmos Advisor is conversational and non-deterministic. Target the bundle +
`provision_script` path; treat Advisor as human bootstrap convenience.

### Devin — tier 3 (managed), tier 0 (Outposts)
<https://docs.devin.ai/onboard-devin/environment/blueprint-reference>

**No per-session command hook exists.** Session start does only: `git pull`,
re-inject secrets, load `knowledge` as context. `maintenance` is *surfaced to
the agent as advisory text, not executed*.

Blueprints: `initialize`, `maintenance`, `knowledge`, `post-build`, `clone`.
Three additive tiers (enterprise → org → repo). `.devin/blueprint.yaml` exists
but is **not read automatically** — needs an explicit sync API call, so plan a
CI step. `post-build` is the only hook that fails a build on non-zero exit and
is **org/enterprise only**.

No custom base image. Ubuntu 22.04. Repos clone to `~/repos/<short-name>`;
`clone.path` overrides the name only. Differential builds **skip
`initialize`** — `maintenance` must stand alone. `$ENVRC` resets every build.
Docker availability in cloud sessions is never officially stated.

`boot` must be installed as a **systemd unit** during `initialize`, or invoked
by the agent via `knowledge`.

**Devin Outposts** is the escape hatch — your VMs/containers/K8s, `devin worker
start --outpost=<name>`, needs only `git` and outbound HTTPS. Open-source K8s
operator at `CognitionAI/devin-outpost-k8s`. Tier 0; your devcontainer works
unmodified.

**Windsurf is folded into Devin.** `docs.windsurf.com` now titles its landing
page "Welcome to Devin Desktop." Its cloud story *is* Devin blueprints. No
separate surface.

### Factory — tier 3 (managed), tier 0 (BYOM / `droid exec`)
<https://docs.factory.ai/droid-computers/overview> ·
<https://docs.factory.ai/droid-computers/byom>

**No declarative environment surface anywhere.** Managed computers take a name
at creation and nothing else. The announcement: *"either have Droid set up the
development environment dynamically, or access a terminal to configure
everything yourself."*

**Managed computers persist running processes** — full filesystem *and memory*
snapshots on idle-pause/resume. Uniquely, `boot` could run once ever. But
**Docker availability is entirely undocumented**; the backend appears to be
E2B/Firecracker. `factory-user` has passwordless sudo. 4 CPU / 8 GB RAM / 6 GB
swap. **Test this before writing the adapter** — it's the difference between
best-in-class and unusable.

`.factory/hooks.json` is committable with a `SessionStart` hook (60s default
timeout, designed for context injection — off-label for booting services).
Hooks execute from Droid's cwd, which may differ from the repo root: use
`"$FACTORY_PROJECT_DIR"`.

Tooling: `droid computer ssh`, VS Code Remote-SSH via `ProxyCommand`, `droid
computer port-forward`.

**Cloud Templates are deprecated and broken for this** — the setup script runs
in a *build* container before activation, so services started there don't reach
the session. `/workspaces/<repo>` is the only path surviving rebuild.

**BYOM and `droid exec`** are tier 0: your machine, your image, real Docker,
outbound-only through `relay.factory.ai`, free on all plans.

### Jules — tier 3
<https://jules.google/docs/environment/>

No repo config file at all. One free-form "Initial Setup" shell script in the
web UI plus env vars. REST API is **read-only for sources** — none of it is
automatable.

Disqualifying, stated twice: *"Long-running processes like dev servers or watch
scripts aren't currently supported in setup scripts."* Also listed as a common
cause of task failure. There is nowhere to bring services up.

Docker 28.2.2 and Compose v2.36.2 **are** in their published inventory, but
whether `dockerd` runs is stated nowhere and there's no shell to check. **No
Ruby preinstalled.** 20GB disk. Fresh VM per task; snapshot from an explicit
"Run and Snapshot". Whether the setup script re-runs per task once a snapshot
exists is **unresolved in the docs**.

Best available: keep an idempotent entrypoint in the repo and have a human
paste `bash script/clouddev/prepare && bash script/clouddev/boot` into the box
once, so the repo stays the source of truth. `AGENTS.md` carries the rest.

### Codex cloud — tier 4, unsupported
<https://developers.openai.com/codex/cloud/environments>

Fixed `universal` image; runtime versions pinnable, image not replaceable.
**`dockerd` does not work** — no nested Docker, so no compose. Internet during
setup, off by default during the agent phase.

Supporting it needs a native-install provisioning path that never runs locally
and therefore rots. Document as unsupported.

### Kiro Web — tier 4, unsupported
<https://kiro.dev/docs/web/sandbox/>

Successor to Amazon Q Developer. No documented lifecycle hook, no base-image
control, no documented nested Docker, and the sandbox is **torn down per task
with no snapshotting**. Config is console-only plus "the agent detects your
project type." A launch blog claims Dockerfiles/devfiles are auto-detected, but
the schema, honored command ids, and file path are unspecified.

### Amazon Q Developer — tier 4, sunsetting

New signups closed 2026-05-15; IDE plugins EOL 2027-04-30; successor is Kiro.
The `/dev` `devfile.yaml` surface has been **de-documented** — those pages now
meta-refresh away. Q Developer in GitHub has **no repo config surface at all**
and its docs state feature-development configuration cannot be modified.
