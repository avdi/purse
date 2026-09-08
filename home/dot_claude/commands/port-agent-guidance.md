---
description: Port or refresh agent guidance (skills, auditors, AGENTS.md) from a sibling repo into this one
argument-hint: [source repo, e.g. 410Labs/mailstrom]
---

Port agent guidance from **$1** into this repository, or refresh a port that has
gone stale.

Load the `porting-agent-guidance` skill and follow it. In short:

1. Find this repo's existing guidance — including on an unmerged branch or a
   stalled PR — and find the source repo's, cloning it blobless and sparse if it
   isn't checked out locally.
2. Date the last port, diff the source from that cutoff with rename detection,
   and read the delta as three piles: updates to what exists here, artifacts
   missing here, and structural changes.
3. Ask the user once about scope, where it should land, and naming — then work
   without re-asking.
4. Adapt rather than copy: verify every path, gem, script, and capability claim
   against *this* codebase, and cut what doesn't apply.
5. Sweep for areas this repo has that the source doesn't, and give them their own
   standards and owner.
6. Land it in standards-only commits, update the indexes, validate every
   frontmatter name, and report what you deliberately left out.

If the auditor family is in scope, the `auditor-family` skill owns that
framework — follow it for the skill/auditor split, the dispatcher, and the
review cadence.
