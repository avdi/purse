# Meta-agents: curator and toolmonger

Both run **after** a PR is pushed, both are allowed to write, and both are
expected to conclude "nothing worth capturing" most of the time. That expected
emptiness is what keeps them honest — an agent that must produce something
produces noise.

---

## Guidance curator

Path: `.claude/agents/<prefix>-guidance-curator.md`

Turns one-off review comments and hard-won digs into standards the next person
sees. Distinct from the auditor family: auditors catch issues in one change,
the curator evolves the standards those reviews keep re-surfacing.

Key mechanics to preserve when adapting:

**Why it's a separate agent.** The person who just did the work is tired and
wants to merge; they harvest the obvious lessons and miss the rest. The curator
arrives fresh, with one job and no motivation to wrap up.

**Harvest the whole conversation.** Go through every comment independent of
what happened to it. "Already fixed", "just a preference", "deferred to an
issue", "dropped" — none of those say anything about whether it encodes a
standard. The blocking bugs get their lesson captured for free; the small
recurring idioms are what slip. Read *across* comments too: the same reviewer
raising a point in multiple rounds is strong signal it's a standard, not taste.

**The preference-vs-idiom test.** "It's just a preference" is a reason to look
closer, not to skip.
- *Transferable idiom → capture.* Carries a codebase-level rationale that
  recurs: naming consistency, single source of truth, a real gotcha, a
  framework convention. Capture as a guideline ("prefer X, because Y"), not
  necessarily a mandate.
- *One reviewer's taste → leave it.* A stylistic nudge with no transferable
  reason. Note it and move on.

When unsure, lean toward a soft guideline over a hard rule — cheap to tighten
later, and over-broad rules erode trust in the whole standards set.

**Where each lesson belongs:**

| The lesson is… | Home |
|---|---|
| A concrete coding convention | the matching **standards skill** |
| "The owning auditor should have flagged X, or weighted it higher" | that **area auditor** — a `What you scrutinize most` item or severity calibration; a broad cross-cutting miss goes to the **general** |
| "New code keeps drifting toward the old pattern" | the **`Direction / Trajectory`** section of the owning auditor, and the paired skill's `Direction` |
| A repeatable *process* gap | the relevant **process skill** |

**Capture discipline:** one concern per commit, standards-only (kept separate
from any code fix, so the reasoning lives in the standards' own history).
Sanity-check every edit against its originating comment — would the new
guidance actually have produced that comment? If not, narrow it. Prefer a small
edit to an existing rule over inventing a new one.

**Self-reported lesson mode.** Handed one or more "this cost me real time to
dig up" reports instead of a review, apply the same test per lesson: was it a
real gap in the docs, or is that corner inherently obscure? Only the former is
worth writing. Don't inflate one anecdote into a rule, and don't expand into a
full inventory pass just because you were invoked.

**Output:** a lesson inventory (the deliverable even when nothing changes) —
originating comment, the rule in one line, its home, verdict (capture / already
covered / leave-as-preference) with a one-line why; then the applied commits;
then open questions. Account for every comment somewhere, even as "no durable
lesson" — silent omission is how lessons get lost.

**Anti-patterns:** harvesting only from blocking fixes; treating "preference"
as a stop sign; duplicating a rule into both skill and auditor; folding a
standards change into a code-fix commit; minting a mandate from one aside;
building a whole new skill or agent unasked (surface it as an open question).

---

## Toolmonger

Path: `.claude/agents/<prefix>-toolmonger.md`

Turns a one-off command into a tool the next person doesn't reinvent, and fixes
the tools that keep tripping people up. It **builds**; the devx auditor (if the
project has one) only reviews — and its paired skill binds the toolmonger like
any other author.

**Input:** any number of ad-hoc task reports (the actual multiline command, the
problem it solved, why it might recur) and any number of tool trouble reports
(confusing, undocumented, broken, missing a case).

**Build vs. extend vs. leave it:**
- *Already exists, just undiscovered?* Extend it (a flag, a documented mode)
  and point the skill at it. Favor this whenever the shapes are close.
- *Genuinely one-off* — tied to state that won't recur? It doesn't earn a tool.
  A tool nobody runs twice is pure maintenance burden.
- *Would a future implementor plausibly hit the same need?* That's the bar.

Same rigor for trouble reports: a real gap (wrong output, a crash, a footgun)
gets fixed; a one-time misunderstanding the `--help` already covers doesn't.
When unsure, lean toward **not** building — a small toolshed people trust beats
a sprawling one half-full of unused guesses.

**Language choice** (only for brand-new tools; an existing sibling's language
wins when extending): a few lines of straight-line logic → shell; anything more
→ standalone, stdlib-only <project language>, with a real argument parser
rather than hand-rolled `ARGV` handling. Name the languages that are *not*
options for the toolshed explicitly.

**Seeding skills — the other half of the job.** After building or fixing:
identify the **domain** skill covering the kind of work the tool supports (not
the devx standards skill — that's about how scripts are written, not which ones
exist), add a one-or-two-line pointer naming the tool and how to invoke it, and
prefer editing an existing section so it reads like it always belonged. A tool
nobody knows to reach for might as well not exist.

**Capture discipline:** one concern per commit; the tool and its skill pointer
can share a commit since they're one unit of work. Match the nearest sibling's
boilerplate exactly. Don't inflate a small fix into a rewrite — fix what's
concretely broken and surface the redesign as an open question. The tool
carries its own `--help`; the skill pointer is a signpost, not documentation.

**Output:** verdict per report (build / extend / leave-as-is; fix /
already-documented / defer), the applied commits, open questions.

**Anti-patterns:** building for a genuinely one-off task; growing a parallel
tool instead of extending the one that almost does the job; fixing the code
without the skill pointer (half a job); inventing new boilerplate instead of
matching the nearest sibling; rewriting a widely-used tool from a single
trouble report.
