# GitHub Actions as an agent host

Checked 2026-11. Tier 0 — your runner, your steps, no platform contract to
satisfy. The skill's main body treats tier 0 as free ("your devcontainer runs
unmodified"). That is true of the *toolchain*. It is not true of everything
else, because Actions differs from every platform in `platforms.md` on the one
axis the whole contract is built around.

## Actions has no snapshot, so the two phases collapse

Every other platform here snapshots a prepared disk and resumes it per session.
That is what makes `prepare` (expensive, network, once) worth separating from
`boot` (cheap, per-session, no network).

**An Actions run is always cold.** There is no snapshot to resume, so there is
no cheap phase. Both scripts run, in order, on every single run, and you pay
full network cost each time.

```yaml
- run: script/clouddev/prepare   # was "once per prebuild" — now every run
- run: script/clouddev/boot
- run: script/clouddev/verify
```

Consequences that invert the main body's advice:

- **The phase split stops being an optimization and becomes documentation.**
  Keep it — the scripts are shared with real platforms — but do not expect it
  to buy you anything here.
- **`prepare` output being world-readable matters less** (nothing is baked into
  a reusable image) **and run duration matters much more.** Caching moves from
  nice-to-have to the main lever: `actions/cache` for the bundle, the npm
  store, and Playwright browsers.
- **"Starting a process in `prepare`" stops being an anti-pattern** here
  specifically, because nothing is snapshotted away. Do not act on that. The
  scripts must stay correct for the platforms that *do* snapshot.

## Backing services: `services:` beats compose

Same finding as Copilot, for the same reason, and it applies to any Actions
job. A `services:` block is the services half of your compose file
transcribed, and the runner supplies health-gating for free:

```yaml
    services:
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping" --health-interval 5s --health-retries 10
```

Reach for `docker compose up` from inside the job only when you need something
`services:` cannot express (build context, depends_on ordering, volumes).

## The environment must be *proved*, not assumed

This is the transferable lesson, and it is sharper for agents than for CI.

**A broken environment does not stop an agent. It redirects one.** A test suite
that cannot connect to Postgres exits non-zero and a human reads the log. An
agent handed the same failure does not stop — it investigates, theorizes,
tries workarounds, edits config it should not touch, and burns a meaningful
fraction of a paid context window before concluding anything. The cost of a
broken environment is not a failed run. It is a *plausible-looking* run that
spent its budget on your infrastructure instead of the task.

Two rules follow.

### Prove the environment, not the code, before the agent starts

The tempting version is to run the project's own commit gate as a setup step.
Don't: it answers a question setup isn't asking. Build a fast task that proves
the *box* — see "Prove the box, not the code" in SKILL.md for why the two
questions have different owners and different costs.

```yaml
- name: Prove the environment can run the suite before the agent starts
  run: bundle exec rake smoke    # not `rake ci`
```

Select it for coverage of the moving parts: boot the app, serve one request,
render one view, exercise each external adapter once, run your own CI helper
scripts, and ask each linter for its version (a *missing* linter is an
environment fault; a lint *offense* is a code verdict that isn't yours to
render here). Ours: 42 seconds, against several minutes for the full gate.

Two things this buys:

1. **Attribution.** A machine that cannot run the suite redirects the agent
   into debugging your infrastructure, and everything it then does looks like
   the ticket failing. Proving the box up front converts an hour of
   misattributed flailing into a fast verdict that blames nobody's ticket.
2. **A statement you can put in the prompt.** "The environment was proved
   working before you started" lets you then say: *a failure you hit is a
   consequence of your own change.* But say precisely what was proved — if you
   skipped the full suite and the linters, tell the agent so, and tell it what
   to do when it meets a failure that predates it. An overclaim here is worse
   than no claim: the agent either wastes the run owning someone else's break
   or learns to distrust the whole preamble.

Make it an input so a latency-sensitive workflow (answering a human's question
in a thread) can skip it while the long unattended one keeps it.

### Install-and-prove, never install-and-hope

Every dependency installed for the agent's benefit gets driven once, in setup,
by a step whose failure is loud. The main body already calls *"claiming
capabilities `verify` doesn't check"* an anti-pattern; in Actions it
generalizes — the install succeeding is not evidence the thing works, only
using it is.

But **resist putting the install in the workflow.** The pull is strong, because
Actions is where you noticed the gap. Wiring a browser into your CI config gets
*Actions* a browser. Declaring `browser` in `capabilities:`, installing it in
`prepare` and driving a page with it in `verify`, gets **every** platform one —
and gets the honest answer recorded on the platforms where it does not work.

```yaml
# clouddev.yml
capabilities: [test, serve, browser]
```

The workflow then needs no browser step at all; it already calls `prepare` and
`verify`. This is the platform-identification trap from the main body wearing
its most persuasive disguise: not a `CLOUDDEV_PLATFORM` branch, just a step in
one platform's config that quietly makes the capability list a lie everywhere
else.

## Playwright specifically

Browser builds are pinned per Playwright revision, and Playwright's CLI looks
for one exact build number. Two independently resolved Playwright versions —
say `npx playwright install` alongside an MCP server that bundles its own —
disagree about which build to look for, and the failure reads
`browser distribution is not found at <path>` even though a browser is
installed.

**Install through the consumer's own bundled CLI**, so the installer and the
runtime are the same copy:

```bash
npm install -g "@playwright/mcp@${PINNED}"
cli="$(npm root -g)/@playwright/mcp/node_modules/playwright/cli.js"
node "$cli" install chromium
```

Pin the version. An unpinned global npm install silently changes the browser
revision under you.

`--with-deps` apt-installs Chromium's shared libraries and therefore needs
root, which a devcontainer user usually is not — and usually does not need,
having got the libraries from the image. Split it rather than requiring root:
run `install-deps` only when you are root or `sudo -n` works, then `install`
unconditionally, and let the proof step decide whether the result is usable.

To *test* for the browser, note that `playwright install --dry-run` prints the
install location whether or not it is there. It yields a path to test, not a
verdict to trust.

Wiring it to Claude Code in Actions: `claude-code-action@v1` has **no
`mcp_config` input**. It goes through `claude_args`:

```yaml
claude_args: |
  --allowedTools "Read,Write,Edit,Bash,mcp__playwright"
  --mcp-config '{"mcpServers":{"playwright":{"command":"playwright-mcp",
    "args":["--browser","chromium","--headless","--isolated","--no-sandbox"]}}}'
```

The binary is `playwright-mcp`. `--isolated` keeps the profile in memory,
which is what you want on a throwaway runner. Smoke-test a stdio MCP server
without an agent by piping three JSON-RPC lines (`initialize`, the
`initialized` notification, `tools/list`) into it and grepping for tool names.

Whether a missing browser should fail `doctor` follows from the capability
list, not from taste: once `browser` is declared, it is a real check like any
other. If the project genuinely cannot support it, remove the capability —
an advisory is how a capability list starts drifting from the truth.

## Headless agent lifecycle — where unattended runs actually die

Not strictly environment, but it is what an Actions agent host fails on, and
none of it appears in the interactive documentation.

### Waiting is the same as quitting

The single most expensive failure. An agent that dispatches a background
subagent and then says *"I'll wait for its findings"* — scheduling a wakeup —
is using an **interactive-session** pattern. In a headless run there is no loop
to wake it. The process exits with the work undone and reports **success**.

Guidance written for interactive sessions actively invites this: any
"dispatch your reviewers in parallel" instruction is a trap here. Defend three
ways, because no one of them is sufficient:

1. Tell it in the prompt that background work and waiting end the run.
2. Forbid the wakeup tool explicitly.
3. Check, after the fact, that the run left a trace.

### `--allowedTools` is not a whitelist

Observed: an agent used two tools that appeared nowhere in `--allowedTools`,
with a permission-denial count of zero. The flag governs *prompting*, not
capability. To actually forbid something you need `--disallowedTools`.

### Success is not evidence of work

A headless run can report `subtype: success` having written no file, pushed no
branch, and left no comment. Assert on the artifact instead:

- The action suppresses transcripts by default (`full output hidden for
  security`). Use its `execution_file` **output** rather than guessing the path.
- Upload that as an artifact. To keep the logs safe to read, emit a
  content-free trace — tool *names* and the model's own first lines, never
  arguments or results.
- Add an explicit check that the run reached a real **ending**: a pushed
  branch, a closure, or a blocked-for-human label. A posted plan is not work.

### Watching a run in flight, without publishing its contents

`show_full_output: true` is the documented answer and the wrong one. In
`claude-code-action` it is literally binary:

```ts
if (showFullOutput) return JSON.stringify(message, null, 2);
// otherwise: only `init` and a sanitized `result` survive
```

So it publishes every tool result — file contents, command output, anything
the run minted — into a log your whole org can read. Actions redacts only
registered secrets by exact match, so a token the workflow created for itself
is not covered.

Tail the session file instead. Claude Code appends as it works, before the
action writes `execution_file`:

```
~/.claude/projects/<cwd-slug>/<session-id>.jsonl
~/.claude/projects/<cwd-slug>/<session-id>/subagents/*.jsonl
```

Pipe it through the same content-free filter the post-run trace uses:

```bash
jq -r --unbuffered '
  select(.type == "assistant")
  | .message.content[]?
  | if .type == "tool_use" then "  tool  \(.name)"
    elif .type == "text" and (.text | length) > 0 then
      "  say   \(.text | split("\n")[0] | .[0:160])"
    else empty end'
```

Three practical notes: the session id isn't known until the `init` message, so
glob-and-wait rather than hardcode a path; `jq` needs `--unbuffered` or you'll
see nothing for minutes; and a backgrounded tail interleaves messily into the
agent step's own log, so run it as a concurrent step and reap it after.

The subagent files matter more than the top-level one — fan-out work (audit
rounds, reviews) is the most opaque part of a run and the part you're least
sure is happening.

### Two small ones that cost real time

- **YAML block scalars leak indentation into Markdown.** A multi-line comment
  body built inside `run: |` carries the block's leading spaces into the string,
  and GitHub renders anything indented four spaces as a code block. Build the
  body with `printf '%s\n' "line" "" "line"` instead.
- **`gh issue comment` refuses a PR number.** If a trigger can fire on either,
  use `gh api repos/{repo}/issues/{n}/comments`, which accepts both.

## Private plugin/skill marketplaces

Agent guidance factored into a private repo has to be reachable from the
runner. The GitHub App that provides the agent integration does **not** help:
it is installed on the repo being worked, not the repo holding the guidance,
and the agent CLI clones marketplaces through **git credential helpers**, not
through the App.

Working routes, in preference order:

1. **Mint an installation token** from an App installed on the guidance repo.
   Short-lived, no human in the loop.
2. **A PAT with read access.** Simple; rotates manually.

Configure whichever you got as a git credential, then install:

```bash
git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf \
  "https://github.com/"
```

Two things worth knowing:

- **Support both routes and degrade politely.** A credential that is absent or
  expired should short-circuit the workflow *before* it starts a paid agent,
  not fail mid-run. Gate on "is one of these usable", not "is one configured".
- **The action may replace your CLI.** `claude-code-action` installs its own
  build over the one you installed and logs `No plugins specified, skipping
  plugins installation`. It picks the plugins up anyway via **user-scope**
  `~/.claude/settings.json`, which it reads and preserves — so install plugins
  to user scope, and treat your own verification step as a check on setup
  rather than proof about the binary that ultimately runs.

## An ephemeral runner needs continuous persistence

A hosted runner's disk is destroyed when the job ends, so any work that has
not left the box does not exist. The usual shape — work for an hour, push at
the end — means **anything that stops the run early costs the entire run**.
Runs stop early often: credit exhaustion, job timeout, cancellation, a model
that simply halts.

Persist on two channels that fail independently:

- **Code → git.** Push the branch the moment it is created and again at every
  step. Frame it in the prompt as *a push is a checkpoint, not a publication*,
  or the model will hold work back waiting for a tidy history.
- **Knowledge → the issue/PR, via the REST API.** A run also buys findings,
  decisions, and dead ends that no diff records. Append them to a single
  rolling comment (read-modify-write; roll over near the 65,536-char cap).
  Give the model a `note-progress`-style helper rather than the raw API calls.

The second channel is not redundancy — it is the only one that survives a
**refused push**, which is a real and common failure. Give the model a command
it can pipe Markdown into and tell it what is worth recording: validity
verdicts, reasoning, open questions, and above all dead ends, which are the
most expensive thing for a fresh run to rediscover. Explicitly exclude files
changed and commands run; git and the run log already have those.

Then add a workflow-level `if: always()` salvage step — in the *workflow*, not
the prompt, so a run that has stopped thinking still gets it: commit the dirty
tree, rebase onto the default branch, push, and upload a `git bundle` artifact
regardless. The bundle is the backstop that does not depend on the push
succeeding.

### Staleness makes the final push fail

The default branch moves while a long run works. The run's branch then still
carries the *older* copies of protected paths, and GitHub reads the push as
changing them — rejecting it for a change the agent never made. Seen in the
wild: a rejected push plus a dead account destroyed a completed, rebased,
pushable branch.

`git fetch origin <default> && git rebase origin/<default>` is the fix, since
the push then contains only the agent's own commits. **Do not "fix" it by
restoring the protected file from the default branch** — verified by probe,
`file_path_restriction` is evaluated per commit, not against the net tree, so
a commit that restores a protected file to byte-identical content is still
refused, and the branch is then unpushable until that commit is rewritten
away. Check for offending commits before attempting the push and fall back to
the artifact, rather than retrying something that cannot succeed.

### The salvage step, entire

Ordered so the cheap checks bail before the expensive ones, and so the bundle
is written even when the push is impossible.

```yaml
- name: Salvage whatever the run produced
  id: salvage
  if: ${{ always() && steps.agent.outcome != 'skipped' }}
  env:
    PROTECTED: .github script/ci-gate.sh AGENTS.md   # or CLAUDE.md — whatever
                                                     # your repo's canonical
                                                     # guidance file is
  run: |
    set -uo pipefail
    note() { echo "$*"; echo "$*" >> "$GITHUB_STEP_SUMMARY"; }

    branch=$(git rev-parse --abbrev-ref HEAD)
    case "$branch" in HEAD|main) note "No branch to salvage."; exit 0;; esac
    echo "branch=$branch" >> "$GITHUB_OUTPUT"

    git config user.name  "agent"
    git config user.email "agent@users.noreply.github.com"

    # --no-verify on purpose: the commit gate is a bar for work being
    # offered, not a reason to drop work on the floor. This is labelled WIP
    # and merges nothing.
    if [ -n "$(git status --porcelain)" ]; then
      git add -A
      git commit -q --no-verify -m "WIP: salvaged from run ${GITHUB_RUN_ID}" || true
    fi

    git fetch origin main --quiet || true
    [ -n "$(git log origin/main..HEAD --oneline)" ] || { note "No commits."; exit 0; }

    git rebase origin/main >/dev/null 2>&1 || git rebase --abort >/dev/null 2>&1 || true

    # Refuse to attempt a push that the ruleset will reject anyway.
    hits=$(git log origin/main..HEAD --name-only --pretty=format: -- $PROTECTED \
           | sort -u | grep -v '^$' || true)
    if [ -n "$hits" ]; then
      note "Commits touch fenced paths; cannot push:"; note "$hits"
    elif git push --force-with-lease -u origin "$branch" >/dev/null 2>&1; then
      note "Work is safe on \`$branch\`."
      echo "pushed=true" >> "$GITHUB_OUTPUT"
    else
      note "Push failed; the bundle artifact is the only copy."
    fi

    git bundle create "${RUNNER_TEMP}/salvage.bundle" HEAD --not origin/main >/dev/null 2>&1 \
      || git bundle create "${RUNNER_TEMP}/salvage.bundle" HEAD >/dev/null 2>&1 || true

- name: Keep the salvaged work
  if: ${{ always() && steps.agent.outcome != 'skipped' }}
  uses: actions/upload-artifact@v4
  with:
    name: salvage-${{ github.run_id }}
    path: ${{ runner.temp }}/salvage.bundle
    if-no-files-found: ignore
```

Recover with `git clone salvage.bundle` or `git fetch ../salvage.bundle`.

### The notebook, entire

Created *before* the model starts, so the agent has somewhere to write from
its first step. Give it a command rather than the API calls: a model asked to
hand-roll read-modify-write and a size ceiling will eventually drop a note.

```yaml
- run: |
    set -euo pipefail
    printf '%s\n' "🤖 Run in progress." "" "## Working notes" > "${RUNNER_TEMP}/nb.md"
    gh api "repos/${GITHUB_REPOSITORY}/issues/${ISSUE}/comments" \
      -F body=@"${RUNNER_TEMP}/nb.md" --jq .id > "${RUNNER_TEMP}/nb-id"

    mkdir -p "${RUNNER_TEMP}/bin"
    cat > "${RUNNER_TEMP}/bin/note-progress" <<'SH'
    #!/usr/bin/env bash
    set -euo pipefail
    state="${RUNNER_TEMP}/nb-id"; id=$(cat "$state")
    incoming=$(cat); [ -n "$incoming" ] || exit 0
    # A single note over the ceiling is rejected outright and lost — the one
    # outcome this mechanism exists to prevent. Truncate rather than drop.
    # An `if`, not `[ ] && x=`: under `set -e` a false test would exit here.
    if [ ${#incoming} -gt 50000 ]; then
      incoming="${incoming:0:50000}
    _(note truncated)_"
    fi
    current=$(gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" --jq .body)
    # A comment caps at 65536 chars; roll over early rather than lose the append.
    if [ $(( ${#current} + ${#incoming} )) -gt 60000 ]; then
      printf '%s\n\n%s\n' "## Working notes (continued)" "$incoming" > "${RUNNER_TEMP}/nb-next.md"
      gh api "repos/${GITHUB_REPOSITORY}/issues/${ISSUE}/comments" \
        -F body=@"${RUNNER_TEMP}/nb-next.md" --jq .id > "$state"
      exit 0
    fi
    printf '%s\n\n%s\n' "$current" "$incoming" > "${RUNNER_TEMP}/nb-next.md"
    gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" -X PATCH \
      -F body=@"${RUNNER_TEMP}/nb-next.md" --jq .id > /dev/null
    SH
    chmod +x "${RUNNER_TEMP}/bin/note-progress"
    echo "${RUNNER_TEMP}/bin" >> "$GITHUB_PATH"
```

`-F body=@file` rather than `--body "$str"`: note bodies contain backticks,
`$`, and newlines, and passing them as shell strings eventually mangles one.

Then, in the prompt — be specific, or it narrates:

> Append to the notebook at the end of every step:
> `printf '%s\n' "### Step 4 — dead end" "..." | note-progress`
> Record the verdict and its evidence, decisions and *why*, open questions,
> and above all **dead ends** — what you tried, what happened, why you
> abandoned it. Not files changed or commands run; git and the run log have
> those, and a wall of transcript buries the thinking it exists to keep.

Dead ends are the highest value per line: a fresh run's first instinct is to
retry exactly what already failed. One rolling comment, not one per
checkpoint — a chatty agent across thirty tickets is a thread nobody reads.

Lessons about the *project* rather than the ticket are a **proposal**, not an
edit. The instructions file is a fenced path (below), so the agent writes the
suggestion into the notes and the PR and a human promotes it. What every
future run must obey is not a call a single ticket gets to make.

## Fencing an agent that merges without review

An unattended runner that merges its own PR has no human diff review, so the
line it must not cross is: the agent may change the product, never the things
that judge the product — CI config, the composite action that provisions and
grades it, the pre-commit gate, the environment contract, its own
instructions file.

A caution in the prompt is not a guard. Put it where the agent cannot reach:

- **`GITHUB_TOKEN` is already refused `.github/workflows/**`** — *"refusing to
  allow a GitHub App to create or update workflow … without `workflows`
  permission"*. Free, and there is no `workflows:` key in a workflow
  `permissions:` block, so it cannot be granted by accident.
- **`.github/actions/**` is wide open by default.** This is the real hole: the
  composite action that installs the toolchain and runs the gate.
- **Close it with a push ruleset** (`target: push`, rule
  `file_path_restriction`). Available on **GitHub Team** for a private repo.
  Bypass actor `RepositoryRole` **id 5 = admin**; prefer it over
  `OrganizationAdmin`, since repo admins are often ordinary org members.
- **It holds because of the trigger.** For `issues`, `schedule`, and
  `workflow_dispatch` the workflow file is read from the **default branch**, so
  an agent editing the workflow on its own branch changes nothing about the run
  policing it.

Two traps, each worth a cycle:

- The pattern must be `.github/**/*`. **`.github/**` matches immediate children
  only** — and a push of a nested file is then reported as
  `file_path_restriction → result: "pass"`. The rule evaluates and *approves*,
  so a ruleset protecting nothing is indistinguishable from one that works.
- Therefore: **prove a path restriction with a real rejected push.** A throwaway
  workflow that tries `git push` one file at a time, printing ALLOWED/REFUSED,
  settles in a minute what the docs will not. Same instinct as `verify` — a
  capability you have not exercised is a capability you are guessing about.

Inspect evaluations with
`gh api repos/{owner}/{repo}/rulesets/rule-suites?time_period=hour`, then
`.../rule-suites/{id}` for the per-rule verdicts.

Still name the paths in the prompt — not as the guard, but so the agent meets
the boundary while planning rather than in a rejected push an hour of tokens
later.

## Concurrency: choose the lane per trigger, not per repo

Two workflows against the same repo wanted opposite models.

- **Unattended issue runner — one global lane.** `concurrency: agent-issue-runner`
  with no cancel. Only one agent should hold the repo at a time.
- **Interactive mention responder — one lane per issue.** Sharing the global
  lane looks tidier and is wrong: GitHub keeps only one *pending* run per
  group, so a second person's mention silently cancels the first person's
  unanswered question.

Where a global lane is genuinely needed but the concurrency group is the wrong
tool, use a **label as the interlock** (`agent-working`, applied on start and
removed in an `always()` cleanup). It survives across workflows, is visible to
humans, and can be inspected before starting.

## Reuse seam

The shared setup belongs in a **composite action**, not copied between
workflows:

```
.github/actions/prepare-agent/action.yml
```

It is the Actions equivalent of the clouddev entrypoints, and it is where the
environment work above belongs — services, toolchain, browser, credentials,
plugins, commit gate — with `inputs:` for the parts a caller varies (whether to
run the slow gate, which token, which plugin).

## The prompt itself

Everything above is harness. The worker prompt is the other half and the more
expensive one to get wrong, because its weaknesses surface as plausible-looking
runs rather than failures.

See `worker-prompt.md` for a complete annotated template — the eight-part
skeleton, what each section defends against, and the table of which concerns
must live in the harness because a prompt cannot enforce them.
