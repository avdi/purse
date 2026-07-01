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
  dot_local/bin/executable_dc         # → ~/.local/bin/dc  (devcontainer shorthand)
  dot_local/share/purse/shims/executable_devcontainer.tmpl
                                      # → ~/.local/share/purse/shims/devcontainer
                                      #   shim that wraps `devcontainer up`; see
                                      #   "Devcontainer integration" below
                                      #   (PATH-prepended in env.sh)
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

### 1. Runtime env vars — `purse-setup-secrets`

`~/.config/purse/secret-ids.env` maps environment variable names to Zoho Vault numeric IDs. IDs are non-sensitive and safe to commit.

```
# ~/.config/purse/secret-ids.env
ANTHROPIC_API_KEY=2000002716908
GITHUB_TOKEN=2000003012345
```

Run `purse-setup-secrets` (alias: `setup-secrets`) to pull the current values and write them to `~/.config/shell/secrets.sh` (mode 600, never committed). That file is auto-sourced by `~/.config/shell/env.sh` on every new shell.

**Adding a new secret:**

1. Add the secret to Zoho Vault (title = env var name, password = the value).
2. Find its numeric ID: `zv search -k "secret-name" --name --output json | jq '.[0]'`
3. Add `ENV_VAR_NAME=<id>` to `~/.config/purse/secret-ids.env`.
4. Run `purse-setup-secrets`.
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

This requires `zv` to be authenticated before running `chezmoi apply`. For bulk env-var secrets, prefer `purse-setup-secrets` — it authenticates interactively only when needed and doesn't block `chezmoi apply`.

### `zv` CLI

`zv` (Zoho Vault CLI) is installed automatically by a chezmoi pre-hook before every `apply` — `.install-zv.sh` on Linux, `.install-zv.ps1` on Windows. Both drop the binary into `~/.local/bin/` and exit immediately if `zv` is already on PATH. Authenticate once with `zv login`.

## Devcontainer integration

`~/.local/share/purse/shims/devcontainer` wraps the `@devcontainers/cli` so that
`devcontainer up` (and the `dc` shorthand) behaves more like the VS Code Dev
Containers extension. It's prepended to `PATH` by `env.sh`; non-`up` subcommands
pass through untouched.

For every `up` invocation the shim adds:

| Behavior | Default | Opt-out |
|---|---|---|
| Inject `--dotfiles-{repository,install-command,target-path}` so this repo applies inside the container | on | pass any `--dotfiles-*` flag yourself |
| Forward `GH_TOKEN`, `GITHUB_TOKEN`, `BUNDLE_GITHUB__COM` via `--remote-env`, lazy-fetching missing values from `gh auth token` | on | `PURSE_DEVCONTAINER_FORWARD_ENV=""` (or override the list) |
| **WSLg X11/Wayland/PulseAudio forwarding** — mount `/tmp/.X11-unix` and `/mnt/wslg`, set `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `PULSE_SERVER` so GUI apps render on the host Windows desktop | on (when `/mnt/wslg` exists) | `PURSE_DEVCONTAINER_FORWARD_WSLG=0` |
| **devcontainer-bridge (dbr)** — inject `--additional-features` for [`bradleybeddoes/devcontainer-bridge`](https://github.com/bradleybeddoes/devcontainer-bridge) so host-port forwarding and `xdg-open` → host browser work like in VS Code. Runs `dbr ensure` opportunistically if `dbr` is on the host's PATH. | on | `PURSE_DEVCONTAINER_FORWARD_DBR=0` |

`dbr` requires a one-time host install (`curl -fsSL https://github.com/bradleybeddoes/devcontainer-bridge/releases/latest/download/install.sh | bash`) and runs a long-lived host daemon. Without it the injected feature is inert — the container daemon just retries silently — so containers still come up cleanly.

To make `xdg-open` and `$BROWSER` actually reach the host browser, set `BROWSER=dbr-open` in your container shell rc (already wired into purse dotfiles).

## Links

- [chezmoi docs](https://www.chezmoi.io/user-guide/setup/)
- [chezmoi template reference](https://www.chezmoi.io/reference/templates/)
- [Codespace dotfiles docs](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles)
- [VS Code dev container dotfiles](https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories)