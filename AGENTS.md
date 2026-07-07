# Agent Instructions — purse

This is Avdi Grimm's dotfiles repo, managed by [chezmoi](https://www.chezmoi.io/).
Changes here are applied to the live system via `chezmoi apply` (or `purse-pull`).

## Commits and pushes

Frequent commits and pushes are expected and **do not require explicit authorization** from the user.
Commit after each logical change; push promptly. Rebase on the remote if a push is rejected.

## Repo layout

- `home/` — chezmoi source tree; files here are templated/installed into `$HOME`.
  - `dot_*` prefixes become `.` in the target path (`dot_bashrc` → `~/.bashrc`).
  - `executable_*` files are installed with the executable bit set.
  - `run_once_*` scripts are executed by chezmoi once per machine.
  - `run_onchange_*` scripts are re-executed whenever their content changes.
- `docs/` — reference documentation (not installed by chezmoi).
- `install.sh` — bootstraps chezmoi on a new machine.

## Target environments

These dotfiles are applied across several distinct contexts; keep all of them in mind when making changes:

- **Linux (WSL2)** — the primary interactive shell environment on Avdi's Windows PCs. Most shell scripts and tooling are written for this context.
- **Windows / PowerShell** — the Windows side of the same PCs. Relevant files use `.ps1` extensions; chezmoi templates gate Windows-only content with `{{ if eq .chezmoi.os "windows" }}`.
- **GitHub Codespaces** — cloud dev environments spun up from repos. Dotfiles are applied automatically by Codespaces on container start.
- **Dev containers** — local or remote Docker-based environments (VS Code devcontainer / `devcontainer` CLI). Dotfiles are injected the same way as Codespaces.
- **macOS** — not yet in active use but planned. Assume any shell or tooling changes should remain portable (avoid Linux-isms like `readlink -f`; prefer `realpath` or POSIX idioms).

Scripts that are platform-specific should guard themselves or be named/templated clearly. When adding a new tool or path assumption, consider whether it holds across all of the above.

## MCP servers

A short list of "always-want-these" MCP servers is registered declaratively into
every AI agent present on the machine.

- `home/.chezmoidata/mcp-servers.yaml` — the manifest: the servers (`mcpServers`)
  and the agents to configure (`mcpAgents`). Currently ships **github** (remote
  HTTP), **playwright**, **auggie**, and **ripgrep** (local stdio).
- `home/dot_local/bin/executable_purse-outfit-agents.tmpl` → `purse-outfit-agents`
  — the installer. It's a **manually-invoked** step (not run on `chezmoi apply`),
  run after `purse-install-agents`, because alongside MCP registration it also
  installs agent plugins, registers the **GitKraken MCP** server (`gk mcp install
  --all`), and downloads the `codebase-memory-mcp` binary — together too slow
  to run inline. It only touches agents whose CLI/config is actually detected, and
  is idempotent (safe to re-run). The end-of-apply reminder (`run_after_show-setup-reminders`)
  nudges you to run it.

The **GitKraken MCP** server is the exception to the declarative manifest above:
`gk` (the GitKraken CLI) ships its own multi-client installer, so rather than
listing it in `mcp-servers.yaml` we let `gk mcp install --all` detect every
installed MCP client and write the stdio entry itself. `gk` is installed by
`run_onchange_install-packages` — from GitHub releases into `~/.local/bin` on
Unix (it's not in apt and brew ships it as a macOS-only cask), and via winget
(`gitkraken.cli`) on Windows.

Registration is per-agent: agents with a non-interactive MCP CLI are configured
via that CLI (`claude`, `codex`, `copilot`, `auggie`, `vscode`); agents whose CLI
triggers an OAuth/browser login or that lack a CLI are configured by merging JSON
directly into their config file with `jq` (`cursor`, `opencode`, `devin`,
`antigravity`).

**Secrets:** the manifest and generated configs contain **only environment-variable
reference strings** (e.g. `${GITHUB_PERSONAL_ACCESS_TOKEN}`) — never token values.
Each agent expands them from the shell environment at runtime. To add a server,
edit the manifest; do not hand-edit per-agent config files.

`jq` is a hard dependency of the installer (declared in `packages.yaml`).

## Agent plugins

Claude Code, Codex CLI, and GitHub Copilot CLI share the same plugin/marketplace
format (`.claude-plugin/plugin.json` manifests, near-identical `plugin marketplace
add` / `plugin install`(`add` for Codex) CLI verbs), so plugins are installed
into all three from a single declarative manifest and loop in
`purse-outfit-agents`.

- `home/.chezmoidata/agent-plugins.yaml` — the manifest: `agents` (the CLIs this
  applies to), `marketplaces` (name → source, each tagged with which agents
  should register it), and `plugins` (name → marketplace, each tagged with which
  agents should install it). This lets one plugin (e.g. `superpowers`) fan out to
  every supporting agent while another stays Claude-only.
- VS Code also supports this plugin format (Preview), but only via global-user
  `settings.json` — no CLI verb — so it's intentionally left unmanaged, alongside
  Cursor/Devin/Antigravity which don't share the format at all.

## Secrets — Zoho Vault

Avdi uses [Zoho Vault](https://www.zoho.com/vault/) as his password/secret manager, **not** 1Password, Bitwarden, or the system keychain. When secrets need to be referenced in scripts or configs, expect them to come from Zoho Vault (typically via a CLI or manual retrieval), not from another secret store. Do not assume or generate integrations with other secret managers.

**WSL2 keyring quirk:** the Linux `zv` binary persists its session via libsecret's
Secret Service (gnome-keyring + D-Bus), which is unreliable under WSL2. The
`~/.local/share/purse/shims/zv` shim (`home/dot_local/share/purse/shims/executable_zv.tmpl`)
transparently routes `zv` through the Windows `zv.exe` on WSL2 — its session lives
in the Windows Credential Manager instead. It falls through to the Linux `zv` off
WSL2, when no Windows `zv.exe` is found, or when `PURSE_ZV_WINDOWS=0`.

**Devcontainer secrets:** containers have no Windows interop and no keyring, so
`zv` stays host-only there. Instead the `devcontainer`/`dc` shim
(`home/dot_local/share/purse/shims/executable_devcontainer.tmpl`) forwards every
var declared in `~/.config/shell/secrets.sh` (the `PURSE_TOKENS` vars written by
`purse-setup-secrets`, already exported into the host shell) into the container
via `--remote-env` — reading only the var names from the file, values from the
live host env. Opt out with `PURSE_DEVCONTAINER_FORWARD_SECRETS=0`. So don't try
to run `zv login`/`unlock` inside a container; forward from the host instead.

**GPG signing:** `home/private_dot_gnupg/private_gpg-agent.conf.tmpl` pins
`pinentry-program` to `pinentry-curses` for inline TTY passphrase prompts (no GUI
popup); `home/run_onchange_reload-gpg-agent.sh.tmpl` reloads the agent on change.

## PATH hygiene

`env.sh` is the single owner of PATH construction. It prepends `~/.local/bin`
(dedup) and then unconditionally strips-and-prepends `~/.local/share/purse/shims`
so the devcontainer shim always shadows the real binary regardless of what else
has touched PATH.

**Known problem:** AI agent and tool installers routinely append lines like
`export PATH="$HOME/.local/bin:$PATH"` directly to `~/.bashrc` or `~/.profile`
as a side-effect of their install step. This re-buries the purse shims behind
`~/.local/bin` and breaks `dc up` config injection. Confirmed offenders so far:
Antigravity CLI (writes to both `~/.bashrc` and `~/.profile`).

`purse-outfit-agents` automatically scrubs these lines from both files at the
end of its run. If the shim ever stops winning again, check both files for
new installer-injected PATH lines matching
`^export PATH=.*\.local/bin.*PATH` and add them to the scrub loop (or just
re-run `purse-outfit-agents`).

## Style

- Shell scripts use `bash` with `set -euo pipefail`.
- Prefer self-explanatory code over comments; use intent-revealing function and variable names.
- Keep scripts focused and composable; prefer small helpers over monolithic scripts.
