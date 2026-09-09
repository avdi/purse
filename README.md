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
  dot_local/bin/executable_dcsh       # → ~/.local/bin/dcsh (shell into this project's
                                      #   devcontainer; makes the containerised agent
                                      #   legible to herdr — see "herdr" below)
  dot_local/bin/executable_dcbridge   # → ~/.local/bin/dcbridge (reconciles every running
                                      #   devcontainer: ports, secrets, herdr relay)
  dot_local/bin/executable_herdr-bridge   # → ~/.local/bin/herdr-bridge (fronts herdr's
                                      #   control socket on a loopback port)
  dot_local/share/purse/lib/herdr-relay.py
                                      # pushed into each container by dcbridge; the
                                      #   container half of herdr-bridge
  dot_local/share/purse/shims/executable_devcontainer.tmpl
                                      # → ~/.local/share/purse/shims/devcontainer
                                      #   shim that wraps `devcontainer up`; see
                                      #   "Devcontainer integration" below
                                      #   (PATH-prepended in env.sh)
  run_onchange_install-packages.sh.tmpl   # installs packages on Linux/macOS
  run_onchange_install-packages.ps1.tmpl  # installs packages on Windows (winget)
  run_once_setup-shell.sh             # wires aliases + direnv into rc files (once)
  run_after_install-herdr.sh.tmpl     # installs herdr + refreshes its agent integration
                                      #   hooks on every apply (host and container)
  run_once_setup-lenticel.sh.tmpl     # bootstraps lenticel frp tunnel (once)
  AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json
                                      # → Windows Terminal settings (Windows only;
                                      #   .chezmoiignore skips the AppData tree
                                      #   everywhere else). See "Windows Terminal".
.install-zv.sh                        # installs Zoho Vault CLI before apply (Linux/macOS)
.install-zv.ps1                       # installs Zoho Vault CLI before apply (Windows)
install.sh                            # VS Code / Codespace auto-dotfiles hook
lenticel-bootstrap.sh                 # frp tunnel client setup
```

Packages are declared in `.chezmoidata/packages.yaml`. Adding or removing an entry
and running `chezmoi apply` is all it takes — the `run_onchange_` scripts re-run
automatically whenever the rendered package list changes.

## Windows Terminal

Windows Terminal's `settings.json` is managed **in place**, at its real path under
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`.

Not via a symlink. The old `avdi/dotfiles` repo symlinked that path into the repo,
and Windows Terminal eventually replaced the symlink with a plain file — silently
detaching the config from version control. Managing the file directly avoids that
whole failure mode.

The trade-off is that Windows Terminal owns the file and rewrites it whenever you
change a setting in the UI. So the workflow is bidirectional:

```bash
chezmoi diff        # see what the UI changed since the last sync
chezmoi re-add "$LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
chezmoi apply       # push repo state back out (e.g. on a new machine)
```

Deliberately kept as a plain file, **not** a `.tmpl`, so `chezmoi re-add` round-trips
cleanly. `.gitattributes` pins it to `eol=lf`, because Windows Terminal writes LF and
`core.autocrlf=true` would otherwise check it out as CRLF and make every `chezmoi diff`
report the entire file as drifted.

## Secret management

Secrets (API keys, tokens, etc.) live in [Zoho Vault](https://www.zoho.com/vault/) and are never committed. The workflow has two layers:

### 1. Runtime env vars — `purse-install-secrets`

`~/.config/purse/secret-ids.env` maps environment variable names to Zoho Vault numeric IDs. IDs are non-sensitive and safe to commit.

```
# ~/.config/purse/secret-ids.env
ANTHROPIC_API_KEY=2000002716908
GITHUB_TOKEN=2000003012345
```

Run `purse-install-secrets` (aliases: `purse-setup-secrets`, `setup-secrets`) to pull the current values and write them to `~/.config/shell/secrets.sh` (mode 600, never committed). That file is auto-sourced by `~/.config/shell/env.sh` on every new shell.

`zv` is host-side only. It keeps its session in the OS credential store — libsecret's Secret Service on Linux — which a container has no D-Bus session to reach, so `zv login` there reports success and the next command says "Credentials not found". Run `purse-install-secrets` on the host; the `devcontainer` shim forwards the resulting values into the container as env vars. `purse-zv-guard` is what warns you off the container-side path (`PURSE_ZV_ALLOW_CONTAINER=1` to override).

**Adding a new secret:**

1. Add the secret to Zoho Vault (title = env var name, password = the value).
2. Find its numeric ID: `purse-get-secret-id ENV_VAR_NAME`
3. Add `ENV_VAR_NAME=<id>` to `~/.config/purse/secret-ids.env`.
4. Run `purse-install-secrets`.
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

This requires `zv` to be authenticated before running `chezmoi apply`. For bulk env-var secrets, prefer `purse-install-secrets` — it authenticates interactively only when needed and doesn't block `chezmoi apply`.

### `zv` CLI

`zv` (Zoho Vault CLI) is installed automatically by a chezmoi pre-hook before every `apply` — `.install-zv.sh` on Linux and macOS, `.install-zv.ps1` on Windows. Both drop the binary into `~/.local/bin/` and exit immediately if a real `zv` is already on PATH (the purse shim doesn't count). Authenticate once with `zv login`.

**macOS:** Zoho publishes an x86_64-only build, so Apple silicon needs Rosetta 2. Without it the hook declines to install rather than leaving a binary that dies with "bad CPU type" on every call; `purse-zv-remedy` prints the fix (`softwareupdate --install-rosetta --agree-to-license`).

**WSL2 keyring:** the Linux `zv` stores its vault session via libsecret's Secret Service (gnome-keyring + D-Bus), which is fragile under WSL2. On WSL2 the `~/.local/share/purse/shims/zv` shim therefore routes `zv` through the Windows `zv.exe`, whose session lives in the durable Windows Credential Manager. It falls through to the Linux `zv` off WSL2, when no Windows `zv.exe` is found, or when `PURSE_ZV_WINDOWS=0`. Authenticate the Windows side once with `zv login`.

### GPG commit signing

`~/.gnupg/gpg-agent.conf` (managed by chezmoi, Unix only) sets `pinentry-program` to `pinentry-curses` so passphrase prompts appear inline in the terminal rather than as a GUI popup — reliable on WSL2 where the GUI pinentry routes through WSLg. `GPG_TTY` is exported in `env.sh`. A `run_onchange` hook reloads `gpg-agent` when the resolved pinentry changes.

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
| Forward every secret from `~/.config/shell/secrets.sh` (the `PURSE_TOKENS` vars, already in the host shell) via `--remote-env` — containers have no keyring/`zv`, so this is how in-container tools get vault secrets | on | `PURSE_DEVCONTAINER_FORWARD_SECRETS=0` (or `PURSE_DEVCONTAINER_SECRETS_FILE=` to point elsewhere) |
| **WSLg X11/Wayland/PulseAudio forwarding** — mount `/tmp/.X11-unix` and `/mnt/wslg`, set `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `PULSE_SERVER` so GUI apps render on the host Windows desktop | on (when `/mnt/wslg` exists) | `PURSE_DEVCONTAINER_FORWARD_WSLG=0` |
| **devcontainer-bridge (dbr)** — inject `--additional-features` for [`bradleybeddoes/devcontainer-bridge`](https://github.com/bradleybeddoes/devcontainer-bridge) so host-port forwarding and `xdg-open` → host browser work like in VS Code. Runs `dbr ensure` opportunistically if `dbr` is on the host's PATH. | on | `PURSE_DEVCONTAINER_FORWARD_DBR=0` |

`dbr` requires a one-time host install (`curl -fsSL https://github.com/bradleybeddoes/devcontainer-bridge/releases/latest/download/install.sh | bash`) and runs a long-lived host daemon. Without it the injected feature is inert — the container daemon just retries silently — so containers still come up cleanly.

A container the shim did not create — started by VS Code, by `docker compose up`, or built without the feature — gets no bridge from the shim at all. `dcbridge` reconciles those: it runs the host dbr daemon, starts a container daemon in anything missing one, drops the host's resolved vault secrets on tmpfs where `env.sh` sources them (`--remote-env` only decorates `devcontainer exec`, so an sshd or `docker exec` shell inherits none of them), and maintains the herdr relay described below. `dcbridge --install` runs it as a systemd user service; `chezmoi apply` installs that service on a host. `dcbridge --status` reports all three.

To make `xdg-open` and `$BROWSER` actually reach the host browser, set `BROWSER=dbr-open` in your container shell rc (already wired into purse dotfiles).

## herdr — one workspace, every container

[herdr](https://herdr.dev) is a terminal workspace manager for coding agents: panes, a
sidebar listing every agent it can see, and each agent's live state — working, idle,
waiting on input — read off that pane's terminal.

One herdr runs on the host, and its panes reach into containers with `dcsh` (or the
`work` shell function that wraps it). Every project's containerised agent lands in that
one sidebar, and a pane costs a container shell rather than a second herdr server. The
alternative — `herdr --remote` per project — is one server and one sidebar per repo.

### What herdr needs from a pane, and where each piece comes from

| herdr wants | Source | Crosses the container wall via |
|---|---|---|
| the agent's **state** | the pane's terminal, matched against herdr's downloadable rule manifest | nothing — a pty is a pty |
| the agent's **identity** | the pane's foreground process, or a report over the socket API | `dcsh --agent` → `HERDR_AGENT` on the host-side CLI; or `purse-agent` inside the container → the same relay as the session id |
| the agent's **session id** | the agent's own herdr integration hook, inside the container | `$HERDR_SOCKET_PATH` → `herdr-relay` → `herdr-bridge` → the host's `herdr.sock` |

Identity is the load-bearing one: without it herdr sees no agent in the pane and never
consults the rules that would have matched. With it, detection, state, `herdr agent
prompt` and `herdr agent wait` all work against a containerised agent. The session id
buys one further thing — `resume_agents_on_restore`, which needs the agent's *native*
session id to pick a conversation back up after a herdr restart.

**Identity, when the agent is named up front.** `devcontainer exec` starts the CLI's
own node interpreter, so the pane's foreground process is `node`. `dcsh --agent claude`
knows the answer before it execs, and sets `HERDR_AGENT=claude` on that process — the
hint herdr documents for exactly this, wrappers that hide the real agent from it. herdr
then treats the pane as holding Claude Code and applies the same screen-detection
manifest it would use for a host-run one. Nothing has to be reported back, and state is
as good as it is on the host.

**Identity, when you type the agent's name inside the container.** Nothing on the host
can know: `HERDR_AGENT` is fixed at exec, long before you reach a container prompt. So
the agent says so itself. `purse-agent` — which every agent command routes through
inside a container — reports the pane over the same relay the session id uses. herdr
accepts a reported agent with no matching process anywhere, which is the only thing that
can work through a container wall.

That report carries lifecycle authority along with the name; the two cannot be
separated, and authority never lapses on its own. So `purse-agent` also owns the state
while it holds the pane, and takes it from herdr itself: `herdr agent explain` returns
the screen verdict even while a reporter is authoritative, so the wrapper mirrors that
back once a second. Same manifests, same answers, one interval late. It releases the
pane when the agent exits — a claim left behind is a pane labelled with an agent that
stopped running, and herdr will hold it forever.

**Session id.** `herdr-bridge` fronts the host's `~/.config/herdr/herdr.sock` on
`127.0.0.1:19287`, behind a shared token at `~/.config/herdr-bridge/auth-token` — the
same shape dbr uses for its own control channel on 19285/19286. `dcbridge` pushes
`herdr-relay.py` and a copy of the token into `/dev/shm` of every running devcontainer
and keeps the relay alive, restarting it whenever the script or the token changes. The
relay listens on a unix socket at `/dev/shm/herdr.sock` because `AF_UNIX` is the only
thing herdr's integration hooks know how to open; `dcsh` points `$HERDR_SOCKET_PATH`
there. A container with no relay leaves the hook with a socket that won't connect, which
it already treats as "no herdr" and skips.

Loopback is not a weaker bind than it reads as: Docker Desktop NATs the container's
outbound connection so it arrives on `127.0.0.1`. Plain Linux Docker needs
`HERDR_BRIDGE_BIND` pointed at the bridge gateway instead. The relay needs `python3` in
the container (purse installs it); a container without one is skipped silently.

> **The token is a host credential.** Whoever holds it can drive herdr, and herdr can
> start processes on the host. Handing it to a container is a real trade.
> `DCBRIDGE_SYNC_HERDR=0` declines it and keeps everything else.

### Using it

```sh
herdr                          # on the host
work myproject some-branch     # dc up + dcsh + wt switch, from a herdr pane
dcclaude                       # straight into an agent (alias for dcsh --agent claude)
dcsh                           # or a plain shell, and type `claude` when you get there
```

Both doors work. `dcclaude` is the better one — native detection, herdr's own state
reading, nothing polling — and `dcsh` then `claude` is the one you take by habit, which
is why it is covered too.

Nothing is configured per project. `dcsh` forwards the pane's identity only when it is
actually running in a herdr pane (`HERDR_ENV=1` with a `HERDR_PANE_ID`), and only names
commands it recognises as agents. Inside the container, `purse-agent` stands down
whenever herdr already sees an agent in the pane — which covers the `--agent` door and
every agent whose own integration reports its whole lifecycle.

### Checking it

```sh
dcbridge --status         # herdr bridge up? relay up in each container?
herdr-bridge status       # daemon, listener, socket, token file, log
herdr integration status  # whether each agent's hook is current
```

`~/.config/herdr-bridge/daemon.log` and the container's `/tmp/herdr-relay.log` hold the
refusals — a bad token is visible nowhere else.

### Setup and knobs

`run_after_install-herdr.sh.tmpl` runs on **every** apply, on hosts and inside containers.
It installs the herdr binary if it is missing (herdr updates itself after that), then
asks `herdr integration status` which hooks have fallen behind herdr's current format
version and reinstalls those — a stale hook stops reporting and says nothing about it.
Only agents whose CLI is actually present get a hook. On a host it also installs the
`dcbridge` user service, which is what supervises the relays.

| Knob | Default | Effect |
|---|---|---|
| `PURSE_INSTALL_HERDR` | `1` | `0` skips installing herdr and its integrations entirely |
| `DCBRIDGE_SYNC_HERDR` | `1` | `0` runs no bridge daemon and pushes no relay into containers |
| `DCSH_HERDR` | `1` | `0` stops `dcsh` forwarding pane identity and naming the agent |
| `DCSH_AGENT` | *(derived from the command)* | force the agent name `dcsh` hands herdr |
| `PURSE_AGENT` | `1` | `0` makes `purse-agent` a pass-through: no install, no outfit, no herdr |
| `PURSE_AGENT_HERDR` | `1` | `0` keeps the provisioning half but never claims a pane |
| `PURSE_AGENT_POLL_SECONDS` | `1` | how often the container mirrors herdr's screen verdict back |
| `HERDR_BRIDGE_PORT` / `HERDR_BRIDGE_BIND` | `19287` / `127.0.0.1` | move the listener |
| `HERDR_BRIDGE_SOCKET` | `~/.config/herdr/herdr.sock` | front a different herdr session's socket |

## Links

- [chezmoi docs](https://www.chezmoi.io/user-guide/setup/)
- [chezmoi template reference](https://www.chezmoi.io/reference/templates/)
- [Codespace dotfiles docs](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles)
- [VS Code dev container dotfiles](https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories)