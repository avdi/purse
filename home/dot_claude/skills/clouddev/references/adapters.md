# Adapter templates

Adapters are **generated from `clouddev.yml`, not written**. Each is a few lines
calling the manifest's scripts. Anything conditional belongs in `prepare` or
`exec`, where it can be exercised locally.

Adapter files are the one artifact class whose location is **forced** — each
platform dictates its own path, and several have no repo file at all. That's why
the manifest exists: the single anchor every scattered adapter points back at.

Regenerate all adapters whenever the manifest changes.

All schemas below checked **2026-08-06**. Re-verify before relying on one.

---

## Ona — tier 1, direct topology — start here

The closest thing to a native implementation of this contract. `devcontainer.json`
carries the image (including `dockerComposeFile`); `.ona/automations.yaml`
carries the phases:

```yaml
# .ona/automations.yaml
tasks:
  prepare:
    name: Prepare
    command: script/clouddev/prepare
    triggeredBy: [prebuild, postDevcontainerStart]   # bake AND re-run on rebuild

services:
  backing:
    name: Backing services
    triggeredBy: [prebuild, postEnvironmentStart]
    commands:
      start: script/clouddev/boot --foreground      # MUST block
      ready: script/clouddev/verify --services-only
      stop:  script/clouddev/halt
```

Three things to get right:

- **`commands.start` must block.** `docker compose up -d` exits immediately and
  Ona marks the service Stopped. Use a foreground compose invocation — this is
  the one place `boot` runs in blocking form rather than returning fast.
- **Always define `ready:`** for prebuild services, or the snapshot may be taken
  before images finish pulling. It also gates Starting→Running.
- **`network_mode: host` on every compose service is required.** Omitting it
  *"can lock you out of your dev container with no way to recover except
  deleting the environment."* Service-name DNS collapses, so the manifest's
  `services.env` localhost overlay is mandatory here, not optional.

Prebuild sees org and project secrets but **never user secrets**. Build-time
BuildKit secrets don't work with compose-based dev containers at all — if the
image build needs a credential, you must choose between compose and build
secrets. Artifacts generated during prebuild must be gitignored or written
outside the workspace folder, since untracked changes are cleared on env start.

---

## Codespaces — tier 0/1, direct topology

No agent product exists; this is a devcontainer host you `gh codespace ssh`
into. The adapter is the devcontainer file itself, using the spec's own phase
boundary:

```json
{
  "dockerComposeFile": ["../docker/compose.services.yml", "docker-compose.yml"],
  "service": "app",
  "workspaceFolder": "/workspaces/myproject",
  "updateContentCommand": "script/clouddev/prepare",
  "postStartCommand": "script/clouddev/boot"
}
```

`onCreateCommand` and `updateContentCommand` run at prebuild; `postCreate`,
`postStart`, and `postAttach` never do. Codespaces secrets are **not** available
during image build or in features — only once the container is running, so
`prepare` cannot depend on them.

---

## Coder — tier 0

Self-hosted, so this is a workspace template, not an agent adapter. Ignore
Coder's agent layer entirely (Tasks is removed in v2.37; Coder Agents
deliberately doesn't run third-party CLIs).

```hcl
resource "coder_agent" "main" {
  startup_script = <<-EOT
    script/clouddev/prepare
    script/clouddev/boot
  EOT
}
```

Pick the **Dev Containers Integration** path, not envbuilder — envbuilder lists
`dockerComposeFile`, `service`, and `runServices` as unsupported. Nested Docker
needs one of Sysbox / Envbox / rootless Podman / socket mount.

---

## GitLab Duo — tier 1 (external agent)

`.gitlab/duo/flows/<name>.yaml` — the permissive surface, with real CI/CD
variables and no SRT sandbox:

```yaml
image: ghcr.io/acme/myproject-dev:main
injectGatewayToken: true
variables:
  - DATABASE_PASSWORD
commands:
  - script/clouddev/prepare
  - script/clouddev/boot
  - script/clouddev/verify
  - claude -p "$DUO_WORKFLOW_GOAL"
```

The native-flow surface (`.gitlab/duo/agent-config.yml`) has `image` and
`setup_script` but **no `services:` key** and **no access to your CI/CD
variables** — secrets go through OIDC `id_tokens` to an external manager, which
suits Vault. Its config is also **default-branch-only**, so iterate locally.

For tier 0, register your own runner tagged `gitlab--duo` and author the job
yourself.

---

## OpenHands (self-hosted) — tier 0/1

`.openhands/setup.sh` — but note it is a **`boot` script, not a `prepare`
script**: it is `source`d (so exports persist), capped at 600s, and **re-runs on
every conversation start** even on a reused sandbox.

```bash
#!/usr/bin/env bash
set -euo pipefail
script/clouddev/boot
```

Expensive work belongs in the image. Build the agent-server onto your dev image
rather than supplying it directly — the runtime container *is* the agent-server:

```
docker buildx build --build-arg BASE_IMAGE=ghcr.io/acme/myproject-dev:main \
  --target binary -f openhands-agent-server/openhands/agent_server/docker/Dockerfile ...
```

Then set **both** `AGENT_SERVER_IMAGE_REPOSITORY` and `AGENT_SERVER_IMAGE_TAG`.

The OSS sandbox has **no nested Docker** — not privileged, no socket. Run the
compose stack outside the sandbox and reach it via `host.docker.internal`.
`.openhands/hooks.json` is Claude Code hooks-compatible, so hook scripts port
across unchanged.

---

## Claude Code cloud — tier 2, container topology

No repo file; the setup script is configured in the environment UI at
`claude.ai`. Body:

```bash
#!/usr/bin/env bash
set -euo pipefail
script/clouddev/prepare
```

Because the snapshot preserves disk but **not running processes**, `boot` goes
in a repo `SessionStart` hook:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "script/clouddev/boot" }] }
    ]
  }
}
```

Network access `Trusted` at minimum (Docker Hub is in the defaults); add a
`Custom` allowlist entry for a private registry host. Registry credentials go in
the environment's variables — visible to anyone who can use the environment, so
use a read-only pull token.

---

## Cursor cloud agents — tier 1, direct topology

`.cursor/environment.json`:

```json
{
  "build": { "dockerfile": "Dockerfile", "context": ".." },
  "install": "script/clouddev/prepare",
  "start": "script/clouddev/boot",
  "ports": [{ "name": "app", "port": 3000 }]
}
```

`dockerfile` and `context` are relative to `.cursor`; `.`, `./`, and `..` are
special-cased to mean the repo root. Config is read from the environment's
**default branch** — a feature-branch change needs a commit and push first.

Your image **must contain `git` and `sudo`** (undocumented, staff-confirmed —
Cursor runs `git clone` inside your container), and must **not** `COPY` the
project in.

Nested Docker needs daemon config baked into the image, not just installation:

```dockerfile
RUN mkdir -p /etc/docker && \
    echo '{"storage-driver":"fuse-overlayfs"}' > /etc/docker/daemon.json && \
    update-alternatives --set iptables  /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
```

`sudo service docker start` belongs at the top of `boot`. Vault needs
`disable_mlock` — there is no `--privileged` knob.

Secrets: build-time credentials must be **team**- or **environment**-scoped
(user secrets are unavailable during Builds), consumed via
`RUN --mount=type=secret,id=…`. Note the open bug where environment-scoped
secrets aren't injected at runtime; personal scope is the current workaround.

---

## Amp (orbs) — tier 2, direct topology

`.agents/setup` (must be executable, `chmod +x`):

```bash
#!/usr/bin/env bash
set -euo pipefail
script/clouddev/prepare
```

`.agents/resume` — **10-second budget**, so this must return immediately:

```bash
#!/usr/bin/env bash
set -euo pipefail
script/clouddev/boot &          # health-gates in the background
```

Docker is not preinstalled; install it in `prepare` (Amp documents the apt
recipe including `docker-compose-plugin`), then start the daemon as a supervised
service rather than from a hook:

```bash
amp orb service start docker-daemon --command 'sudo dockerd'
```

Declarative services in `.amp/services.yaml` are supervised and survive
pause/resume — prefer them to backgrounding processes yourself:

```yaml
services:
  web:
    command: script/clouddev/exec bin/dev
    portal:
      title: App
```

Portals are the ingress model. **Cross-origin between two portal hosts is
unsupported** — proxy the API through the frontend dev server.

Branch on `AMP_ORB=1`. Logs at `/home/user/.cache/amp/logs/{setup,resume}.log`.

---

## Superconductor — tier 2, direct topology

No repo config file is documented; the dev environment lives in project
settings. That makes this the shortest adapter in the file — two boxes, one line
each — and the shortness is the point, because the settings aren't in git and
every character you put there is a character you can't review or diff.

**Build commands** (= `prepare`; snapshotted, and the only thing that survives
an instance restart):

```bash
script/clouddev/prepare
```

**Startup commands** (= `boot`; run automatically at launch):

```bash
script/clouddev/boot
```

Then **snapshot after the build commands succeed** — that snapshot is
user-controlled and never expires, so every later implementation boots warm.
Nothing rebuilds it on a timer either: wire `script/clouddev/refresh` plus a
re-snapshot into a scheduled job, or accept that the snapshot ages.

**HTTP services** are declared in settings, one marked Primary, and are the
manifest's `ports:` transcribed by hand — the one place regenerating adapters
means editing a web form:

```yaml
# clouddev.yml
ports:
  app:  3000     # → HTTP service "app", port 3000, Primary
  vite: 3036     # → HTTP service "vite", port 3036
```

Each service gets an HTTPS URL and an injected host variable. **Use them in
`boot`** — a framework host allowlist rejecting the generated hostname is the
most likely reason a preview comes up blank:

```bash
# in script/clouddev/boot, when running under Superconductor
export RAILS_DEVELOPMENT_HOSTS="${AGENT_RAILS_HOST:-localhost}"
export VITE_ALLOWED_HOSTS="${AGENT_WEB_HOST:-localhost}"
```

Docker and compose work — it is a full VM, not a nested container — so the
services compose file runs unmodified and the direct topology applies. This is
the least friction any tier-2 platform here offers for a stateful stack.

Instances pause after **15 minutes** idle and wake on return; the terminal
reconnects as a new session. Assume startup commands may re-run and keep `boot`
idempotent.

The egress allowlist is per-project and configurable. **Verify whether it
applies during build commands** before assuming `prepare` can reach your gem
host or registry — if it does, widen the allowlist first.

---

## Copilot cloud agent — tier 2, direct topology

`.github/workflows/copilot-setup-steps.yml`, on the **default branch**. Single
job named exactly `copilot-setup-steps`. Only `steps`, `permissions`, `runs-on`,
`services`, `snapshot`, `timeout-minutes` (max **59**) are honored — everything
else is silently ignored, and **`container:` breaks the agent job outright**.

```yaml
name: "Copilot Setup Steps"
on:
  workflow_dispatch:
  push:
    paths: [.github/workflows/copilot-setup-steps.yml]

jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
    services:
      postgresql:
        image: postgres:14.2
        env: { POSTGRES_PASSWORD: postgres }
        ports: ["5432:5432"]
      redis:
        image: redis:8.2
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - run: script/clouddev/prepare
      - run: script/clouddev/boot
      - run: script/clouddev/verify
```

**Use `services:`, not `docker compose`** — `services:` is what GitHub commits
to; Docker is nowhere in their docs. It can't express `depends_on`, build
contexts, named volumes, or multi-network topology, so Vault dev-mode and
CouchDB bootstrap each need a follow-up step.

Everything is per-session (cold runner per task), so `prepare` and `boot` both
run here — the sequence invariant is doing the work.

Secrets go in the **Agents** scope, not Actions. All network work must finish in
these steps; the agent phase is firewalled. A non-zero exit **skips the
remaining steps and starts the agent anyway**, which is why `verify` runs last
and `AGENTS.md` tells the agent to re-run it.

Beware: the agent's working directory is `/workspace` with `HOME=/root`, while
these steps run in the Actions workspace. The relationship is undocumented.

---

## Augment Cosmos — tier 1, direct topology

Declarative bundle via `auggie cloud environment init|validate|diff|apply` —
GitOps-friendly and idempotent, the best adapter target here:

```yaml
apiVersion: poseidon.augmentcode.com/v1alpha1
kind: EnvironmentBundle
metadata:
  name: myproject
spec:
  environment:
    displayName: myproject
    baseImage: ghcr.io/acme/myproject-dev:main
    refreshEnabled: true
    repos:
      - { owner: acme, name: myproject }
    environmentVariables: []
```

The bundle has **no field** for hook scripts or the registry credential. Those
are separate CLI calls:

```bash
auggie cloud registry-credential set ghcr --type generic \
  --username "$USER" --secret-stdin
auggie cloud environment rebuild "$ENV_ID" \
  --provision-script script/clouddev/prepare \
  --vm-startup-script script/clouddev/boot
```

Private registry pull **is** supported this way, though documented nowhere on
the docs site. The credential-to-image binding is server-side and opaque —
verify empirically.

`/hooks/on_refresh.sh` → `script/clouddev/refresh` (12h when enabled).

**`rebuild` is destructive** — it starts from the base image and discards
snapshot state. Use `environment update --script` for incremental changes, and
keep all provisioning in the committed `provision_script` so a rebuild loses
nothing.

**Test `docker info` first.** If nested Docker is unavailable, `prepare` must
install services as native packages (a Ruby 3.4 base image is on offer) and
`boot` starts them with `&` plus explicit health checks — there is no guaranteed
init system.

Egress-only. Environment names are unique **org-wide**.

---

## Devin — tier 3 (managed), tier 0 (Outposts)

`.devin/blueprint.yaml` — **not read automatically**; requires a sync API call,
so ship the CI step too:

```yaml
initialize:
  - name: Provision clouddev environment
    run: script/clouddev/prepare
  - name: Install boot as a service
    run: script/clouddev/install-boot-service
maintenance: |
  script/clouddev/refresh
knowledge:
  - name: environment
    contents: |
      Backing services start from a systemd unit at boot. If they are not
      running, execute `script/clouddev/boot`. Verify with
      `script/clouddev/verify`.
```

There is **no per-session hook**, so `boot` must self-install. The unit
`prepare` writes is the actual adapter:

```ini
[Unit]
Description=clouddev backing services
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/ubuntu/repos/myproject
ExecStart=/home/ubuntu/repos/myproject/script/clouddev/boot

[Install]
WantedBy=multi-user.target
```

Repos clone to `~/repos/<short-name>`. Differential builds **skip
`initialize`**, so `maintenance` must stand alone and cannot rely on `$ENVRC`
values from a parent build. Files written by build steps are baked into the
snapshot — generate credentials in `boot`.

**Outposts** is tier 0 and needs no adapter beyond `devin worker start
--outpost=<name>` on a machine with `git` and outbound HTTPS.

---

## Factory — tier 3 (managed), tier 0 (BYOM / `droid exec`)

No declarative environment surface. Managed computers are configured
imperatively over SSH or by the agent.

`.factory/hooks.json` is committable, but `SessionStart` has a 60s default
timeout and is meant for context injection:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "bash",
        "command": "\"$FACTORY_PROJECT_DIR\"/script/clouddev/boot &",
        "timeout": 60
      }
    ]
  }
}
```

Hooks run from Droid's cwd, which may differ from the repo root — the
`$FACTORY_PROJECT_DIR` prefix is mandatory.

**Managed computers persist running processes** across idle-pause via memory
snapshot, so `boot` may only ever need to run once. Keep it idempotent anyway.
**Docker availability is undocumented — probe before writing this adapter.**

**BYOM / `droid exec`** are tier 0: your machine, your image, real Docker,
outbound-only through `relay.factory.ai`. No adapter needed. For `droid exec` in
CI, bring services up as ordinary CI steps and pass `--auto high` or
`--skip-permissions-unsafe` in a disposable runner.

---

## Jules — tier 3

No repo config file and no API for it. A human pastes this into the "Initial
Setup" box once:

```bash
bash script/clouddev/prepare
```

**Not `boot`** — long-running processes in the setup script are explicitly
unsupported and are a documented cause of task failure. Services have to be
started by the agent, so `AGENTS.md` carries the real instruction. No Ruby is
preinstalled; 20GB disk.

---

## The compose split, which every devcontainer-native adapter depends on

```yaml
# .devcontainer/docker-compose.yml
include:
  - ../docker/compose.services.yml

services:
  app:
    build: ...
    depends_on: [postgresql, redis]
```

Local behavior is unchanged; cloud simply never starts `app`. On Ona, every
service in the included file also needs `network_mode: host`.

---

## Tier 0 — no adapter at all

Nothing to write. Your devcontainer runs unmodified and a headless agent CLI
runs inside it:

```bash
claude -p "..."          # Claude Code
droid exec "..."         # Factory
devin -p "..."           # Cognition CLI (no `devin exec` subcommand)
junie --headless "..."   # JetBrains
```

Applies to: Devin Outposts, Factory BYOM, Coder, a self-hosted GitLab runner,
Codespaces via `gh codespace ssh`, self-hosted OpenHands, and your own CI. When
a platform fights you, this is the exit.

---

## Non-targets — agents run on your compute

Zed (ACP agents are subprocesses of the client), JetBrains Junie (*"executes
entirely on your GitHub runners"*), Goose, Aider, Cline, OpenCode, and the local
worktree orchestrators — Conductor, `oscardobsonbrown/superconductor`,
super.engineering. Nothing to adapt; they are tier 0 by construction. Don't
confuse that last group with cloud **Superconductor** (`superconductor.com`)
above, which is tier 2 and has an adapter.

---

## Tier 4 — no adapter, and record why

So their absence doesn't read as an oversight:

- **Codex cloud** — no nested Docker (`dockerd` doesn't work), fixed image.
- **Kiro Web** — no lifecycle hook, no base-image control, torn down per task
  with no snapshotting.
- **Amazon Q Developer** — sunsetting; `devfile.yaml` surface de-documented.
- **Antigravity** — IDE is local-only; the hosted Gemini API sandbox has no
  manifest, no hook, no image control, no Docker, and injects credentials only
  as HTTP headers (useless for Postgres or Redis).
- **Replit** — Nix workspace, no Docker at all, no CouchDB/Vault story.
- **Daytona** — no lifecycle hooks of any kind, OSS frozen June 2026, volumes
  explicitly cannot back a database. You'd write an orchestrator, not an
  adapter.
- **OpenHands Cloud** — no self-serve BYO image, no documented Docker. Use
  self-hosted or Enterprise instead.
- **Codegen** — fixed image, Docker undocumented, single fixed ingress port
  3000.
