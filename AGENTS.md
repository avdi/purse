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

## Style

- Shell scripts use `bash` with `set -euo pipefail`.
- Prefer self-explanatory code over comments; use intent-revealing function and variable names.
- Keep scripts focused and composable; prefer small helpers over monolithic scripts.
