# Platform capability matrix

**Every entry carries a checked date. Treat a stale entry as unknown, not as
true.** These platforms ship changes monthly; re-read the linked doc before
making a decision that costs real time — above all "can this platform take my
image?"

## Summary

| Platform | Base image | Nested Docker | Customization hook | Topology | Checked |
|---|---|---|---|---|---|
| Claude Code cloud | Anthropic's, **not replaceable** | yes | setup script (UI) | container | 2026-08-06 |
| Cursor cloud agents | yours (Dockerfile) | yes | `.cursor/environment.json` | direct | 2026-08-06 |
| Devin | VM + machine snapshots | yes | snapshot startup commands | direct | 2026-08-06 |
| Augment Cosmos | any **public** registry image | unverified | `/hooks/*.sh` | direct | 2026-08-06 |
| Factory droids | managed, or bring-your-own-machine | yes on BYOM | cloud templates / persistent computers | direct | 2026-08-06 |
| Copilot coding agent | GitHub Actions runner | yes | `copilot-setup-steps.yml` | direct | 2026-08-06 |
| Codespaces | yours, **devcontainer-native** | yes | `devcontainer.json` | direct | 2026-08-06 |
| Codex cloud | `universal`, **fixed** | **no** | setup script | *unsupported* | 2026-08-06 |

Gitpod/Ona, Coder, and Daytona are also devcontainer-native and behave like
Codespaces for this contract's purposes; unverified in detail.

## Per-platform notes

### Claude Code cloud — checked 2026-08-06
<https://code.claude.com/docs/en/cloud-environments>

- Base image **cannot** be replaced. Docs state the supported paths are to
  install on top via setup script, or "run your own image as a container
  alongside Claude with `docker compose`" — the latter is this contract's
  container topology.
- `docker`, `dockerd`, `docker compose` all preinstalled. PostgreSQL 16 and
  Redis 7 preinstalled but **not running** (`service postgresql start`).
- Preinstalled runtimes include Ruby 3.1/3.2/3.3 + rbenv, Node 20/21/22 via
  nvm, Python 3.x, Go, Rust, PHP 8.4, OpenJDK 21.
- **Environment caching**: the setup script runs once, then the filesystem is
  snapshotted and reused. Installed packages, pulled images, and written files
  carry over; **running processes do not**. Re-runs when the setup script or
  the allowed-host list changes, or after roughly seven days.
- Network access levels: `None` / `Trusted` (allowlisted registries + GitHub) /
  `Full` / `Custom` allowlist. Docker Hub is in the Trusted defaults.
- No interactive shell for the human — the agent runs every command.
- Consequence for this contract: put `docker compose pull`/`build` in `setup`
  so images land in the snapshot; put `services-up` in a `SessionStart` hook,
  because the snapshot won't preserve running containers.

### Cursor cloud agents — checked 2026-08-06
<https://docs.cursor.com/en/cloud-agents> ·
DinD example: <https://github.com/amacneil/cursor-cloud-agent-dind>

- `.cursor/environment.json` takes a `build.dockerfile`, plus install and start
  scripts. Your image, so direct topology.
- Docker-in-Docker works but compose services reportedly need
  `network_mode: host`, and `docker build` needs `--network=host`.
- Known friction: secrets set in the UI have been reported missing from the
  agent terminal when `environment.json` builds from a Dockerfile. Verify
  before depending on registry credentials there.

### Devin — checked 2026-08-06
<https://docs.devin.ai/use-cases/tutorials/containerization>

- Machine snapshots (custom `blockdiff` VM snapshot format) save installed
  state; each snapshot supports startup commands that run every session. That
  maps onto `setup` (baked into the snapshot) and `services-up` (startup
  command).
- Full VM, so compose works normally.

### Augment Cosmos — checked 2026-08-06
<https://docs.augmentcode.com/cosmos/environments/cloud>

- Base image: "any image from a **public** Docker registry" with `bash` and
  `git` present. **Private-registry pull is not documented** — verify before
  planning on a private dev image here.
- Lifecycle hooks live in `/hooks`; `on_refresh.sh` runs every 12 hours if
  enabled, and by default git-pulls repos in `/workspace`.
- Environments are org-shared and each session starts from a fresh snapshot.
- Network is **egress-only**.
- Secrets warning from their docs: anything put in environment variables or
  files is visible to every user and agent that starts a session there.

### Factory droids — checked 2026-08-06
<https://docs.factory.ai/droid-computers/overview>

- Two paths: Factory-managed cloud computers, or **bring your own machine** —
  the latter is the clean fit, since it's your box and your image.
- Droid Computers are persistent: installed packages, files, and running
  services survive between sessions, unlike the snapshot-only platforms.
- Cloud Templates (the older mechanism) still supported, superseded by Droid
  Computers.

### Copilot coding agent — checked 2026-08-06
<https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment>

- **Does not read `devcontainer.json`.** Configuration is
  `.github/workflows/copilot-setup-steps.yml`, containing a single
  `copilot-setup-steps` job that runs before the agent starts.
- It's an Actions runner, so Docker *is* available — compose works, in Actions
  idiom.
- Direct topology, but with GitHub's runner image, not yours. Either install
  the toolchain in the setup steps, or pull your dev image and use the
  container topology.

### Codespaces — checked 2026-08-06

- Devcontainer-native: reads `dockerComposeFile`, features, and lifecycle
  commands. The only platform where the existing devcontainer needs no
  adaptation at all.
- Splitting compose for this contract must keep the devcontainer's compose file
  working — have it `include` the services file and add `app`.

### Codex cloud — **unsupported** — checked 2026-08-06
<https://developers.openai.com/codex/cloud/environments>

- Fixed `universal` container image; runtime versions can be pinned in
  environment settings, but the image cannot be replaced.
- **`dockerd` does not work** — no nested Docker, so no compose, so no backing
  services short of installing them natively.
- Two-phase runtime: internet access during the setup script, **off by default**
  during the agent phase (configurable to limited or unrestricted). Lazy
  dependency installs at agent time fail.
- Supporting it requires a native-install provisioning path — a second
  environment definition that never runs locally and therefore rots. Document
  the platform as unsupported rather than building it.
