# Running-audits skill template

Path: `skills/<prefix>-running-audits/SKILL.md`

The invoking agent's procedure for a self-review round, end to end. The
auditors review; this skill owns getting them run, turning what they return
into changes, and leaving a record the next round can pick up. Project-specific
unsafe-to-run lists and verification scripts go in a `running-audits-notes`
supplement, not here.

Description: "Run a self-review audit of your own changeset with the
`<prefix>-auditor-*` family, end to end: dispatching the general, running the
planned auditors, consolidating, closing with the generalist, dispositioning
and fixing, posting the verdict, and running the second round against the fix."

---

## Goal and cadence

One round by default. A second runs when the first returned a Blocking finding,
or when one of the three post-fix checks (step 9) could not be done.

## The round

1. **Dispatch.** Invoke `<prefix>-auditor-general` with the changeset. It
   returns a dispatch plan; it does not run auditors or write findings.
2. **Run every auditor on the plan** as a subagent, the whole round in one
   block. Capture the diff to a file once, against a fetched merge base, never
   a possibly stale local `main`
   (`git fetch origin --quiet && git diff "$(git merge-base origin/main HEAD)" > changeset.diff`
   to include uncommitted work; `origin/main...HEAD` once committed). Pass each
   auditor that file, its row's Paths and Why, and the severity-model skill's
   content. Run every row on the plan's round model: the base (fast / balanced,
   translated into a concrete override for the runtime) for every row, except
   the rows the plan escalates, which run on the strongest model. Escalate only
   the rows the plan names. Use the default subagent model for the whole round
   if the runtime can't override per dispatch. One subagent per row. On round 2, resume the same auditor if the
   runtime can address it (Claude Code `SendMessage`), else dispatch fresh.
3. **Run codified checks once, centrally**, before the auditors review: sweep
   the snapshot with every applicable codified/partial check via the owning
   plugin's grouped entrypoint (compatible linters in one analyzer run, not one
   process per rule). Early hook feedback doesn't replace this unless it proves
   coverage of the whole snapshot, inputs and rule set. Pass each relevant
   auditor the compact result: rule ID, check path/version, lifecycle point,
   target/snapshot and scope, pass / violation / not-applicable / error, coverage
   limits. A stale result, an error, or an unsupported runtime leaves that
   predicate open — the auditor reviews it by hand. A passing check narrows the
   manual look; it never waives the charter.
4. **Consolidate** into one severity-grouped verdict.
5. **Close with the generalist**, invoked directly (it is not on the plan),
   on the strongest model whatever the round's base is, given the changeset
   **and** the consolidated verdict. In round 1, also hand
   it any Plan/Spec review's recorded dispositions — nothing else re-reads
   them, so it is the only reader positioned to check that what the design
   round adopted landed.
6. **Post the verdict** as a PR comment (open a draft PR if none exists).
7. **Mark the boundary**: `git rev-parse HEAD`, or commit round 1's state.
8. **Disposition and fix.**
9. **Round 2?** A Blocking finding forces one. Otherwise, before stopping:
   1. **Break it.** Revert each fix and watch a spec fail; if none fails,
      write one that does.
   2. **Run it.** Run every check an auditor suggested but didn't run.
   3. **Keep the coverage.** If a fix edited an existing test, name the
      behaviour it used to exercise and confirm a test still does.

   Fix what these turn up. Run round 2 only for one you tried and could not do,
   and tell the general which; if the author asks for one, it runs. Round 2
   goes through the general, told explicitly it's round 2, with
   `<boundary-sha>..HEAD` and round 1's verdict read from the PR comment.
10. **Stop.** Two rounds is the cap.

Small follow-on route: for a ticket the project's working-an-issue skill
classes as a small follow-on, ask the general for one or two owning auditors and
omit step 5. If the actual diff exceeds that route's scope or risk limits, use
the normal plan.

## Auditors are read-only

No edits, no new files, anywhere in the worktree, from any auditor — say so
when dispatching. A probe left behind is an unreviewed change riding into a
commit, and a fix reverted mid-audit is a tree the next auditor reports as
your work. Read-only is also what makes a concurrent round safe: dispatched
together a round costs about its slowest auditor, one call at a time about the
sum.

The exception is a test suite that writes shared state (one test DB file, a
shared fixture). Dispatch those rows on their own; don't overlap them with your
own full-suite run or a background CI run, whose lock failures look like
regressions. The `running-audits-notes` supplement names what's unsafe here.

**The orchestrator is bound too.** From dispatch until the verdict is posted,
make no edits in the worktree the auditors read, including during the closing
pass. Auditors read the working tree, not a frozen diff; an edit mid-round
means each reviewed a different codebase, and red specs or a half-written
constant read like findings. Work that can't wait goes in a second worktree off
the same commit. A tool that rewrites a file and restores it (mutation checker,
reverting codemod) is an edit; never instruct an auditor to run one.

Don't pass an auditor an isolated worktree as the *review target*: pre-commit
work isn't in a worktree branched from `HEAD`. (A scratch worktree for a
destructive probe is different.)

### Auditors default to your cwd, not the review target

A subagent starts in the orchestrator's own worktree. When the target is a
different worktree, an auditor can silently read the wrong checkout and return a
confident "No findings" citing files that don't match the diff. In every
dispatch for a non-cwd target: name the target path as the **only** review
target; say its default cwd is a different checkout it must not read; require
`git -C <target> rev-parse --short HEAD` to match the expected SHA before
reviewing anything.

**Run every row the plan lists**, not a subset that looks worth it. The general
already trimmed to the auditors with a stake, and the rows that read as marginal
from inside the change are exactly the ones whose findings you won't reach on
your own. If the fan-out is disproportionate, ask for a leaner plan *before*
dispatching; narrowing what ships is the author's call, narrowing the review is
not.

## Establish a fact by the cheapest available means

Where a claim can be run, run it: a runner probe, a scope's `to_sql`, a
production-safe count, a grep for the caller you assumed exists. Most of all for
findings a fix will be built on: what a library returns or mutates, what a scope
selects, whether a caller exists, how large a population is. Put the probe
result in the finding, not just the conclusion.

## Not human-review feedback

Auditor findings are the standards enforcing themselves; feeding them back into
the standards as part of clearing a finding is a positive feedback loop. Don't
generalize a finding into a new rule while addressing it. A consistently wrong or
noisy auditor is narrowed or recalibrated as a separate curator action.

## Consolidate

- At the **second instance** of the same defect, search all related sites before
  proposing a fix; record the family and affected paths; prefer one fix at the
  owning boundary; file one family issue with a checklist if follow-on work is
  eligible, not a ticket per occurrence.
- Merge into one verdict, Blocking → Should-fix → Consider, deduplicated:
  narrower owner wins, functional beats style.
- **Opposite verdicts on one instance of a repeated pattern**, each backed by an
  individually correct fact: authority can't settle it. Grep the pattern's other
  instances (siblings in the same list, table, convention); what they do decides
  it. Don't defer to the auditor who sounds more authoritative, and don't split
  the difference.

## Fold in the closing pass

Treat its output in the same round. Buckets: **Findings** (merge like any
auditor's); **Design smells** (disposition on merits: cheap contained fixes now,
larger reshaping in the verdict's findings log under the filing policy); **Open
questions** (surface to the user; not findings); **Roster gap** (carry forward
for the curator; don't act on it in this round). An empty return is the expected
common case, not a reason to re-run.

## Disposition each finding

- **Blocking** — fix in this changeset before the PR goes up.
- **Should-fix** — fix now if cheap; otherwise record the deferral, optionally
  with a `TODO` linking the verdict or an eligible follow-on.
- **Consider** — fix, defer in the verdict, or accept with a one-line reason.

First separate defects this change introduced or worsened from incidental
pre-existing ones; record the latter as **Seen, not filed** with location (unless
independently Blocking). A `TODO` or deferred design smell may link to the
verdict comment instead of a new issue. The non-Blocking follow-on budget applies
across the whole PR, not per auditor or round.

Smallest change that resolves the finding. If it touches risky logic, add or
update a spec — never loosen an assertion to make one pass.

## Fix the code; don't narrate the fix

No source comments testifying that a change satisfied an auditor. The record of
what the round found and did lives in the PR comment.

## Verify the fix is in `HEAD` before you claim it

Before writing "fixed", re-read the cited lines in the tree as it now stands;
cheapest is grepping the expression the finding quoted — still present verbatim
means the fix didn't land. Don't apply a round's fixes as a batch of literal
replacements that can miss silently (a target that no longer matches does
nothing and reports nothing; a post-edit lint hook can reflow lines an earlier
fix just touched). Use an edit step where every replacement must match the file
the expected number of times and any miss aborts with nothing written. Then
re-verify against committed `HEAD`, since an uncommitted edit reads as fixed.

A finding you're about to disposition as moot or accepted gets its **check**
re-run, not its argument re-asserted: one grep or run, with what it showed
recorded. "Not examined" is not an allowed disposition for an in-scope finding.

## Post the round verdict

Include a fenced YAML decision: `round2_reason: null` when no second round runs,
or one of `blocking`, `break_it`, `run_it`, `keep_coverage`, `author_requested`
(the first applicable in that order). Carry it into the round-2 verdict and the
ticket's stats; don't infer rounds by searching prose.

One **PR comment** per round, never folded into the description (which
describes the change as it stands; the conversation carries the narrative):

```markdown
Round 2 — security, testing, reliability, closing pass.

```yaml
round2_reason: null
```

| Finding | Severity | Disposition |
|---|---|---|
| Example invariant broken (`app/models/example.rb:42`) | Blocking | Fixed in `abc1234` |
| Missing request spec on reconnect path | Should-fix | Deferred — #NNNN |
| Fifth branch wants a Strategy | Consider | Accepted; not yet a pattern |
```

Every finding gets a row, accepted ones included. Prose outside the table stays
short; a longer argument goes in a thread reply.

## Two rounds is the cap

Round 2 is final. Fix or consciously accept whatever it surfaces and stop.
