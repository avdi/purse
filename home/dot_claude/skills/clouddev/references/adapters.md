# Adapter templates

Adapters are **generated from `clouddev.yml`, not written**. Each one is a few
lines that call the manifest's scripts. Anything conditional belongs in `setup`
or `exec`, where it can be exercised locally.

Adapter files are the one artifact class whose location is **forced** — each
platform dictates its own path. That's why the manifest exists: it's the single
anchor every scattered adapter points back at.

Regenerate all adapters whenever the manifest changes.

---

## Claude Code cloud — container topology

No file in the repo; the setup script is configured in the environment UI at
`claude.ai`. Body:

```bash
#!/usr/bin/env bash
set -euo pipefail
script/clouddev/setup
```

Pull and build inside `setup` so images land in the filesystem snapshot.
Because the snapshot preserves disk but **not running processes**, bring
services up per session with a `SessionStart` hook in the repo:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "script/clouddev/services-up" }] }
    ]
  }
}
```

Set the environment's network access to `Trusted` at minimum (Docker Hub is in
the defaults); add a `Custom` allowlist entry for a private registry host.

Registry credentials go in the environment's variables — visible to anyone who
can use the environment, so use a read-only pull token.

---

## Cursor cloud agents — direct topology

`.cursor/environment.json`:

```json
{
  "build": { "dockerfile": ".devcontainer/Dockerfile" },
  "install": "script/clouddev/setup",
  "start": "script/clouddev/services-up",
  "terminals": []
}
```

Compose services may need `network_mode: host`, and `docker build` may need
`--network=host`. Verify secrets actually reach the agent terminal before
depending on registry credentials here.

---

## Copilot coding agent — direct topology

`.github/workflows/copilot-setup-steps.yml`. Must be a **single** job named
exactly `copilot-setup-steps`:

```yaml
name: Copilot setup steps
on: workflow_dispatch

jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Provision clouddev environment
        run: script/clouddev/setup
      - name: Start backing services
        run: script/clouddev/services-up
      - name: Verify
        run: script/clouddev/verify
```

It does **not** read `devcontainer.json`. Docker is available on the runner, so
either install the toolchain in these steps or pull the dev image and use the
container topology.

---

## Augment Cosmos — direct topology

Configured in the Cosmos UI, not the repo:

- **Base image**: the manifest's `image`. Verify a **private** image can be
  pulled — the docs describe public registry images.
- **`/hooks/on_refresh.sh`**: append `script/clouddev/setup`.

Egress-only network. Environment variables are visible to every user and agent
that starts a session in the environment — read-only pull tokens only.

---

## Devin — direct topology

Configured per machine snapshot:

- Run `script/clouddev/setup` once while building the snapshot, so installed
  state is baked in.
- Set the snapshot's **startup command** to `script/clouddev/services-up`.

---

## Factory droids — direct topology

Prefer **bring-your-own-machine**: it's your box and your image, so the
adapter is just running `setup` once and `services-up` on boot.

Droid Computers are persistent — installed packages, files, and running
services survive between sessions — so `services-up` may only need to run once
rather than per session. Keep it idempotent regardless.

---

## Codespaces / Gitpod / Coder / Daytona — direct topology

No adapter. These read `devcontainer.json` natively.

The only requirement is that splitting compose doesn't break them: have the
devcontainer's compose file `include` the services file and add `app`.

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

## Codex cloud — no adapter

Unsupported: no nested Docker, so no compose, so no backing services without a
native-install provisioning path that would rot. Record the reason in the
project rather than leaving its absence looking like an oversight.
