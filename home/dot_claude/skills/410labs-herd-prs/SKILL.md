---
name: 410labs-herd-prs
description: >
  Upkeep pass over Avdi's "Avdi's Desk" 410Labs GitHub Project: board stats, column hygiene
  (including conflict resolution and moving stuck items), an org-wide orphan check for open
  PRs not tracked on the board at all, and a paste-ready "please review" list for whatever's
  genuinely ready for someone else to look at.
---

# 410Labs Herd PRs

Upkeep pass over Avdi's "Avdi's Desk" GitHub Project (org: 410Labs, project
#14): board stats, a paste-ready "please review" list, and active hygiene —
resolving merge conflicts, moving items to the column they actually belong
in, fixing assignees, and catching open PRs that never made it onto the board
at all — not just flagging problems and stopping.

Originally scoped as just a review-queue digest; broadened because a plain
PR-authorship search misses most of the board, and because flagging issues
without fixing the fixable ones just defers the work.

## Why not just search PRs

`gh`/GitHub search only finds PRs Avdi **authored**. Most of what's on his
desk isn't that:

- **Issue-tracked work.** A large fraction of board items are Issues with a
  PR linked via GitHub's Development panel (`closedByPullRequestsReferences`
  in GraphQL) — the issue is the board item, the PR is one hop away. A query
  that only unpacks the `PullRequest` GraphQL fragment gets an empty
  `content` for these and silently drops them.
- **Authorship is not the signal.** Avdi is not always the PR/issue author
  (Copilot-authored PRs, issues filed by teammates or Sentry that he's
  driving to a fix) and he isn't always even assigned, though he should be.
  Board membership (the item is in *his* project, in the column being
  worked) is the only reliable filter. Don't filter by author or assignee
  when deciding what's in scope; only use assignee absence to flag a hygiene
  gap.
- **A PR authored by someone else can legitimately sit on his board** — that
  means he owes *it* a review/attention, not the reverse. Keep this bucket
  separate from the "please review" list, which is for PRs where Avdi is the
  one waiting on someone else. Once he says he's taking responsibility for
  one, treat it exactly like his own for the rest of this workflow —
  including pushing a merge commit to resolve its conflicts — but confirm
  with him first if that hasn't been said explicitly; it's someone else's
  branch.

`scripts/herd_prs.rb` (read-only report) and `scripts/herd_prs_apply.rb`
(mutating actions) handle the mechanical parts of all of this.

## Orphan check: PRs not on the board at all

The rest of this skill is about PRs *on* the board. This check is the
opposite: does Avdi have an **open PR he authored that isn't tracked
anywhere on Avdi's Desk** — not as a direct item, not via a linked issue, in
any column? "Herd my PRs" without this misses exactly the PRs most likely to
be forgotten, since nothing on the board points at them.

This is the one place in this skill where filtering by **authorship** is
correct, not a shortcut to avoid — see *Why not just search PRs* above. The
main workflow can't use authorship because board membership is the filter for
"what's in scope"; here, authorship is exactly how you find what board
membership can't: things not on the board.

1. **List every open PR Avdi authored, org-wide:**
   ```
   gh search prs --owner 410Labs --author avdi --state open \
     --json repository,number,title,url,updatedAt,isDraft --limit 200
   ```
2. **For each one, ask GitHub directly whether it's tracked**, rather than
   crawling every column with `herd_prs.rb`:
   ```
   gh pr view <number> -R 410Labs/<repo> --json projectItems,closingIssuesReferences
   ```
   Empty `projectItems` means the PR itself isn't a board item. If
   `closingIssuesReferences` is non-empty, also check each linked issue —
   the *issue* may be the board item instead:
   ```
   gh issue view <issue-number> -R 410Labs/<repo> --json projectItems,state
   ```
   Watch the `title` field inside `projectItems` — it names which *project*
   the item is on. An issue can be tracked on a different org project
   entirely (e.g. "The Big Board") and still count as an orphan for Avdi's
   Desk purposes; being tracked *somewhere* isn't being tracked *here*.

   This is more reliable than a column crawl for two reasons: it answers
   "is this tracked" directly instead of requiring you to enumerate every
   status, and it doesn't depend on `herd_prs.rb --status Done` succeeding —
   that column has grown large enough to occasionally time out the GraphQL
   query (`HTTP 502`/`504`) rather than return, so a crawl can silently
   under-count exactly the column most likely to hide a false orphan.
3. **Confirmed orphans go on the board, never in Inbox/The Stack.** Avdi's
   rule: issues can sit in the early, not-yet-started columns (Inbox, The
   Stack) with no PR yet, but a PR represents work already in progress — by
   definition it is never placed earlier than **Working**. Place it there at
   minimum, and promote further only if the state actually warrants it:
   - `APPROVED`, no unresolved review threads, CI green, not draft → **Ready**
   - not draft, unreviewed or reviewed-clean, mergeable, not conflicting → **Review**
   - draft, conflicting, or genuinely still being worked → **Working**
4. **Add it** with `herd_prs_apply.rb add <owner/repo> <number> <StatusName>
   [--issue]` — `move` errors on anything not already on the board; `add`
   resolves the content's node id, puts it on project #14, and sets its
   status in one call. Safe to re-run: adding an item already on the board
   doesn't duplicate it.
5. **Confirm before bulk-adding.** This can span every repo in the org and
   turn up PRs open for months — some still wanted, some abandoned
   experiments. Separate "opened in the last week or two" (add without much
   thought) from "stale for weeks or longer" (list them and ask whether to
   add-and-triage or close, rather than deciding for Avdi).

This check is a full org-wide sweep and more expensive than the per-column
report — run it periodically, not necessarily every pass.

## Workflow

### 1. Run the report script

```
ruby .claude/skills/410labs-herd-prs/scripts/herd_prs.rb [--status Review]
```

Flags: `--org`, `--project`, `--status` (default `Review`), `--repo`
(default `mailstrom`; PRs in other repos come back in `other_repo_prs` for a
manual follow-up pass with `--repo <other>`).

Run it once per column that matters for this pass — at minimum `Review` (for
the please-review list) and `Working` (to catch items that have quietly
finished and should have moved on already — see step 3).

It prints one JSON object: board totals, issues with no linked PR, PRs in a
different repo, and per-PR `classification` — `fresh` / `re_review` /
`unaddressed_feedback` / `ready` / `ci_failing` / `conflicting` / `draft` —
plus the raw GraphQL detail (reviews, review-thread resolution, comments, CI
rollup, mergeable state, assignees) needed to reason about each one.

**Auth precondition the script checks for you:** the token needs the
`read:project` scope to read board status, and a separate `project` scope
(full read/write) to move items — `herd_prs_apply.rb move`/`assign` check for
that one instead. `GH_TOKEN`/`GITHUB_TOKEN` env vars, if set, silently
override `gh`'s own stored credential, and `gh auth refresh` flat-out refuses
to run while they're set. Both scripts detect a missing scope and print the
exact fix:

```
env -u GH_TOKEN -u GITHUB_TOKEN gh auth refresh -h github.com -s read:project
env -u GH_TOKEN -u GITHUB_TOKEN gh auth refresh -h github.com -s project
```

Each needs an interactive browser/device-code prompt — ask Avdi to run it
himself (`!`-prefixed). **If he mentions running it in his own terminal
separately** (not the code you gave him), that spawns a second, independent
device-code flow — don't wait on yours; check `gh auth status` for the
updated scope once he confirms his finished, and kill any `gh auth refresh`
process you started yourself so it doesn't sit there stuck polling for a
code nobody will authorize.

### 2. Classify each PR from the script's output

The script does the mechanical parts (auth, pagination, content-type
resolution, batched CI/review/thread/comment/mergeable fetch, and a
best-effort classification). Judgment calls stay manual:

- **`conflicting`** — real conflict with the base branch (`mergeable ==
  CONFLICTING`), independent of review state. See **Resolving conflicts**
  below. Always worth fixing — a PR with a real conflict can't merge no
  matter how ready its review is.
- **`ci_failing`** — this comes from GraphQL `statusCheckRollup`, which
  correctly aggregates **both** CircleCI commit-statuses (`ci/circleci:
  <job>`) **and** GitHub Actions check-runs (`rubocop`, `brakeman`,
  `eslint`, `haml-lint`, `erb_lint`, `stylelint`, `dependencies-audit`,
  `typescript-coverage`) into one combined state. **Trust it.** Do not
  "double-check" a red `ci_failing` against `gh api
  repos/<owner>/<repo>/commits/<sha>/status` (the legacy Statuses REST
  endpoint) — that endpoint only sees CircleCI's commit-status contexts and
  is blind to GitHub Actions check-runs entirely, so a real `rubocop`/lint
  failure reads as "success" there. Re-verifying this way once produced a
  false all-clear that put a lint-failing PR on the please-review list. If
  you need a human-readable second look, use `gh pr checks <number> --repo
  <owner>/<repo>` — it lists every context from both systems.
  - **A failing lint/static-analysis check-run (rubocop, brakeman, eslint,
    etc.) is real, not flaky** — these are deterministic, not subject to
    Selenium/external-service timing. Pull the specific offense via `gh api
    repos/<owner>/<repo>/check-runs/<job-id>/annotations` (job ID from `gh
    pr checks`'s URL, or `gh run view <run-id> --job <job-id>
    --log-failed`) — the plain job log often omits the file/line, the
    annotations endpoint always has it.
  Failure-log patterns seen so far, once you're looking at a real
  `ci_failing`:
  - **Known flaky Selenium** — `slow_initial_load_spec.rb`, `Tab list
    missing`, spurious `settings.json` 500s.
  - **Flaky external-service specs** — e.g. an IMAP-daemon spec against a
    real test IMAP server (`client_connection_spec.rb`, `greeting` nil) that
    has nothing to do with the PR's diff. Same shape as the Selenium case:
    unrelated to the changed files, a real external dependency in the loop.
  - **Same failure across multiple unrelated PRs, `finish_line`/rake-boot
    crash** (`app_config.rb`, `mailstrom_hostname.match?` nil) — looked at
    first like plain staleness (merging `main` into one PR made it vanish),
    but it later **recurred on that same already-merged commit on a plain
    re-run**. So it isn't purely "behind main" — more likely an intermittent
    Vault/secrets-lookup flake in CI (same shape as the Selenium/IMAP
    flakiness: unrelated to the diff, an external dependency in the loop).
    Still worth trying `herd_prs_apply.rb sync-branch` first if the PR is
    genuinely behind (cheap, sometimes sufficient), but don't be surprised
    if it comes back — a plain re-run is the real fix, same as the other
    flaky patterns.
  - **Real, PR-specific failure** — the failing spec directly exercises
    logic the PR itself added/changed (e.g. `prune_app_accesses_job_spec.rb`
    failing on the exact job the PR implements). Don't attempt a code fix
    yourself unless asked — that's real engineering judgment on behavior you
    didn't design. Move it (see step 3) and comment with the specific
    failure so whoever picks it up doesn't have to re-derive it.
  - For flaky patterns: offer a re-run (`circleci-mcp-server:rerun_workflow`,
    `fromFailed: true`), don't trigger without confirmation. Re-check status
    afterward — don't assume the re-run passed.
- **`re_review`** — reviewed, then a newer commit landed after the last
  review activity. Note whether it was `CHANGES_REQUESTED` (stronger signal)
  vs plain comments.
- **`unaddressed_feedback`** — review activity (a `CHANGES_REQUESTED`, or any
  unresolved review-comment thread) with nothing from Avdi after it. This is
  his turn, not a reviewer's. He does address non-blocking notes, not just
  formal change requests — an `APPROVED` review with unresolved threads
  still counts as unaddressed, not ready.
- **`ready`** — `APPROVED`, zero unresolved review-comment threads, CI green,
  not draft. This is a *stronger* state than `fresh`: someone already looked
  and had nothing outstanding. Belongs in the **Ready** column, not Review —
  see step 3.
- **`fresh`** — never reviewed, CI green. Ready to post to the please-review
  list as-is.
- Significance (`significant` vs `routine`) is still a judgment call from
  diff size/files/risk — the script doesn't attempt it. Err toward
  `significant` if unsure, especially anything touching what gets deleted,
  who gets charged, or who gets emailed.
- **Title drift** and **agent-guidance-only diffs** (`CLAUDE.md`,
  `.claude/**`, skill files) still need a manual look at the PR body/files —
  rare enough not to be worth scripting.
- `has_qa_report` / `has_audit_verdict_comment` are cheap string-match
  heuristics over the last 20 comments (looking for a `"QA report"` heading,
  or an audit-verdict-shaped comment). They're signals for step 3's
  Verification check, not proof — skim the actual comments before acting on
  them.

### 3. Column hygiene — fix what's fixable, not just flag it

Every item's *actual* state (from step 2) can disagree with the column it's
sitting in. Correct it:

| Actual state | Belongs in | Action |
|---|---|---|
| `conflicting` | (unchanged) | Resolve the conflict first — see below — then re-classify |
| `ci_failing`, confirmed real (not flaky, not fixed by a sync) | **Working** | `herd_prs_apply.rb move`, then `comment` explaining the specific failure (see step 2) |
| `ready` (approved, no unresolved threads) | **Ready** | `herd_prs_apply.rb move` |
| `unaddressed_feedback` sitting in **Working** | **Working** (correct already) | leave it |
| `unaddressed_feedback` sitting in **Review** | **Working** | `herd_prs_apply.rb move` — it's not actually ready for a fresh reviewer |
| In **Working**, looks worked-on and local audits addressed (`has_audit_verdict_comment`), but no QA report yet (`!has_qa_report`) | **Verification** | `herd_prs_apply.rb move` — confirm by reading the comments first, this is a heuristic |
| `re_review` or `fresh`, CI green, no conflict | **Review** | already correct if it's there; move it there if it was sitting in Working |

Run the report against **Working** as well as **Review** — that's the only
way to catch an item that quietly became `ready` or reached Verification
criteria without anyone moving it.

Also flag, without necessarily moving:

- **Issues with no linked PR** (`issues_without_pr`) — nothing to review
  yet. Default destination: **The Stack**.
- **PRs authored by someone else** sitting on the board — Avdi owes *them*
  review/attention; keep out of the please-review list. If he's explicitly
  claimed responsibility, treat identically to his own PRs for every step
  including conflict resolution — but confirm before pushing to someone
  else's branch if he hasn't said so already.
- **Missing-assignee gap** — if Avdi isn't in an item's `assignees`, flag it
  and offer `herd_prs_apply.rb assign <owner/repo> <number> avdi`. He should
  be assigned to everything on his own desk even when he didn't author it.

Always confirm before moving/commenting/assigning at scale; individual small
fixes (an assignee gap, a clear miscategorization) are fine to just do and
report, per how literally he's asked in the moment.

### Resolving conflicts

For every `conflicting` PR:

1. Try the cheap path first: `herd_prs_apply.rb sync-branch <owner/repo>
   <number>`. This calls GitHub's "Update branch" API — merges base into
   head server-side, no local checkout. It only succeeds when there's no
   real content conflict (i.e., the PR was just behind, not diverged) — so
   try it even for a PR whose `mergeable` reads `MERGEABLE`-but-stale, since
   that alone can fix certain CI failures (see the `finish_line` case in
   step 2) with no manual work at all.
2. If that 422s ("merge conflict between base and head"), it's a real
   conflict — resolve it by hand in a worktree:
   - `wt list` to find the PR branch's existing worktree (this repo tends to
     already have one per open PR), or create one.
   - `EnterWorktree(path: ...)`, `git fetch origin main`, `git merge
     origin/main --no-edit`.
   - **Read both sides before resolving — don't blind-pick "ours" or
     "theirs".** Agent-guidance/doc conflicts are usually two independent
     additions in the same spot; keep both, in whatever order reads best.
     Application-code conflicts (especially anything touching data
     mutation/deletion) need real understanding of *why* each side changed —
     `git log -S<distinctive string> origin/main -- <file>` to find the
     commit that introduced the other side's change, read its message, and
     preserve both sides' intent rather than mechanically picking one.
   - Run whatever verification is available (rubocop/lint, syntax check,
     relevant specs) before committing. If full spec verification isn't
     reachable (e.g. Vault/sidecar services not up in the current shell),
     say so plainly rather than claiming a false-confidence pass.
   - `git add`, `git commit --no-edit` (keeps the default merge message),
     `git push`.
   - `ExitWorktree(action: "keep")` when done with that worktree.

### 4. Order the "please review" list

1. `re_review` (oldest `updatedAt` first — fastest to unblock)
2. `significant`, `fresh`
3. `routine`, `fresh`

Skip the age note for anything under ~a week old; state age in days
otherwise (never say "stale"). Say **"feedback addressed"**, not "changes
addressed" — feedback isn't always a formal change request.

### 5. Report

One combined report at the end, in this exact order — concise, not a wall of
text. **Every item is self-contained**: a reader must not have to look up
another section to know which PR a bullet is about. Never write "the N
in-flight reruns" or similar — name each one.

```
Stats: <column> N items (N direct PR, N issue-linked, N no-PR) — was M at pass start (±D)
  <column2>: +A moved in / -B moved out
  <column3>: +A moved in / -B moved out

Actions:
- <verb> mailstrom#<n> — <what, terse>
- <verb> mailstrom#<n> — <what, terse>

Orphan check (omit if not run this pass):
- N found, N added (N Working, N Review, N Ready), N flagged stale for a triage decision

Please review:
- [mailstrom#123](url) — Fix IMAP reconnect backoff (re-review, feedback addressed, 9d)
- [mailstrom#124](url) — ...

Still needs you:
- mailstrom#<n> — <specific, actionable ask>
- mailstrom#<n> — <specific, actionable ask>
```

- **Stats**: report the queried column's before/after count and net change,
  plus every *other* column anything moved into or out of this pass — not
  just the queried one. This is what first exposed the original undercount
  bug (a hand count of Review showed 19; the flawed query surfaced 4), so
  don't drop it to a vague "did some cleanup."
- **Actions**: one line per mutation actually *performed* (not just
  flagged) — conflict resolved & pushed, column moved, assignee added, CI
  re-run triggered. Terse — verb, PR, what — not a paragraph.
- **Orphan check**: only when that sweep ran this pass (see *Orphan check*
  above) — omit the section entirely otherwise. One line with the counts;
  name the stale ones under **Still needs you**, not here.
- **Please review**: the formatted list (see Output format below),
  ready to paste as-is.
- **Still needs you**: goes *last* — everything that couldn't be
  auto-resolved and needs Avdi's call, each its own bullet naming the PR and
  the specific ask (a pending CI rerun to recheck, a destination column that
  was ambiguous, a real failure on someone else's PR, a conflict resolution
  that touched risky logic and deserves a second look). If nothing's
  pending, omit the section rather than writing "none."

## Output format

**When the report's destination is the terminal itself** (the reply Avdi
reads in Claude Code, not something copied elsewhere), Markdown link syntax
`[text](url)` shows up as literal brackets — the terminal doesn't render it.
Use a bare URL on its own line under each item instead, so it's actually
clickable. The Markdown-link guidance below is for the *paste-ready* list —
somewhere with real Markdown rendering (Slack, GitHub, a PR comment) — not
for what's printed directly in the response.

**Please-review list** — standard Markdown links, **not** Slack's
`<url|text>` mrkdwn syntax — that syntax reliably breaks when copied through
this pipeline (angle brackets render as literal text outside real HTML, and
the `|` gets percent-encoded into the URL, producing a dead link). Link only
the `owner#12345` ticket-ID part, not the title — the title stays plain text
after it. One line per PR:

```
- [mailstrom#123](https://github.com/410Labs/mailstrom/pull/123) — Fix IMAP reconnect backoff (re-review, feedback addressed, 9d)
- [chuck#45](https://github.com/410Labs/chuck/pull/45) — Rework auth token refresh (significant, 14d)
- [chuck-backend#12](https://github.com/410Labs/chuck-backend/pull/12) — Add rate limit headers (routine)
```

Keep titles short (truncate if long), status note to 2–4 words.

## Notes

- Repos in scope: all repos in the 410Labs GitHub org, not just mailstrom —
  but the script currently CI/review-checks only `--repo` (default
  `mailstrom`); PRs it finds in other repos land in `other_repo_prs` for a
  manual follow-up pass.
- If the project's Status field uses different label text (e.g. renamed),
  pass `--status` or ask Avdi to confirm rather than guessing. The full
  option set as of this writing: Inbox, The Stack, Working, Verification,
  Review, Ready, Circle Back, Done, Rejected (see `HerdPrs::STATUS_OPTIONS`
  in `herd_prs_lib.rb`, which both scripts share).
- A failure repeating identically across *unrelated* PRs, gone after
  syncing with `main`, is environmental/staleness — not worth a "flaky,
  offer re-run" flag once `sync-branch` has already fixed it.
