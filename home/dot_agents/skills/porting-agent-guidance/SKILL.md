---
name: porting-agent-guidance
description: >
  Port agent guidance — skills, auditors, AGENTS.md, hooks — from a sibling repo
  that has accumulated more of it into a repo that has less, or refresh a port
  that has gone stale. Covers finding what the source added since the last port,
  deciding scope with the user, adapting each artifact to the target's real
  facts, discovering areas the source has no counterpart for, and landing it.
  Use when asked to sync, port, or refresh one project's agent guidance from
  another's, or when a project's .claude/ has fallen behind a sibling's.
---

## What this is for

Two repos in the same org grow guidance at different rates. One becomes the
place where standards actually get written; the other gets a snapshot once and
then drifts. This is the procedure for closing that gap without importing facts
that aren't true in the target.

The one rule everything else serves: **the source repo supplies structure and
lessons; the target repo supplies facts.** Every path, gem, script, table, and
CI capability in the ported text is verified against the target, or it doesn't
go in. A confidently wrong skill is worse than a missing one — everything
downstream trusts it.

## 1. Find both sides

**The target's existing guidance may not be on `main`.** Look before assuming
there is none:

```bash
git log --all --oneline --diff-filter=A -- '.claude/*' 'AGENTS.md' 'CLAUDE.md'
git branch -a --contains <that-sha>
gh pr list --state all --head <branch> --json number,state,title
```

A port that stalled in an open PR is the usual finding. Landing the refresh on
that same branch keeps one PR instead of two — but rebase it onto current `main`
first, before writing anything.

**Get the source repo readable.** If it isn't checked out locally, a blobless
sparse clone is enough and costs seconds:

```bash
git clone --filter=blob:none --no-checkout <url> src && cd src
git sparse-checkout init --cone && git sparse-checkout set .claude .codex .gemini .augment
git checkout main
```

When SSH has no key in this environment (devcontainers, Codespaces), clone over
HTTPS with the token that is already there — `gh auth status` will show it —
rather than debugging keys:

```bash
git clone --filter=blob:none "https://x-access-token:${GH_TOKEN}@github.com/<org>/<repo>.git"
```

For the target's own remote, a per-command rewrite avoids touching the checkout's
configured URL:

```bash
git -c url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf="git@github.com:" push --force-with-lease
```

## 2. Establish the cutoff and read the delta

Date the last port from the target's own commits, then diff the source from
there:

```bash
CUT=$(git -C src rev-list -1 --before=<port-date> main)
git -C src diff --stat -M10% "$CUT"..main -- .claude AGENTS.md
```

`-M10%` matters: a source that renamed its skills (a `<project>-` prefix is the
common move) will otherwise show every file as a delete plus an add, hiding the
real content delta inside the noise.

Read the diff, not just the stat. What you are looking for is in three piles:

- **Deltas to artifacts the target already has** — the highest-value, lowest-risk
  material.
- **Whole artifacts the target lacks** — process skills, standards skills,
  auditors.
- **Structural changes** — a naming convention, a new indexing scheme in
  `AGENTS.md`, a workflow the skills now assume.

## 3. Settle scope, landing, and naming with the user

These change the size of the work by an order of magnitude, so ask once, with
concrete tiers, before writing anything:

- **Scope** — sync the existing artifacts only; plus the process and workflow
  skills; plus the whole auditor family (see the `auditor-family` skill, which
  owns that framework).
- **Landing** — refresh the existing branch and its PR, or a fresh branch off
  `main`, or working tree only.
- **Naming** — adopt the source's prefix convention for the target's own skills,
  or leave them bare.

Then work. Don't re-ask mid-flight.

## 4. Adapt, never copy

For each artifact, the source's text is a draft to be re-grounded:

- **Verify every fact against the target.** A codebase-Q&A MCP (`auggie`'s
  `codebase-retrieval`, or a code-graph server) answers "how does X work here"
  far faster than reading files, and it is the difference between a skill that
  cites real classes and one that cites the source repo's.
- **Cut what the target doesn't have.** Different queue library, no document
  store, no SPA, a different feature-flag gem. Deleting is cheaper than
  half-translating.
- **Check the capability claims especially.** These are the ones that read as
  true and aren't: "CI keeps the failure screenshot", "the linter catches this",
  "there's a preview for every component". Confirm in the target's CI config and
  initializers. Where the capability is genuinely absent, say so in the skill —
  "nothing lints this, so review is the only backstop" is real guidance.
- **Keep the lesson, drop the anecdote.** A worked example naming the source's
  issue numbers and services becomes an example in the target's own vocabulary.
- **Watch for the reverse flow.** The target sometimes edited its copy after the
  original port; that content is newer than the source's. Diff both ways and
  offer the source repo the deltas it lacks.

## 5. Discover the target's own areas

A port that only mirrors the source leaves the target's distinctive subsystems
unowned. Sweep the three axes from the `auditor-family` skill — modules,
cross-cutting concerns, technologies — against the target specifically, and look
at two cheap signals it makes concrete:

- **The repo's issue labels.** An org that already labels `billing`, `vault`,
  `CRM`, `OAuth2 proxy` has told you what its areas are.
- **Directories in another language or with their own deploy path.** They have
  invariants no general reviewer knows and no shared test suite covers.

## 6. Land it

- **Standards-only commits, one concern each**, so the reasoning lives in the
  guidance's own history.
- **Update the indexes**: `AGENTS.md`'s skill and auditor tables, `CLAUDE.md`'s
  pointers, the PR template if the port brought a description skeleton, and any
  `.gitignore` entry a new workflow needs.
- **Validate the frontmatter** before committing — every `SKILL.md`'s `name`
  matches its directory, every agent's matches its filename, every file has a
  `description`. A mismatch means the skill silently never loads.
- **Expect the target's own commit gate to bite.** A repo with a pre-commit lint
  or security gate may be sitting on a pre-existing failure that blocks every
  commit, including a documentation-only one. That is the user's decision to
  make, not yours to route around — surface it with options and wait.
- **Subagents register at session start.** Newly added auditors are not
  dispatchable until a fresh session; say so rather than reporting them as
  broken.

## Anti-patterns

- Copying a skill wholesale and fixing the names — the facts underneath are the
  part that matters, and they're the part that doesn't survive translation.
- Porting an auditor with no paired standards skill in the target. It will invent
  rules. (The generalist auditor is the sole deliberate exception.)
- Duplicating a rule into both the skill and its auditor.
- Asserting a capability the target lacks because the source had it.
- Doing the whole port on `main`, or on a branch nobody agreed to.
- Leaving the source repo's newer sibling deltas unmentioned when the target's
  copy is actually ahead.
