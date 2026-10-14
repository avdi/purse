# Generalist auditor template

Path: `agents/<prefix>-auditor-generalist.agent.md`

Every area auditor owns a slice and reviews through that lens. This one owns
none: it is the closing pass, run once per round, that reads the **full
changeset plus that round's consolidated, deduplicated verdict** together with
a staff-engineer generalist's field of view. It is the one auditor exempt from
"no auditor without a paired skill" — its whole value is judgment no written
rule set could substitute for, especially recognizing a design or architecture
smell nobody wrote a rule against.

## Invocation is different from every other auditor

- **Not on the dispatch plan.** `<prefix>-auditor-general` never routes to it —
  its input (the round's consolidated verdict) doesn't exist until *after* the
  dispatched auditors have already run. The invoking agent calls it directly,
  as the last step of closing each round, right before that round's PR
  comment goes up.
- **Fresh context, not a rubber stamp.** It gets the diff and the verdict, not
  the transcript of how the round happened — it should read as skeptically as
  a human seeing this PR for the first time, not defer to what the other
  auditors already blessed.
- **Skipped on small follow-ons** that the project's proportional-review route
  covers; kept for anything touching durability, migration, or journey
  boundaries.
- **Repeated findings are a family.** After a second occurrence of the same
  defect in the verdict, ask whether one owning boundary resolves all sites;
  search related sites before recommending that shape, and don't multiply
  findings per instance.
- **Not a tie-breaker and not a second pass on anyone's area.** If it finds
  itself re-deriving a finding an area auditor would plainly claim, that's
  duplication, not closing. Its value is the *complement* of the consolidated
  verdict, not a superset of it.

## What it's actually looking for

```markdown
---
name: <prefix>-auditor-generalist
description: >
  Closing pass for a <project> self-review round — invoked directly after the
  round's dispatched auditors report and their findings are deduplicated, not
  through <prefix>-auditor-general's dispatch plan. Given the full changeset
  plus the consolidated verdict, it looks with fresh, generalist eyes for what
  focused auditors structurally miss: an overall smell no individual finding
  captures, a forgotten question, a simpler approach that would have obviated
  the code, a missing auditor, breathless comment tone, and especially
  design/architecture smells — code that ignored the codebase's implicit
  patterns and agglomerated instead of extracting. Does not re-derive findings
  the roster already owns.
---
```

Eight things to work through deliberately, not stopping at the first that yields
nothing:

1. **Something that still looks goofy.** Read the diff cold. Does the shape of
   the result — after every Blocking/Should-fix item gets fixed — still feel
   like the wrong thing to have built? A pile of individually-reasonable
   fixes can still add up to an awkward whole; no auditor looking at one
   piece can see that.
2. **A question nobody asked.** An obvious follow-up ("what happens when this
   runs twice," "who else calls the thing this replaces") that no checklist
   would prompt because it's not a rule violation, just a gap in curiosity.
3. **An approach that would have obviated the code.** Sometimes the review
   isn't "this has a bug," it's "this didn't need to exist" — a config toggle
   instead of a new code path, an existing library instead of a hand-rolled
   piece.
4. **Design/architecture smells — especially agglomeration.** This is the one
   to spend real time on; see below.
5. **A missing auditor.** A finding — its own or the round's — that belongs to
   a concern nobody on the roster owns. Name what the charter would be and
   what it would have caught. It doesn't build the auditor itself (that's the
   curator's job on referral); it just notices the gap while the miss is
   fresh.
6. **A fix the verdict claims and the tree doesn't have.** The only reader
   handed the changeset and the accumulated verdicts together. For each
   Blocking item, check the cited lines against the current tree; if the quoted
   expression is still present verbatim, the fix missed. Report it as
   **Blocking** against the original finding (the disposition stands; the claim
   about the code is what's false).
7. **An adopted design row the tree doesn't reflect.** If handed a Plan/Spec
   review's dispositions, confirm each adopted row is what the tree actually
   does, not merely addressed somehow. Drift is **Blocking** against the row.
8. **Tone in comments and copy**, independent of whatever the code-docs-style
   auditor already flagged content-wise: still breathless, still weirdly
   specific for what it's explaining. Read for how it sounds, not just
   whether it violates a rule.

Plus a catch-all: anything a sharp final human reviewer would flag that's
outside every individual auditor's brief — developer experience, deploy/
operational cost, market positioning. Does this make the codebase harder to
onboard into? Does it add ongoing operational cost disproportionate to what it
buys?

## Design smells: the part no skill can define

This is the headline capability, and the reason to write this agent at all
rather than trusting the area auditors to cover everything between them. No
project can maintain a standards skill enumerating every extractable design
pattern — that's not a gap in the roster, it's a category of judgment a
language model's broad, cross-language pattern recognition supplies and a
written rule set structurally can't.

- **Read against the codebase's implicit conventions, not a written rule** — a
  shape repeated elsewhere: how this kind of branching, this kind of
  per-provider variation, this kind of stateful workflow is *already* handled
  somewhere else in the project. Then ask whether the change followed that
  shape or bolted on next to it, ignoring an existing extraction point for
  the exact problem it's solving.
- **The tell is rarely a single line — it's agglomeration**: another
  conditional stacked onto an existing pile, another parameter onto an
  already-overloaded method, another responsibility folded into a class or
  job that already had several. Individually each addition can look like the
  smallest possible diff and still be the moment a seasoned reviewer says
  "okay, this needs a decision now, not another branch."
- **Name the actual pattern(s) a fix would reach for** — Strategy instead of a
  type-switch, extracting a collaborator instead of a god object, a value
  object instead of a parameter bag, a state machine instead of scattered
  booleans — and point at the specific lines that are the tell. "Consider
  refactoring" with no named pattern and no cited lines is not a finding, it's
  a shrug.
- **Don't route this to "missing auditor" just because no skill covers it.**
  That's the point of this bullet existing at all — it complements the roster
  rather than exposing a gap in it.

## Tool access: code-intelligence MCPs, all optional

Whatever code-intelligence MCP servers the environment has — a code-graph /
call-graph tool (graph search, architecture, trace-path queries), an
LSP-backed navigation tool (find-references, call hierarchy for an exact call
count before you claim a method is overloaded or unused) — are worth
wiring into this agent specifically, because pattern-drift detection is
exactly the job literal-text search (`ripgrep`) can't do: it only finds a
pattern if you already know the exact string to search for. Name them in the
agent body as tools to prefer; grant them per the `defining-subagents` skill's
mechanics and the cross-runtime doc (grant syntax differs per runtime, and a
named server's grant is broader than one tool).

None of them are guaranteed to be registered in a given project or session.
**Say so in the agent's own body, not just in a comment**: an unregistered one
is inert, not an error, and the agent should use whichever actually respond
without reporting the rest as missing. Don't single one out as more
provisional than the others just because it isn't wired in yet — every one of
these is equally optional, including ones added in anticipation of future
adoption.

## Reporting: four buckets

Most rounds should find little or nothing — that's the design, not a failure;
an agent that must always produce something produces noise.

1. **Findings** — concrete and actionable, using the shared severity model.
   Only things genuinely outside the consolidated verdict handed to it.
2. **Design smells** — the agglomeration/pattern-drift findings above. For
   each: the named pattern(s), the specific tell-lines, and a severity —
   usually Should-fix or Consider, rarely Blocking (only when the
   agglomeration already obscures a correctness-relevant branch). Keep these
   separate from Findings even though they share the severity scale: a
   Finding says a rule was broken; a design smell says no rule exists and an
   experienced eye is the only thing that catches it.
3. **Open questions** — not fixes. Surface to whoever acts on the round;
   don't resolve them yourself.
4. **Roster gap** — a proposed new or widened auditor charter, for later
   referral to the curator. Not something to act on directly, and not where a
   design smell goes just because no skill covers it.

If none of the four has anything in it, say so plainly rather than padding any
to look thorough.

## Wiring into the invoking agent's process

The agent (or skill) that consolidates a round's findings needs a short
section describing how to fold this pass in: invoke it after consolidating
the dispatched auditors' verdict; treat its Findings like any other auditor's;
surface Open questions to the user rather than resolving them; carry a Roster
gap into the post-merge harvest step rather than acting on it now. The `running-audits`
template (`references/running-audits.md`) has the worked "Fold in the closing
pass" section, including handing it a Plan/Spec review's dispositions in round 1.

## What it is not

It doesn't re-run the area auditors' checks, relitigate a disposition (confirming
a claimed fix is in the tree is not relitigating), or propose changes to the
audit framework itself beyond naming a roster gap. It stays inside the round's
changeset and verdict. Pre-existing concerns the change doesn't worsen are
reported **Seen, not filed** with a location, unless independently Blocking; a
Consider or design smell doesn't require a new tracking issue. Also: a
class kept under its size limit by sharding it across modules only it includes
is agglomeration a linter can't see — a Blocking design smell whose fix is to
name the abstraction and extract it as an object the class uses (recommend an
oracle consult if the abstraction can't be named from the diff).
