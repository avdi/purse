# Agent Instructions — purse

This is Avdi Grimm's dotfiles repo, managed by [chezmoi](https://www.chezmoi.io/).
Changes here are applied to the live system via `chezmoi apply` (or `purse-pull`).

## Commits and pushes

Frequent commits and pushes are expected and **do not require explicit authorization** from the user.
Commit after each logical change; push promptly. Rebase on the remote if a push is rejected.

Do not stop to ask. Do not offer to commit and wait for a yes. Do not leave the
change applied locally and the source tree dirty. Pushing to `origin` here is
routine work, not an outward-facing publication that needs a second look — the
repo is public, but its audience is Avdi's other machines.

**A change to this repo is not finished until it is applied, committed, and
pushed.** All three, in that order, in the same sitting. `chezmoi apply` fixes
the machine you are sitting at; the push is what fixes the others. An unpushed
commit means every other machine — the other PC, the Mac, tomorrow's Codespace,
the next devcontainer that installs these dotfiles — stays broken, and nothing
will remind anyone.

This holds when you arrive from somewhere else. Working in another project,
hitting an environment problem, and tracing it back to a file here is the common
case, not an exception: "fix this for my environment" means fix it everywhere,
and it is a normal detour, not a scope expansion to check in about. Finish the
dotfiles change the same way you would if you had started here, then return to
what you were doing.

### What it does not license

The policy is about not stalling on the push. It is not a license to put
anything at all into a public repo that auto-deploys to every machine. Stop and
raise these:

- **Secret values.** This repo stores secret *IDs* (`.config/purse/secret-ids.env`)
  and resolves them at runtime through `zv`; `~/.config/shell/secrets.sh` is
  chezmoiignored for exactly this reason. A live token, API key, private key, or
  password does not go in — not in a template, not in a comment, not in a commit
  message. If one is already committed, say so plainly: it needs rotating, not
  just reverting.
- **`chezmoi add` / `re-add` on a file you have not read.** Adding a directory,
  or re-adding a config some tool rewrote in place, is how a credential gets in
  by accident. Read it first.
- **Someone else's material** — a colleague's key, a client's config, an
  employer's internal hostnames or infrastructure detail. The audience is Avdi's
  own machines, but the repo is public.
- **`run_once_*` / `run_onchange_*` scripts that delete, overwrite, or `sudo`.**
  These execute unattended on every machine that pulls, including fresh
  Codespaces and devcontainers. Adding one is a decision worth confirming.
- **Boot-path and auth-path changes** — `dot_bashrc`/`dot_profile`, `env.sh`,
  `~/.ssh/config`, the git credential helper. A mistake here breaks a machine you
  are not sitting at and may not be able to reach. Apply and verify locally
  first, and keep failures non-fatal.
- **Rewriting pushed history.** Rebasing your own unpushed commits onto the
  remote is the normal answer to a rejected push. Force-pushing over commits that
  are already on `origin` is not — other machines have them.

## Repo layout

- `home/` — chezmoi source tree; files here are templated/installed into `$HOME`.
  - `dot_*` prefixes become `.` in the target path (`dot_bashrc` → `~/.bashrc`).
  - `executable_*` files are installed with the executable bit set.
  - `run_once_*` scripts are executed by chezmoi once per machine.
  - `run_onchange_*` scripts are re-executed whenever their content changes.
  - `run_before_*` / `run_after_*` scripts run before/after **every** `chezmoi apply`.
  - `home/AppData/...` — Windows-only target paths. Managed in place (no symlink);
    `.chezmoiignore` skips the whole `AppData` tree on non-Windows so it doesn't
    create stub dirs there. Currently just Windows Terminal's `settings.json`.
- `docs/` — reference documentation (not installed by chezmoi).
- `install.sh` — bootstraps chezmoi on a new machine.
- `.gitattributes` — line-ending pins for files an external app owns and rewrites.

**Gotcha — `run_` scripts always appear in `chezmoi diff`/`apply`.** chezmoi renders
every `run_` script as a "new file" diff on each apply, because it can't know whether
executing it will change anything. A `run_after_*` (or other ungated `run_*`) hook
showing up in `chezmoi diff` is **expected output, not undeployed drift** — only
`run_once_*` and `run_onchange_*` are content-gated. Don't try to "fix" it by
renaming the script or forcing an apply; it never gets written as a literal file
in `$HOME`.

## Target environments

These dotfiles are applied across several distinct contexts; keep all of them in mind when making changes:

- **Linux (WSL2)** — the primary interactive shell environment on Avdi's Windows PCs. Most shell scripts and tooling are written for this context.
- **Windows / PowerShell** — the Windows side of the same PCs. Relevant files use `.ps1` extensions; chezmoi templates gate Windows-only content with `{{ if eq .chezmoi.os "windows" }}`.
- **GitHub Codespaces** — cloud dev environments spun up from repos. Dotfiles are applied automatically by Codespaces on container start.
- **Dev containers** — local or remote Docker-based environments (VS Code devcontainer / `devcontainer` CLI). Dotfiles are injected the same way as Codespaces.
- **macOS** — in active use. It runs a BSD userland and an ancient bash, so it is
  where Linux-isms surface. When touching shell code, keep these in mind:
  - **bash is 3.2.** `"${empty[@]}"` under `set -u` is an unbound-variable error,
    not zero words — write `${arr[@]+"${arr[@]}"}`. No associative arrays, no
    `mapfile`, no `${var,,}`. `/usr/bin/env bash` finds 3.2 too unless brew's
    bash is installed, which it isn't by default.
  - **BSD tools take different flags.** `sed -i` requires a backup suffix (GNU
    forbids one — rewrite through a temp file instead); `stat -c` is `stat -f`
    (or use `[ -O ]`); `realpath` has no `-m`.
  - **GNU-only commands are absent**: `timeout`, `nproc`, `fc-cache`, `xdg-open`.
    Guard on `command -v` and degrade rather than failing.
  - **Homebrew is not on PATH after its own installer runs** — it only prints the
    `brew shellenv` line. Resolve it from `/opt/homebrew` or `/usr/local`.
  - **zsh is the login shell** and there is no default `~/.zshrc`; zsh never
    reads `~/.profile`. Anything that wires up a shell must create the rc file.
  - **`~/.local/bin` shadows system commands.** Don't install a Linux
    compatibility wrapper whose name collides with a real macOS tool (`open`).

Scripts that are platform-specific should guard themselves or be named/templated clearly. When adding a new tool or path assumption, consider whether it holds across all of the above.

## MCP servers

A short list of MCP servers is registered declaratively into each compatible AI
agent present on the machine.

- `home/.chezmoidata/mcp-servers.yaml` — the manifest: the servers (`mcpServers`)
  and the agents to configure (`mcpAgents`). Servers may declare `excludeAgents`
  for known incompatibilities; **auggie** is excluded from Copilot CLI.
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
(`GitKraken.cli` — note the casing; `winget --exact` matches ids
case-sensitively, so a lowercased id silently installs nothing) on Windows.

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

Claude Code, Codex CLI, GitHub Copilot CLI, and Auggie share the same
plugin/marketplace format (`.claude-plugin/plugin.json` manifests — Auggie also
reads `.augment-plugin` — with near-identical `plugin marketplace add` / `plugin
install`(`add` for Codex) CLI verbs), so plugins are installed into all of them
from a single declarative manifest and loop in `purse-outfit-agents`.

- `home/.chezmoidata/agent-plugins.yaml` — the manifest: `agents` (the CLIs this
  applies to), `marketplaces` (name → source, each tagged with which agents
  should register it), and `plugins` (name → marketplace, each tagged with which
  agents should install it). This lets one plugin (e.g. `context7`) fan out to
  every supporting agent while another stays Claude-only.
- `retired` mirrors those two lists for entries dropped from the shortlist, so
  `purse-outfit-agents` uninstalls them and an already-outfitted machine
  converges instead of only ever gaining plugins.
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
`purse-install-secrets`, already exported into the host shell) into the container
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
