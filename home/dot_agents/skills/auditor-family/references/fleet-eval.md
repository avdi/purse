# Evaluating an auditor fleet

How to measure whether a fleet's dispatch shape — which models, how many
sessions, what effort — earns its cost, and what the first such measurement
found. The worked example, with every script and every run's transcript, is
`docs/auditor-fleet-eval/` in 410Labs/agent-infra.

## What we know (measured 2026-09, extended 2026-10-12)

Five real, already-graded PR audits from two production Rails codebases (one a
clean case, one hard-Blocking case), 3 replicates per (arm, case), one fixed
judge (`claude-opus-5`). Tiers and arms, September run (four cases):

| Arm | Weighted recall | Blocking recall | $/round | Critical path |
|---|---|---|---|---|
| One auditor per session, all strongest | 0.68 | 1.0 | 4.50 | 276s |
| One auditor per session, all balanced | 0.50 | 1.0 | 0.28 | 13s |
| Three affinity clusters, balanced | 0.50 | 1.0 | 0.47 | 20s |
| Per-auditor tiers (strongest / balanced / small by stakes) | 0.43 | 1.0 | 1.26 | 188s |
| One session holding every charter, balanced | 0.41 | 1.0 | 0.20 | 20s |
| One session holding every charter, strongest | 0.42 | 0.92 | 2.03 | 307s |
| All on the *previous-generation* small model (Haiku 4.5) | 0.25 | **0.40** | 1.33 | 232s |

October addendum (five cases, 11265 added; the 11265 out-of-scope correction
applied):

| Arm | Weighted recall | Blocking recall | $/round | Critical path |
|---|---|---|---|---|
| All on the **current-generation** small model (Haiku 5.5) | 0.62 | 1.0 | 0.04 | 38s |
| All balanced (Sonnet) | 0.50 | 1.0 | 0.72 | 72s |
| Three lanes by affinity (code / boundary / view), balanced | 0.33 | 0.78 | 1.04 | 150s |
| Haiku 5.5, charter in the *prompt* instead of the agent definition | 0.55 | 1.0 | 0.10 | 53s |

What that means for a fleet:

- **One model per round; default to the current-generation small one.** A flat
  Haiku 5.5 round matched or beat a flat balanced round on recall and cleared
  the Blocking floor at a small fraction of the cost. A new small generation
  can differ wildly from the last (Blocking 0.40 → 1.0), so "small model" is
  not a fixed verdict; re-measure on each generation. `balanced` is the
  fallback when the small model isn't current-generation or you can't tell.
- **Never an old-generation small model.** It missed Blocking findings and
  repeatedly failed to return findings in the required structured shape.
- **Per-auditor tiering loses** to a flat round on recall *and* cost; the small
  slots of the old scheme were the recall drag.
- **Escalate the whole round to the strongest model** when a Blocking miss
  would be an incident — about +18 points of recall at ~16× the cost. Extra
  depth (16 turns vs 2) is most of that gap.
- **One session per auditor.** Single-session monoliths lost recall at every
  model size; affinity clusters/lanes matched or lost to fan-out and cost more.
  Fan-out at the balanced model is ~13–70s of critical path, so a round is
  not where a ticket's wall clock goes.
- **Charter as the agent definition, not as prompt text.** Prompt delivery
  lowered recall and cost more (4× cache-creation tokens). Confounded by
  system-prompt size, n=10 — don't expect a win from it.
- **Reasoning effort** (low/medium/high) moved nothing worth its price.
- **The small model's extra "noise" is mostly taste and process notes**, not
  false claims: an Opus adjudication put false claims at about the same rate
  per round as the balanced model's (≈4 of ~27 vs ~14 raw findings). Expect to
  discard style notes; the consolidating reader is usually a stronger model.
  Dropping them was not itself measured.
- **Every arm flags 2–9 unmatched findings on a 5-line clean change.** Noise
  is endemic to the family, not a property of any one shape; the judge counts
  real-but-uncatalogued findings as noise, so `noise_count` overstates false
  findings and ground truth undercounts real ones.
- **A single hard Blocking case (11265) can decide the 90% floor** for every
  arm; keep at least two Blocking-bearing cases and say which cases an arm
  failed on, not only the mean.

Not yet measured: round 2 (resuming round-1 auditors vs fresh dispatch),
consolidation loss, recall recomputed with adjudicated real findings, a human
spot-check beyond the first 15 items, and whether any of this holds on a
runtime other than Claude Code.

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
- **Confine auditor reads to the snapshot.** Pass `--disallowedTools
  "Read(//home/**)"` (or your equivalent); otherwise an auditor can silently
  read a different checkout elsewhere on the machine. 2 of 15 runs did.
- **A ground-truth finding that needs code absent from the snapshot** (a
  private gem pinned in the lockfile, say) is out of scope: score it at the
  out-of-scope weight rather than counting every arm as missing it.
- **Adjudicate "noise" before trusting it.** A second pass that drops findings
  restating ground truth, clusters duplicates (one cluster raised 15 times
  inflates a per-run count), and checks the remainder against the code at
  `pre_audit_sha` splits noise into real / false / taste / process. Follow with
  a human spot-check of a sample.
- **Make the sweep resumable** (skip runs that already have a score file):
  usage limits and CLI auto-updates will kill runs mid-sweep.
