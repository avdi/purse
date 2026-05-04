# Avdi's Every Day Carry

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). Compatible with
[VS Code / GitHub Codespace auto-dotfiles](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles).

## New machine setup

### Linux / macOS

```sh
chezmoi init --apply avdi/purse
```

Or if chezmoi isn't installed yet:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply avdi/purse
```

### Windows (PowerShell)

```powershell
winget install twpayne.chezmoi 
# restart PowerShell so chezmoi is on PATH, then:
chezmoi init --apply avdi/purse
```

If `winget` isn't available, install chezmoi with the upstream PowerShell bootstrap instead:

```powershell
iex "&{$(irm 'https://get.chezmoi.io/ps1')}"
& "$HOME\bin\chezmoi.exe" init --apply avdi/purse
```

Windows packages (winget + npm + Cursor agent CLI) are installed by `run_onchange_install-packages.ps1.tmpl` on first apply.

## Repo structure

```
.chezmoiroot                          # tells chezmoi: source state lives in home/
home/
  .chezmoi.toml.tmpl                  # generates ~/.config/chezmoi/chezmoi.toml
  .chezmoidata/packages.yaml          # edit this to add/remove packages
  dot_config/shell/env.sh             # → ~/.config/shell/env.sh  (EDITOR, PATH, etc.)
  dot_config/shell/aliases.sh         # → ~/.config/shell/aliases.sh
  run_onchange_install-packages.sh.tmpl   # installs packages on Linux/macOS
  run_onchange_install-packages.ps1.tmpl  # installs packages on Windows (winget)
  run_once_setup-shell.sh             # wires aliases + direnv into rc files (once)
  run_once_setup-lenticel.sh.tmpl     # bootstraps lenticel frp tunnel (once)
.install-zv.sh                        # installs Zoho Vault CLI before apply (Linux)
.install-zv.ps1                       # installs Zoho Vault CLI before apply (Windows)
install.sh                            # VS Code / Codespace auto-dotfiles hook
lenticel-bootstrap.sh                 # frp tunnel client setup
```

Packages are declared in `.chezmoidata/packages.yaml`. Adding or removing an entry
and running `chezmoi apply` is all it takes — the `run_onchange_` scripts re-run
automatically whenever the rendered package list changes.

## Secret management

Secrets (API keys, tokens, etc.) live in [Zoho Vault](https://www.zoho.com/vault/) and are never committed. The workflow has two layers:

### 1. Runtime env vars — `setup-secrets`

`~/.config/purse/secret-ids.env` maps environment variable names to Zoho Vault numeric IDs. IDs are non-sensitive and safe to commit.

```
# ~/.config/purse/secret-ids.env
ANTHROPIC_API_KEY=2000002716908
GITHUB_TOKEN=2000003012345
```

Run `setup-secrets` to pull the current values and write them to `~/.config/shell/secrets.sh` (mode 600, never committed). That file is auto-sourced by `~/.config/shell/env.sh` on every new shell.

**Adding a new secret:**

1. Add the secret to Zoho Vault (title = env var name, password = the value).
2. Find its numeric ID: `zv search -k "secret-name" --name --output json | jq '.[0]'`
3. Add `ENV_VAR_NAME=<id>` to `~/.config/purse/secret-ids.env`.
4. Run `setup-secrets`.
5. Commit the updated file: `chezmoi add ~/.config/purse/secret-ids.env`.

### 2. Chezmoi template secrets — `secretJSON`

For secrets needed at `chezmoi apply` time (e.g. to render a config file), use the `secretJSON` template function. It calls `zv get --not-safe --output json` and is wired in `.chezmoi.toml.tmpl`.

```
{{- $item := secretJSON "-id" "2000002716908" -}}
{{- $pass := "" -}}
{{- range $item.secret.secretData -}}
{{-   if eq .id "password" }}{{- $pass = .value -}}{{- end -}}
{{- end -}}
api_key = "{{ $pass }}"
```

This requires `zv` to be authenticated before running `chezmoi apply`. For bulk env-var secrets, prefer `setup-secrets` — it authenticates interactively only when needed and doesn't block `chezmoi apply`.

### `zv` CLI

`zv` (Zoho Vault CLI) is installed automatically by a chezmoi pre-hook before every `apply` — `.install-zv.sh` on Linux, `.install-zv.ps1` on Windows. Both drop the binary into `~/.local/bin/` and exit immediately if `zv` is already on PATH. Authenticate once with `zv login`.

## Links

- [chezmoi docs](https://www.chezmoi.io/user-guide/setup/)
- [chezmoi template reference](https://www.chezmoi.io/reference/templates/)
- [Codespace dotfiles docs](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles)
- [VS Code dev container dotfiles](https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories)