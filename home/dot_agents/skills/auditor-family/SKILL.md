---
name: auditor-family
description: >
  Set up and maintain a family-of-auditors review framework in a project: the
  standards-skill / auditor-agent split, the auditor-general dispatcher, area
  auditors discovered along three axes (modules, cross-cutting concerns,
  technology), the shared severity-model and search-tools skills, the
  generalist closing auditor, the running-audits process skill (one round by
  default, a second only when triggered), the field-researcher / curator /
  toolmonger meta-agents, and the baseline-plus-overlay layout when a shared
  baseline already ships most of the fleet. Use when bootstrapping agent code
  review for a repo, adding/splitting/retiring an auditor, writing a standards
  skill, or diagnosing a review framework that isn't catching what it should.
---

## What the framework is

A project gets durable guidance of four kinds, prefixed with the project's
short name (`<prefix>-`):

| Kind | Lives in | Role |
|---|---|---|
| **Standards skill** | `skills/<prefix>-<area>-standards/SKILL.md` | *Guidelines.* The concrete rules, with bad/good code pairs. Loaded **before** doing work in that area. |
| **Area auditor** | `agents/<prefix>-auditor-<area>.agent.md` | *Owner.* A scrupulous read-only subagent that **enforces** the paired skill and the area's intended direction. |
| **Shared auditor skills** | `skills/<prefix>-auditor-severity-model`, `skills/<prefix>-auditor-search-tools` | Cited by every auditor instead of restated in each. |
| **Process skill** | `skills/<prefix>-running-audits` | How the invoking agent runs a round end to end (see "Review cadence"). |

Plus meta-agents:

| Agent | Role |
|---|---|
| `<prefix>-auditor-general` | Entry point. Reads a changeset, emits an ordered **dispatch plan** (auditor, paths, why) and the one model the round runs on. Does not review, and does not pre-investigate. |
| `<prefix>-auditor-generalist` | Closing pass, invoked directly (not via the dispatch plan) with the diff plus that round's consolidated verdict. Judgment-based eyes for design/architecture smells and gaps no area auditor owns; also confirms "fixed" claims and adopted design rows really are in the tree. |
| `<prefix>-agent-guidance-field-researcher` | Harvests durable lessons from reviews and self-reported digs and **files them as `lesson` issues** on the guidance repo. Cannot edit it. |
| `<prefix>-guidance-curator` | The only writer of guidance. Lands lessons from the queue, per-issue in real time and as a sweep that sees the whole queue at once. |
| `<prefix>-toolmonger` | Turns ad-hoc commands into tools, fixes friction, seeds skills with pointers to them. |

**The load-bearing invariant: a rule lives in exactly one place — the skill. The
auditor cites it.** Duplicating a rule into both is the framework's most common
decay mode: the two copies drift, and nobody knows which is authoritative. An
auditor's own text carries only what a skill can't: values, *Direction*,
severity calibration, and what it refuses to let through. The generalist is the
one exception to "no auditor without a paired skill" (see Bootstrapping step 6).
The same goes across layers: never put a rule in both a baseline and an overlay;
a lesson that now applies to two or more overlays belongs in baseline.

**Frontmatter is just `name` and `description`.** Agents are named
`*.agent.md` (Copilot silently skips plain `.md`), name no `model:`, and list no
`tools:`/`mcpServers:` unless the agent truly needs a restriction or a grant;
the two runtimes spell those differently and each silently ignores the other's
form. Mechanics: `defining-subagents` skill and the agent-infra repo's
`docs/cross-runtime-agent-authoring.md`.

## Baseline plus overlays

If a shared baseline plugin already ships the fleet (410Labs: `baseline`, with
`<project>-overlay` plugins), do **not** re-author it per project. A project
adds only:

- **Overlay auditors** for its own modules/subsystems/providers, each with a
  paired overlay standards skill.
- **`*-notes` supplements** that extend a baseline agent or skill without
  restating it: `auditor-general-notes` (the project's stakes sentence and
  routing for its overlay auditors), `running-audits-notes` (what is unsafe to
  run concurrently in this project, project-local verification scripts), and
  `<area>-auditor-notes` where a baseline auditor needs project calibration.
- Baseline must be enabled explicitly alongside the overlay in runtimes
  without plugin-dependency resolution (Copilot).

The remaining sections describe the whole framework, which is what a project
without a baseline bootstraps and what a baseline author maintains.

## Bootstrapping a project

Do these in order. Steps 1–3 are the real work; the rest is mechanical.

### 1. Write the project brief first

The auditors all reference one root doc (`AGENTS.md`, with `CLAUDE.md` as an
`@AGENTS.md` include). Before any auditor exists, that doc needs: what the
product does, the architecture tiers, the data stores, the file map, and the
stakes ("this app holds access to users' inboxes" — the sentence that sets
baseline scrutiny for every auditor downstream).

### 2. Discover the areas along three axes

An "area" is something a single agent can *own*. Sweep all three axes; each
finds auditors the others miss. See `references/discovery.md` for the probes.

- **Modules / subsystems** — the parts of *this* system with their own
  invariants: a daemon, a queue layer, a document store, billing, admin, the
  marketing site. Signal: a directory whose code fails in ways no general
  reviewer would recognize.
- **Cross-cutting functional concerns** — the ones that apply to every change
  regardless of path: security, data integrity, reliability, performance, UX,
  code craft and code docs. Near-universal; cut what genuinely doesn't apply.
- **Technology areas** — the stacks in play, split where their idioms diverge:
  language, web framework, modern frontend, legacy frontend, templates,
  styling, testing, shell. Split an area when the *rules* differ, not when the
  files differ.

Sizing rules:

- **One auditor per ownable area, not per directory.** If two candidate areas
  would cite the same skill and flag the same findings, they're one auditor.
- **No auditor without a paired skill.** Write the skill first. A skill without
  an auditor is fine (process skills: git workflow, PR creation, QA).
- **Start with the functional set plus the two or three highest-stakes
  modules.** Grow from real review misses, not from a taxonomy.
- **An area nobody can name the invariants of isn't an area yet.** Skip it.

### 3. Write each pair

Skill first, then its auditor. Templates:
`references/standards-skill.md`, `references/area-auditor.md`.

Every standards skill ends with a **`## Direction`** section and every auditor
with **`## Direction / Trajectory`**: the transitions the codebase is mid-way
through (HAML→ERB, CJS→ESM, string column→enum). New code written in a
deprecated direction is a **blocking** finding even when internally correct. If
the destination can't be reached in this change, the fallback is a `TODO`
naming the destination shape and its tracking issue (or the verdict comment
recording the disposition).

If the guidance repo uses rule traceability (stable `R-NNNN-slug` IDs declared
as `<!-- rule: ... -->` markers, `rule-ref:` where another file enforces the
same rule), every rule you write gets an ID and every auditor reference points
at the authoritative one. Rules a script can decide get a codified check; the
auditor still reviews by hand what a passing check doesn't cover.

### 4. Write the shared pieces and the auditor-general

- `<prefix>-auditor-severity-model` skill: the Blocking / Should-fix / Consider
  scale, reversibility-as-correctness, "state the invariant, not the
  prohibition", and how much each severity's report says. Template inside
  `references/auditor-general.md`.
- `<prefix>-auditor-search-tools` skill: the one paragraph telling auditors to
  search with ripgrep before hand-rolled grep, and that these tools are
  read-only.
- `<prefix>-auditor-general`: `references/auditor-general.md`. Owns the roster,
  the round model, routing rules and conflict resolution; every area auditor
  references it rather than restating it.

### 5. Write the running-audits process skill and the meta-agents

`references/running-audits.md` is the invoking agent's procedure. Meta-agent
templates: `references/meta-agents.md`.

### 6. Write the generalist auditor

Template: `references/generalist-auditor.md`. No paired skill: its job is the
gestalt judgment a written rule can't substitute for. Wire in whatever
code-intelligence MCP servers the environment has (call-graph, LSP
navigation) — each optional, each inert rather than an error if unregistered.

### 7. Wire it into the project doc

`AGENTS.md` gets: a **Skills Index** table (skill → when to use), an
**Auditors** index grouped functional / technology / module, and the workflow
steps that invoke `running-audits`.

## Review cadence

Three distinct passes. They are not interchangeable. Full procedure for the
diff audit is `references/running-audits.md`; the shape:

### Spec/plan audit — one round, raise-concerns mode

Run *before* implementing, against a Plan or design Spec. The auditor-general
is told explicitly there's no diff and leans toward fewer auditors (a document
gives most language auditors nothing to say; favor cross-cutting and
architecture-relevant ones). Each dispatched auditor reads the document, skims
only enough code to sanity-check the approach, and hands back **concerns and
open questions**, not investigations and not fixes. Findings cite the plan's
step. Output is a punch list by auditor, ordered by how much each could reshape
the approach. It does not replace the later diff audit, and its recorded
dispositions are handed to the closing pass in round 1.

### Diff audit — one round by default, a second only when triggered

1. **Dispatch** the auditor-general on the changeset. It returns the plan.
2. **Run codified checks once, centrally**, before the auditors review; hand
   each relevant auditor the compact result. A passing check narrows the
   manual look; it never waives an auditor's charter.
3. **Run every row** of the plan, as one subagent each, in a single concurrent
   block, on the plan's one round model. Hand each auditor the diff as a file,
   its row's Paths and Why, and the severity-model skill's content. Never trim
   the plan yourself; if the fan-out is disproportionate, ask for a leaner plan
   *before* dispatching.
4. **Consolidate** into one verdict, Blocking → Should-fix → Consider,
   deduplicated and attributed (narrower owner wins; functional beats style).
5. **Close with the generalist**, given the changeset and the verdict.
6. **Post the verdict** as a PR comment (a table: finding, severity,
   disposition) with a machine-readable `round2_reason`; never fold it into the
   PR description.
7. **Mark the boundary** (`git rev-parse HEAD`), disposition and fix.
8. **Round 2?** A Blocking finding forces one. Otherwise run three checks
   before stopping — *break it* (revert each fix, watch a spec fail), *run it*
   (run every check an auditor suggested but didn't run), *keep the coverage*
   (a test edited by a fix must still exercise what it used to) — and run
   round 2 only for one you tried and could not do, or if the author asks.
   Round 2 goes through the auditor-general, told it is round 2, given
   `<boundary-sha>..HEAD` and round 1's verdict read from the PR comment.
9. **Two rounds is the cap.** Round 2 is final.

Discipline that makes a concurrent round safe, all in `running-audits`:

- **Auditors are read-only**: no edits, no new files, no restoring a file in
  place, no mutation checker (it rewrites a file, which is an edit). Probes
  that must break something do it in a scratch worktree off the same commit.
- **The orchestrator is bound too**: no edits to the reviewed tree from
  dispatch until the verdict is posted. Auditors read the working tree, not a
  frozen diff; an edit mid-round means each reviewed a different codebase.
  Work that can't wait goes in a second worktree. Don't give auditors an
  isolated worktree as the review *target* — pre-commit work isn't in it.
- **Subagents start in the orchestrator's cwd**. If the target is another
  worktree, name it as the only review target, say the cwd is a different
  checkout, and require `git -C <target> rev-parse --short HEAD` to match the
  expected SHA first.
- **Shared state serializes**: rows that run a suite writing a shared test DB
  are dispatched on their own; the project's `running-audits-notes` names
  what's unsafe.
- **Verify a "fixed" against `HEAD`**, not the working tree; apply fixes with
  an edit step that aborts if any replacement misses.
- **Establish facts by running them** (cheapest read-only probe) and put the
  probe result in the finding.
- **Fix the code, don't narrate the fix** in source comments; the PR comment is
  the record.
- Auditor findings are not human-review feedback. Don't generalize a finding
  into a new standard while clearing it; noisy auditors are recalibrated as a
  separate curator action.

Small follow-ons (a project-defined eligibility test: small scope, no
durability/migration/journey-boundary change) get a proportional route: the one
or two owning auditors, no generalist. Risk overrides size.

### Post-merge harvest — field researcher and toolmonger

After the PR is pushed: hand the field researcher **at most one** self-reported
investigation lesson plus whatever review feedback produced durable lessons, and
the toolmonger **at most one** ad-hoc command worth banking plus any tool
trouble reports. Both are expected to conclude "nothing worth capturing" most of
the time — that's the design.

## Round model

Every auditor in a round runs on **one** model, which the dispatch plan names
for the whole round:

- **fast** — the default: the runtime's **current-generation** small/fast
  model (Claude: Haiku 5.5 or newer).
- **balanced** — the mid-size workhorse. Use it when the small model isn't
  current-generation or you can't tell which generation it is.
- **strongest** — escalate the whole round when a Blocking miss would be an
  incident: authn/authz, secrets, money, data deletion or migration,
  privacy/consent boundaries, or a large change across several. Name the
  reason in Scope.

Never mixed models across one round's auditors; one subagent per auditor, never
several charters folded into one session; an *old-generation* small model is
not `fast`. This is measured, not taste — see `references/fleet-eval.md`.

No agent's frontmatter names a model. The invoking agent maps
fast/balanced/strongest to whatever its runtime calls those models today, and
uses the runtime's default subagent model for the whole round if it can't
override per dispatch.

## Severity model

Defined once, in the severity-model skill; every auditor and the running-audits
skill cite it.

- **Blocking** — risks user data, private content, credentials, money, consent,
  production correctness, or irreversible operations; missing tests for risky
  logic; misleading names; dropped constraints; debug cruft; **new code in a
  deprecated direction**.
- **Should-fix** — clear quality issues worth doing now.
- **Consider** — preferences or improvements fine to defer.

Reversibility is part of correctness: an always-on operation whose mistakes
can't be turned off without a deploy is at least Should-fix. Findings state the
invariant that must hold, not just the prohibition. Full rewrites only for
Blocking; no courtesy praise; "No findings" is one line.

Conflict resolution (in the auditor-general): the **functional** owner
outranks a technology/style owner; privacy/consent/data-lifecycle outranks
everyone on content-derived data; overlapping findings go to the **narrower**
owner, stated once; direction beats "it matches the surrounding legacy code."
When two auditors give opposite verdicts on one instance of a repeated pattern,
check the pattern's other instances — what the siblings do decides it.

At the second instance of the same defect, search all related sites and fix at
the owning boundary instead of patching each. Pre-existing findings the change
doesn't worsen are recorded **Seen, not filed** (unless independently
Blocking); follow-on issues are budgeted per PR, not per auditor or round.

## Maintaining the family

| Signal | Move |
|---|---|
| The same finding recurs across PRs | The rule isn't in a skill, or is stated too weakly. Field researcher files it; curator lands it. |
| An auditor's findings are always noise on this repo's changes | Narrow its scope; retire it if it never lands. |
| One auditor's charter has two sets of unrelated invariants | Split it — and split the paired skill with it. |
| A real bug shipped that an area owns | Add a `## What you scrutinize most` bullet to that auditor, or fix the severity calibration. |
| A change slips past the dispatcher because its subject belongs to an area its paths don't | Add a subject-routing rule to the auditor-general (e.g. a new build gate → infrastructure auditor). |
| A skill exceeds ~200 lines | Move detail into `references/` under the skill; keep SKILL.md scannable. |
| A transition finishes | Delete the `## Direction` entry. Stale direction is worse than none. |
| A repeated rule can be decided mechanically | Codify it as a check; keep the auditor's manual look for what the check can't see. |
| You want to change the round model, the roster shape, or effort | Measure first — `references/fleet-eval.md`. Intuitions about what's "light" were wrong, and what "small model" means went stale when a new generation shipped. |
| The generalist's "roster gap" bucket names the same missing auditor twice | Stop deferring — bootstrap that area auditor (steps 2–3). |

Only the curator edits standards, and only ever as **standards-only commits**
separate from code fixes, one concern per commit — so the reasoning lives in
the standards' own history and any one rule can be reverted alone. Anything
genuinely a call for the guidance owner becomes a decision issue assigned to
them; it blocks only the lesson that raised it.

## Anti-patterns

- Duplicating a coding rule into both the skill and its auditor, or into both
  baseline and an overlay.
- Creating auditors from a taxonomy instead of from areas someone can name the
  invariants of.
- An area auditor with no paired skill — it will invent rules. (The generalist
  is the sole, deliberate exception.)
- Letting the auditor-general write the review itself, or pre-investigate
  likely findings, instead of routing. It stops when every changed subject has
  an owner.
- Per-auditor model tiers, mixed models in a round, or an old-generation small
  model as the "fast" tier.
- Folding several auditors' charters into one session or one "lane" to save
  dispatches (monoliths and affinity clusters both lost recall).
- Pinning `model:` in an auditor's frontmatter; hardcoding `tools:`/MCP syntax
  for one runtime only.
- Dispatching every auditor on every change; an unrelated auditor is noise that
  trains the reader to skim.
- Trimming the dispatch plan yourself because a row looks marginal.
- Dispatching auditors one call at a time (a round costs the sum instead of the
  slowest).
- Editing the reviewed worktree mid-round, or letting an auditor mutate it.
- Running round 2 against the whole changeset instead of the fix range, running
  one when nothing triggered it, or a third round.
- Posting the verdict in the PR description.
- Minting a broad new mandate from one reviewer's stylistic aside.
- Generalizing an auditor finding into a new standard while clearing it.
- Courtesy praise for code that merely did what was required.
- Skipping the generalist because "no auditor owns design smells" — that gap is
  its job. Equally, routing a design smell to "propose a new auditor" just
  because no skill backs it.

## References

- `references/discovery.md` — probes for finding areas along the three axes.
- `references/standards-skill.md` — standards skill template.
- `references/area-auditor.md` — area auditor charter template.
- `references/auditor-general.md` — dispatcher and shared severity-model /
  search-tools templates.
- `references/running-audits.md` — the invoking agent's round procedure.
- `references/meta-agents.md` — field researcher, curator and toolmonger.
- `references/generalist-auditor.md` — closing-pass auditor template.
- `references/fleet-eval.md` — what dispatch shape measured best, and how to
  re-measure it against a project's own graded audits.
