---
name: worktree
description: Rules for working with git worktrees in Claude Code.
---

# Git Worktrees

To switch into or re-root a session inside a worktree, ALWAYS use the
`EnterWorktree` tool. Never use `wt switch` or `git worktree` shell commands
to navigate between worktrees — they change the shell cwd but don't re-root
the Claude Code session.

`wt` commands are still appropriate for non-navigation operations:
- `wt switch --create <branch> --no-cd --format=json` — create a worktree
- `wt list` — list worktrees
- `wt remove` / `wt merge` — clean up or merge

For the full create-then-enter workflow, use the `/wt-switch-create` command.
