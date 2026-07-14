---
name: dotfiles
description: >
  Manage Avdi's dotfiles using chezmoi and the purse repo. Use when working
  with files under ~/, adding config to dotfiles, editing the system prompt,
  or adding agent skills.
---

## Overview

Dotfiles are managed with [chezmoi](https://chezmoi.io) in a repo called **purse**:

- **GitHub**: `https://github.com/avdi/purse`
- **Chezmoi source**: `~/.local/share/chezmoi/` — use `chezmoi cd` to open a shell there

Chezmoi's `sourceDir` is set to the `home/` subdirectory of the purse repo.

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
  dot_gemini/
    symlink_GEMINI.md.tmpl  # ~/.gemini/GEMINI.md → ~/.config/ai/system-prompt.md
  dot_augment/
    rules/
      symlink_global.md.tmpl  # ~/.augment/rules/global.md → ~/.config/ai/system-prompt.md
  dot_config/git/config.tmpl  # ~/.config/git/config (managed git config; ~/.gitconfig is an unmanaged stub)
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
`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, and `~/.augment/rules/global.md`
are all symlinks to `~/.config/ai/system-prompt.md`.

After editing, run `chezmoi re-add ~/.config/ai/system-prompt.md` if you edited
the deployed copy directly.

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
