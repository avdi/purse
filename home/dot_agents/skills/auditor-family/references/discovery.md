# Discovering the areas

Sweep all three axes. Each finds auditors the others miss. Record, for every
candidate area, the **invariants it owns** — an area whose invariants you can't
name in a sentence isn't an area yet.

## Axis A — modules / subsystems

What you're looking for: code with its own failure modes, that a competent
general reviewer would not recognize as wrong.

Probes:

- Read the architecture section of the project doc. Every *tier* (web, jobs,
  daemon) and every *store* (relational, document, cache/queue) is a candidate.
- `ls app/ lib/ services/` — top-level directories that aren't framework
  boilerplate. A directory with its own README, its own vocabulary, or its own
  vendored client is a strong signal.
- Money, auth, and admin are always their own areas when present.
- Anything with a wire protocol or a third-party API contract (payments,
  provider OAuth, mail transport, webhooks).
- `git log --format= --name-only | sort | uniq -c | sort -rn | head -50` — the
  hot directories are where review effort pays back.
- Ask: "what breaks *silently* here?" Silent-corruption subsystems earn a
  strong-tier auditor; loud-failure ones may not need an auditor at all.

## Axis B — cross-cutting functional concerns

These apply to every change regardless of path, and the general dispatches them
even when no file is "theirs." Start from this six:

| Auditor | Owns |
|---|---|
| security | authz, secrets, crypto, injection, third-party scope |
| data-integrity | constraints, invariants, migrations, bulk writes |
| reliability | failure modes, idempotency, retries, error handling |
| performance | N+1, unbounded scans, hot paths, offloading |
| ux | user-facing behavior, a11y, error/empty states |
| code-craft | comments, naming, dead code, debug leftovers — any language |

`code-craft` goes on essentially every change: its checklist is small, applies
in every language, and catches what narrower language auditors scope past.

Cut one only when the project genuinely has no surface for it (no UI → no ux).
Add one when the project has a functional concern this six doesn't name —
privacy/PII handling, accessibility as its own discipline, i18n, cost.

## Axis C — technology areas

Enumerate the stacks, then **split where the rules diverge, not where the files
diverge**.

Probes:

- Dependency manifests (`Gemfile`, `package.json`, `go.mod`) — one auditor per
  language actually written by hand.
- The frontend is usually **two** areas when a migration is in flight (modern
  framework vs. legacy), each with opposite advice. That's the clearest signal
  a split is real.
- Templates and styling separate from both, since their rules (structure,
  component extraction / tokens, specificity) are unrelated to either.
- Testing is always its own area — its highest-value finding (assertions
  loosened or deleted to make a spec pass) belongs to nobody else.
- Build/CI/deploy/dependency-pinning is one "infrastructure" area unless the
  project is infra-heavy.
- Developer tooling (scripts, tasks) is its own light-tier area once there's a
  script tree worth conventions.

## Sanity check the roster

Before writing anything:

1. **Merge test.** For each pair of areas: would they cite the same skill and
   produce the same findings? Merge them.
2. **Ownership test.** For each area: name three findings only that auditor
   would catch. Can't? Don't create it.
3. **Coverage test.** Take the last five merged PRs. For each, list which
   auditors would have been dispatched. A PR that routes to nobody means a gap;
   a PR that routes to everybody means the areas are too broad.
4. **Stakes test.** Assign default tiers. If everything is strong, the tiers
   carry no information — recalibrate against what actually causes incidents.
