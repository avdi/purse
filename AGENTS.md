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

## Secrets — Zoho Vault

Avdi uses [Zoho Vault](https://www.zoho.com/vault/) as his password/secret manager, **not** 1Password, Bitwarden, or the system keychain. When secrets need to be referenced in scripts or configs, expect them to come from Zoho Vault (typically via a CLI or manual retrieval), not from another secret store. Do not assume or generate integrations with other secret managers.

## Style

- Shell scripts use `bash` with `set -euo pipefail`.
- Prefer self-explanatory code over comments; use intent-revealing function and variable names.
- Keep scripts focused and composable; prefer small helpers over monolithic scripts.
