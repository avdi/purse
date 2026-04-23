# Avdi's Every Day Carry

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). Compatible with
[VS Code / GitHub Codespace auto-dotfiles](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles).

## New machine setup

```sh
chezmoi init --apply avdi/purse
```

Or if chezmoi isn't installed yet:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply avdi/purse
```

## Repo structure

```
.chezmoiroot                          # tells chezmoi: source state lives in home/
home/
  .chezmoi.toml.tmpl                  # generates ~/.config/chezmoi/chezmoi.toml
  .chezmoidata/packages.yaml          # edit this to add/remove packages
  dot_config/shell/aliases.sh         # → ~/.config/shell/aliases.sh
  run_onchange_install-packages.sh.tmpl   # installs packages on Linux/macOS
  run_onchange_install-packages.ps1.tmpl  # installs packages on Windows (winget)
  run_once_setup-shell.sh             # wires aliases + direnv into rc files (once)
  run_once_setup-lenticel.sh.tmpl     # bootstraps lenticel frp tunnel (once)
.install-zv.sh                        # installs Zoho Vault CLI before apply
install.sh                            # VS Code / Codespace auto-dotfiles hook
lenticel-bootstrap.sh                 # frp tunnel client setup
```

Packages are declared in `.chezmoidata/packages.yaml`. Adding or removing an entry
and running `chezmoi apply` is all it takes — the `run_onchange_` scripts re-run
automatically whenever the rendered package list changes.

## Links

- [chezmoi docs](https://www.chezmoi.io/user-guide/setup/)
- [chezmoi template reference](https://www.chezmoi.io/reference/templates/)
- [Codespace dotfiles docs](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles)
- [VS Code dev container dotfiles](https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories)