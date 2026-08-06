---
name: auditor-family
description: >
  Set up and maintain a family-of-auditors review framework in a project: the
  standards-skill / auditor-agent split, the auditor-general dispatcher, area
  auditors discovered along three axes (modules, cross-cutting concerns,
  technology), the two-round diff audit and one-round spec audit, and the
  curator and toolmonger meta-agents that keep the framework evolving. Use when
  bootstrapping agent code review for a repo, adding/splitting/retiring an
  auditor, writing a standards skill, or diagnosing a review framework that
  isn't catching what it should.
---

## What the framework is

A project gets two kinds of durable guidance, both prefixed with the project's
short name (`<prefix>-`):

| Kind | Lives in | Role |
|---|---|---|
| **Standards skill** | `.claude/skills/<prefix>-<area>-standards/SKILL.md` | *Guidelines.* The concrete rules, with bad/good code pairs. Loaded **before** doing work in that area. |
| **Area auditor** | `.claude/agents/<prefix>-auditor-<area>.md` | *Owner.* A scrupulous subagent that **enforces** the paired skill and the area's intended direction. Read-only. |

Plus three meta-agents:

| Agent | Role |
|---|---|
| `<prefix>-auditor-general` | Entry point. Reads a changeset, emits an ordered, model-tiered **dispatch plan** of which area auditors to run. Does not review. |
| `<prefix>-guidance-curator` | Harvests durable lessons out of reviews and self-reported digs, lands them in the right skill or auditor. |
| `<prefix>-toolmonger` | Turns ad-hoc commands into tools, fixes friction, seeds skills with pointers to them. |

**The load-bearing invariant: a rule lives in exactly one place — the skill. The
auditor cites it.** Duplicating a rule into both is the framework's most common
decay mode: the two copies drift, and nobody knows which is authoritative. An
auditor's own text carries only what a skill can't: values, *Direction*,
severity calibration, and what it refuses to let through.

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
  code craft. These are near-universal; start from that six and cut what
  genuinely doesn't apply.
- **Technology areas** — the stacks in play, split where their idioms diverge:
  language, web framework, modern frontend, legacy frontend, templates,
  styling, testing. Split an area when the *rules* differ, not when the files
  differ.

Sizing rules:

- **One auditor per ownable area, not per directory.** If two candidate areas
  would cite the same skill and flag the same findings, they're one auditor.
- **No auditor without a paired skill.** Write the skill first; the auditor is
  worthless without concrete rules to cite. A skill without an auditor is fine
  (process skills: git workflow, PR creation, QA).
- **Start with the functional six plus the two or three highest-stakes
  modules.** Grow from real review misses, not from a taxonomy.
- **An area nobody can name the invariants of isn't an area yet.** Skip it.

### 3. Write each pair

Skill first, then its auditor. Templates:
`references/standards-skill.md`, `references/area-auditor.md`.

Every standards skill ends with a **`## Direction`** section and every auditor
with **`## Direction / Trajectory`**: the transitions the codebase is mid-way
through (HAML→ERB, CJS→ESM, string column→enum). New code written in a
deprecated direction is a **blocking** finding even when internally correct —
this is what stops a codebase from accreting the pattern it's trying to leave.

### 4. Write the auditor-general

Template: `references/auditor-general.md`. It owns the roster table, the model
tiers, the shared severity model, and the conflict-resolution rules that every
area auditor references rather than restates.

### 5. Write the meta-agents

Templates in `references/meta-agents.md`.

### 6. Wire it into the project doc

`AGENTS.md` gets: a **Skills Index** table (skill → when to use), an
**Auditors** index grouped functional / technology / module, and the workflow
steps that invoke them (see cadence below).

## Review cadence

Three distinct passes. They are not interchangeable.

### Spec/plan audit — one round, raise-concerns mode

Run *before* implementing, against a Plan or design Spec. The auditor-general
is told explicitly there's no diff. Each dispatched auditor reads the document,
skims only enough code to sanity-check the approach, and hands back **concerns
and open questions**, not investigations and not fixes. Findings cite the
plan's step, not `file:line`. Output is a punch list ordered by how much each
concern could reshape the approach — not a Blocking/Should-fix verdict, since
nothing exists to block. Catches direction mistakes while they're free.

### Diff audit — two rounds, hard cap

**Round 1:** invoke the auditor-general on the changeset; it returns the
dispatch plan; the invoking agent runs each listed auditor as a subagent
(serial or parallel) and consolidates findings into one verdict grouped
**Blocking → Should-fix → Consider**, deduplicated and attributed.

Before acting on round 1, record the boundary: `git rev-parse HEAD` (commit
round 1's state if uncommitted).

**Round 2:** invoke the auditor-general again, explicitly told it's round 2,
with a **commit range** bounding only the fix (`<boundary-sha>..HEAD`) — not a
prose summary, not a pasted diff. It scopes the plan to those changes and
routes only the auditors whose area the fixes touch.

**Two rounds is the cap.** Round 2 is final: auditors must not hold findings
back expecting a round 3, and the invoking agent fixes or consciously accepts
whatever comes back.

Each round's consolidated verdict, and what was addressed from it, is posted as
a **PR comment** — never folded into the description. The description describes
the change as it now stands; the conversation carries the narrative.

### Post-merge harvest — curator and toolmonger

After the PR is pushed: hand the curator **at most one** self-reported
investigation lesson (something that cost real time to dig up), and the
toolmonger **at most one** ad-hoc command worth banking plus any number of tool
trouble reports. Both are expected to conclude "nothing worth capturing" most
of the time — that's the design, not a failure.

## Model tiers

Each dispatch-plan row names a tier for invoking that auditor:

- **strong** — subtle reasoning, high blast radius, the high-stakes subsystems.
- **medium** — the workhorse for most technology, style, and module changes.
- **light** — small mechanical slices checked against a handful of conventions.

Each auditor has a **default tier** in the roster; the general adjusts up for a
large/subtle slice, down for a tiny mechanical one. The invoking agent may
override.

## Severity model

Defined once, in the auditor-general; every auditor reports against it.

- **Blocking** — risks user data, production, money, security, or correctness;
  missing tests for risky logic; misleading names; dropped constraints; debug
  cruft; **new code in a deprecated direction**.
- **Should-fix** — clear quality issues worth doing now.
- **Consider** — preferences or improvements fine to defer with a `TODO`.

Conflict resolution: the **functional** owner (security, data integrity,
reliability) outranks a **technology/style** owner — never trade safety for
idiom. When two areas overlap, attribute the finding to the **narrower** owner
and state it once. Direction always beats "it matches the surrounding legacy
code."

## Maintaining the family

| Signal | Move |
|---|---|
| The same finding recurs across PRs | The rule isn't in a skill, or is stated too weakly. Curator's job. |
| An auditor's findings are always noise on this repo's changes | Narrow its scope or lower its default tier; retire it if it never lands. |
| One auditor's charter has two sets of unrelated invariants | Split it — and split the paired skill with it. |
| A real bug shipped that an area owns | Add a `## What you scrutinize most` bullet to that auditor, or fix the severity calibration. |
| A skill exceeds ~200 lines | Move detail into `references/` under the skill; keep SKILL.md scannable. |
| A transition finishes | Delete the `## Direction` entry. Stale direction is worse than none. |

Only the curator edits standards, and only ever as **standards-only commits**
separate from code fixes, one concern per commit — so the reasoning lives in
the standards' own history.

## Anti-patterns

- Duplicating a coding rule into both the skill and its auditor.
- Creating auditors from a taxonomy instead of from areas someone can name the
  invariants of.
- An auditor with no paired skill — it will invent rules.
- Letting the auditor-general write the review itself instead of dispatching.
- Dispatching every auditor on every change; an unrelated auditor is noise that
  trains the reader to skim.
- Running round 2 against the whole changeset instead of the fix range.
- A third round.
- Minting a broad new mandate from one reviewer's stylistic aside.
- Auditors that only criticize: acknowledging what a change got right is how
  the instinct gets reinforced.

## References

- `references/discovery.md` — probes for finding areas along the three axes.
- `references/standards-skill.md` — standards skill template.
- `references/area-auditor.md` — area auditor charter template.
- `references/auditor-general.md` — dispatcher template.
- `references/meta-agents.md` — curator and toolmonger templates.

Subagent frontmatter mechanics (tools, `mcpServers`, model): see the
`defining-subagents` skill.
