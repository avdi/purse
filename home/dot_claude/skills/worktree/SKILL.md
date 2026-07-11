---
name: worktree
description: Rules for working with git worktrees in Claude Code.
---

# Git Worktrees

ALWAYS use the `EnterWorktree` tool to switch into or create a git worktree.
Never shell out to `wt` or `git worktree` commands for this purpose.
