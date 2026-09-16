---
name: worktree
description: Rules for working with git worktrees in Claude Code — entering/re-rooting a session, the wt commands that are safe to shell out to, and recovering a worktree whose provisioning hooks failed partway. Load this BEFORE any worktree operation: creating, entering, resuming, listing, removing, or troubleshooting one.
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

## Recovering a worktree whose pre-start hooks failed

`git worktree add` runs before `wt`'s pre-start hooks, so a hook failure
leaves the worktree on disk but half-provisioned — missing whatever the
hooks generate (in a project with per-worktree isolation, that means it
silently shares the primary checkout's databases and ports).

Through the Claude Code plugin this surfaces as `EnterWorktree(name: ...)`
failing with *"hook succeeded but returned no worktree path"* — a misleading
message: the plugin's `WorktreeCreate` hook pipes `wt switch --create
--format=json` into `jq` without `pipefail`, so `wt`'s real exit code and
stderr are swallowed (upstream Worktrunk bug).

**Do not retry with `wt switch <branch> --no-cd`.** From inside the worktree
that command names — exactly where you are when you notice the problem — `wt
switch` short-circuits to `Already on worktree for <branch>` and skips the
pre-start pipeline entirely. It exits 0, so the failure is silent: nothing
gets provisioned and nothing says so.

Re-run the hooks directly instead:

```bash
wt hook pre-start    # runs the pre-start pipeline unconditionally, against
                     # this worktree's own branch and cwd; its stderr shows
                     # the real failure. Idempotent — safe to re-run.
```

Fix what it reports, re-run until it succeeds, confirm the generated files
exist, then `EnterWorktree(path: ...)`.

Do not `EnterWorktree(path: ...)` into a half-provisioned worktree and carry
on — that is how you end up writing to the wrong database.
