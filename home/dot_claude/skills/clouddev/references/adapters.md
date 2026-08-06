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

## Codespaces / Gitpod / Coder / Daytona — tier 1

No adapter. These read `devcontainer.json` natively.

The only requirement is that splitting compose doesn't break them:

```yaml
# .devcontainer/docker-compose.yml
include:
  - ../docker/compose.services.yml

services:
  app:
    build: ...
    depends_on: [postgresql, redis]
```

---

## Codex cloud / Kiro Web / Amazon Q — tier 4, no adapter

Unsupported, for reasons worth recording in the project so their absence doesn't
read as an oversight:

- **Codex** — no nested Docker (`dockerd` doesn't work), fixed image. Backing
  services would need a native-install path that never runs locally and rots.
- **Kiro Web** — no documented lifecycle hook, no base-image control, sandbox
  torn down per task with no snapshotting.
- **Amazon Q Developer** — sunsetting (signups closed 2026-05-15); its
  `devfile.yaml` surface has been de-documented.
