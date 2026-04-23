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
- **Chezmoi source**: `/home/avdi/.local/share/chezmoi/` (the chezmoi clone)
- **Working copy**: `/home/avdi/projects/avdi/purse/` (for editing)

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
    CLAUDE.md            # Symlink → ~/.config/ai/system-prompt.md
    skills/              # Agent skills (read by Claude Code + Augment)
      dotfiles/
        SKILL.md
  dot_gitconfig.tmpl     # ~/.gitconfig (templated)
  run_onchange_setup-ai-symlinks.sh  # Wires LLM tool symlinks
```

## Common workflows

### Add or edit a dotfile

```bash
# Option A: edit in working copy, then sync to chezmoi clone
cp home/dot_config/foo ~/.local/share/chezmoi/home/dot_config/foo
chezmoi apply

# Option B: pull an existing file from ~ into chezmoi source
chezmoi add ~/.config/foo
```

### Edit the shared LLM system prompt

Edit `home/dot_config/ai/system-prompt.md` — that file is the source of truth.
`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, and `~/.augment/rules/global.md`
are all symlinks to `~/.config/ai/system-prompt.md`.

After editing, run `chezmoi re-add ~/.config/ai/system-prompt.md` if you edited
the deployed copy directly.

### Add an agent skill

Create `home/dot_claude/skills/<skill-name>/SKILL.md` in the working copy,
then copy to the chezmoi source clone and run `chezmoi apply`.

Claude Code picks up skills from `~/.claude/skills/`; Augment reads that
location too (compatible per the agentskills.io standard).

### Sync the two repo clones

```bash
# After editing in working copy: push to GitHub, pull in chezmoi clone
git -C ~/projects/avdi/purse push
git -C ~/.local/share/chezmoi pull
chezmoi apply
```

## Essential chezmoi commands

```bash
chezmoi apply              # Deploy source → home
chezmoi apply --dry-run    # Preview without changes
chezmoi diff               # Show what would change
chezmoi add <path>         # Pull a ~ file into source
chezmoi re-add <path>      # Re-sync a managed file back to source
chezmoi cd                 # Open shell in chezmoi source dir
```
