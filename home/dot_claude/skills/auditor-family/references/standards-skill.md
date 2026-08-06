# Standards skill template

Path: `.claude/skills/<prefix>-<area>-standards/SKILL.md`

The skill holds **the rules**. Its auditor cites it and never restates it.
Write this before the auditor.

Rules for the rules:

- **Show, don't assert.** A rule lands as a tight bad/good pair in the
  project's real language, not a paragraph.
- **State the current design, not its history.** No "previously we…", no
  "we no longer…", no ticket or PR references. Git holds history.
- **Say where things live.** A "Where X lives" table is the single most-used
  section — it saves every future implementor the same search.
- **Keep it under ~200 lines.** Overflow goes to `references/` beside SKILL.md.
- **End with `## Direction`** — the transition in flight, and the destination
  shape new code should take. Delete entries when a transition completes.

---

```markdown
---
name: <prefix>-<area>-standards
description: >
  Conventions for <project>'s <area>: <the five or six concrete rules, named>.
  Use when writing or reviewing <the concrete triggers: paths, file types,
  operations>. Paired with the <prefix>-auditor-<area> agent.
---

## Overview

Two or three sentences: what this area is, and the property that makes its
mistakes expensive. The auditor inherits its scrutiny from this paragraph.

## Where <area> lives

| Concern | Location |
|---|---|
| <thing> | `path/to/thing` |

## <Rule group>

The rule, stated once, with its rationale.

```<lang>
# bad — <what goes wrong>
<code>

# good — <the shape that's correct>
<code>
```

## Gotchas

Non-obvious facts that cost someone real time: an API that lies, a default
that's wrong for this project, a constraint enforced in a surprising place.

## Direction

- **<Destination pattern>.** New code goes to <destination>, not <deprecated>.
  When the destination can't be reached in one change, leave a `TODO` naming
  the destination shape and the issue tracking it — without it, the stopgap
  reads as the intended design and the next change extends it.
```
