---
name: worktree
description: Rules for working with git worktrees in Claude Code — entering/re-rooting a session, the wt commands that are safe to shell out to, and recovering a worktree whose provisioning hooks failed partway. Also: where worktrees must live on a multi-session night (outside any checkout another session could sweep with `git add -A`). Load this BEFORE any worktree operation: creating, entering, resuming, listing, removing, or troubleshooting one — or whenever more than one session may run concurrently in one checkout.
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

## Multi-session nights: worktrees go outside the shared checkout

When a second session may run concurrently in one checkout (a multi-session
night of parallel packets), each session takes its own worktree **before
writing anything**. Placement is the mechanism, not etiquette: uncommitted
work in a shared tree is exactly what another session's `git add -A` sweeps
into its own commit (this happened twice in shibizops on 2026-11-03/04 — see
`operations/agent-system.md#how-to-work` there). A worktree outside the shared
checkout's tree cannot be reached by a sibling session's `git add -A` at all.

Verified placement per tool:

- **OpenCode `worktree_create`** — `~/.local/share/opencode/worktree/<project>/<name>`.
  Outside the checkout already; leave it there, never in-tree.
- **Worktrunk (`wt switch --create`)** — default `worktree-path` template puts
  the worktree in a **sibling** of the repo (`../<repo>.<branch>`). Outside
  already. Never point a project's `worktree-path` template inside the
  repository (e.g. the `{{ repo_path }}/.worktrees/…` variant).
- **Claude Code (`EnterWorktree` / `claude -w`)** — defaults to
  `.claude/worktrees/<name>/` **inside** the checkout. In repos that gitignore
  that path (Claude Code's own docs recommend it) a sibling sweep still cannot
  reach the worktree; when offered a choice of path, prefer one outside the
  checkout — Claude Code asks approval for paths outside `.claude/worktrees/`,
  and that prompt is the safe answer, not a blocker.

After taking the worktree, do not commit in the shared checkout while another
session is live in it, and keep staging explicit paths — `git add -A` inside
your own worktree only risks your own work, which is the point.

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
