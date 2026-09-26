# Evaluating an auditor fleet

How to measure whether a fleet's dispatch shape — which models, how many
sessions, what effort — earns its cost, and what the first such measurement
found. The worked example, with every script and every run's transcript, is
`docs/auditor-fleet-eval/` in 410Labs/agent-infra.

## What we know (measured 2026-09)

Four real, already-graded PR audits from two production Rails codebases (one
of them a clean case), 11 dispatch arms, 3 replicates each, one fixed judge:

| Arm | Weighted recall | Blocking recall | $/round |
|---|---|---|---|
| Every auditor on the strongest model | 0.68 | 1.0 | 4.50 |
| Every auditor on the balanced model | 0.50 | 1.0 | 0.28 |
| Per-auditor tiers (strongest / balanced / small by stakes) | 0.43 | 1.0 | 1.26 |
| One session holding every charter, balanced model | 0.41 | 1.0 | 0.20 |
| One session holding every charter, strongest model | 0.42 | 0.92 | 2.03 |
| Every auditor on the small model | 0.25 | **0.40** | 1.33 |

What that means for a fleet:

- **One model per round, and it's the balanced one.** Per-auditor tiering
  loses to a flat balanced round on recall *and* cost. The small-model slots
  are the recall drag, and a small model explores in long many-turn sessions,
  so it isn't even cheaper.
- **Never the small model.** It missed Blocking findings and repeatedly failed
  to return findings in the required structured shape at all.
- **Escalate the whole round to the strongest model** when a Blocking miss
  would be an incident — +18 points of recall at ~16× cost.
- **One session per auditor.** Folding charters into one session lost
  recall at every model size. Grouping into 3 affinity clusters matched
  fanout recall with less noise at ~1.7× cost — a reasonable alternative if
  noise is the complaint, not a default.
- **Reasoning effort** (low/medium/high) moved nothing worth its price.
- **Every arm flags 2–9 unmatched findings on a 5-line clean change.** Noise
  is endemic to the family, not a property of any one shape.

Not yet measured: round 2 (resuming round-1 auditors vs fresh dispatch),
consolidation loss, and whether any of this holds on a runtime other than
Claude Code.

## Running your own

1. **Corpus from graded audits, not invented bugs.** A case is a merged PR
   whose round-1 verdict comment is the ground truth: the diff exactly as it
   stood *before* any audit-driven fix (`base..pre_audit_sha`), plus the
   verdict's findings table transcribed with original severities and
   out-of-scope dispositions. Include a **clean case** (round 1 found nothing
   real) — without one, an arm that hallucinates plausible noise is
   invisible — and at least two Blocking-bearing cases, since a hard floor on
   one case is thin.
2. **Freeze the roster per case** to the production dispatch plan, so the
   only thing varying between arms is the thing under test.
3. **One fixed judge model for every arm**, deciding per ground-truth row
   `caught` (substantive match, not wording) and `severity_correct`, plus a
   noise count. Weighted recall = (3·Blocking + 1·Should-fix + 0.3·Consider)
   caught over the same weights total.
4. **≥3 replicates per (arm, case).** Treat gaps under ~5 points as noise.
5. **Decision rule:** discard any arm under 90% Blocking recall; take the
   cost/recall Pareto frontier of the rest; name the frontier points as the
   default and its alternatives, and retire everything off it.

## Harness traps (each silently zeroed or skewed every arm once)

- **Auditors need their charters loaded exactly as production does.** Run
  headless (`claude -p`) with `--plugin-dir` pointing at the fleet's plugin
  directories, so the auditors resolve by plugin-qualified name
  (`baseline:<prefix>-auditor-ruby`) regardless of what the calling session
  has installed.
- **`--agent` + `--json-schema` returns nothing.** An agent's `tools:` list
  shuts out the `StructuredOutput` tool that `--json-schema` answers through;
  every auditor writes real findings in prose and reports an empty list.
  Re-register each charter via `--agents` with `StructuredOutput` appended to
  its tools.
- **The operator's user settings leak in.** Output style and global
  CLAUDE.md load into every auditor and judge session. Use
  `--setting-sources local` (the product repo's own CLAUDE.md/AGENTS.md
  still load, as in production).
- **Snapshot the repo at `pre_audit_sha`** (`git archive | tar -x`) and run
  each auditor rooted there, so it reads surrounding code as it stood.
- **Cost in dollars, not tokens.** Tokens across mixed models compare
  nothing; the envelope's `total_cost_usd` already folds in per-model price
  and cache hits.
- **Parse ground-truth tables by column header** and split only on unescaped
  pipes — a `\|` inside a finding's prose will otherwise shift the severity
  cell.
- **Make the sweep resumable** (skip runs that already have a score file):
  usage limits and CLI auto-updates will kill runs mid-sweep.
