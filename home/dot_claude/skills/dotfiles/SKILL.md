---
name: dotfiles
description: >
  Manage Avdi's dotfiles using chezmoi and the purse repo. Use when working
  with files under ~/, adding config to dotfiles, editing the system prompt,
  or adding agent skills. Also use when a problem in some *other* project
  turns out to live in a shell script, shim, tool config, or agent instruction
  file under ~/ — "fix this for my environment" means fix it here too.
---

## Overview

Dotfiles are managed with [chezmoi](https://chezmoi.io) in a repo called **purse**:

- **GitHub**: `https://github.com/avdi/purse`
- **Chezmoi source**: `~/.local/share/chezmoi/` — use `chezmoi cd` to open a shell there

Chezmoi's `sourceDir` is set to the `home/` subdirectory of the purse repo.

## Always finish the change: apply, commit, push

Edit the **source**, then run all three, in the same sitting:

```bash
chezmoi apply <path>   # deploy to this machine
chezmoi cd
git add -A && git commit -m "..." && git push
```

None of this needs authorization. Do not stop to ask, do not offer and wait for
a yes, do not leave the source tree dirty. Pushing to `origin` is routine here —
the repo is public, but its audience is Avdi's other machines.

`chezmoi apply` fixes the machine you are sitting at. **The push is what fixes
the others.** An unpushed commit leaves the other PC, the Mac, tomorrow's
Codespace, and the next devcontainer that installs these dotfiles still broken,
with nothing to remind anyone.

This applies most of all when you arrive from another project. Hitting an
environment problem elsewhere and tracing it back to a file here is the common
case: it is a normal detour, not a scope expansion to check in about. Finish it
the way you would if you had started here, then go back to what you were doing.

## Source-to-home mapping conventions

| Source pattern | Home result |
|---|---|
| `dot_foo` | `~/.foo` |
| `dot_foo.tmpl` | `~/.foo` (Go `text/template` processed) |
| `run_once_*.sh` | Runs once on first `chezmoi apply` |
| `run_onchange_*.sh` | Re-runs whenever the script content changes |

## Source structure

```
home/
  dot_config/
    ai/
      system-prompt.md   # Shared LLM system prompt (source of truth)
    shell/
      aliases.sh
      env.sh
  dot_claude/
    symlink_CLAUDE.md.tmpl  # ~/.claude/CLAUDE.md → ~/.config/ai/system-prompt.md
    skills/              # Agent skills (read by Claude Code + Augment)
      dotfiles/
        SKILL.md
  dot_copilot/
    symlink_copilot-instructions.md.tmpl  # ~/.copilot/copilot-instructions.md → shared prompt
  dot_gemini/
    symlink_GEMINI.md.tmpl  # ~/.gemini/GEMINI.md → ~/.config/ai/system-prompt.md
  dot_augment/
    rules/
      symlink_global.md.tmpl  # ~/.augment/rules/global.md → ~/.config/ai/system-prompt.md
  dot_config/git/config.tmpl  # ~/.config/git/config (managed git config; ~/.gitconfig is an unmanaged stub)
  AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/
    settings.json             # Windows Terminal config (Windows only)
```

## Common workflows

### Add or edit a dotfile

```bash
# Edit directly in the chezmoi source
chezmoi cd   # opens a shell in ~/.local/share/chezmoi/home/
# ... make changes ...
chezmoi apply

# Or pull an existing file from ~ into the source
chezmoi add ~/.config/foo
```

### Edit the shared LLM system prompt

Edit `home/dot_config/ai/system-prompt.md` — that file is the source of truth.
`~/.claude/CLAUDE.md`, `~/.copilot/copilot-instructions.md`,
`~/.gemini/GEMINI.md`, and `~/.augment/rules/global.md` are all symlinks to
`~/.config/ai/system-prompt.md`.

After editing, run `chezmoi re-add ~/.config/ai/system-prompt.md` if you edited
the deployed copy directly.

### Windows Terminal settings

Managed in place at its real path — **not** via a symlink, and **not** a `.tmpl`
(so `chezmoi re-add` round-trips cleanly). Windows Terminal owns the file and
rewrites it on every UI settings change, so pull changes back explicitly:

```powershell
chezmoi diff      # shows what the Terminal UI changed
chezmoi re-add "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
```

`.chezmoiignore` skips the `AppData` tree on non-Windows. `.gitattributes` pins the
file to `eol=lf` so `core.autocrlf` doesn't fake a full-file diff.

Superseded the old `avdi/dotfiles` repo, which symlinked this path — Windows Terminal
replaced the symlink with a plain file and the config silently fell out of VCS.

### Add an agent skill

```bash
chezmoi cd
mkdir -p home/dot_claude/skills/<skill-name>
# create home/dot_claude/skills/<skill-name>/SKILL.md
chezmoi apply
```

Claude Code picks up skills from `~/.claude/skills/`; Augment reads that
location too (compatible per the agentskills.io standard).

## Essential chezmoi commands

```bash
chezmoi apply              # Deploy source → home
chezmoi apply --dry-run    # Preview without changes
chezmoi diff               # Show what would change
chezmoi add <path>         # Pull a ~ file into source
chezmoi re-add <path>      # Re-sync a managed file back to source
chezmoi cd                 # Open shell in chezmoi source dir
```
