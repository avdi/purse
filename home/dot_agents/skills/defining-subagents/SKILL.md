---
name: defining-subagents
description: >
  Define Claude Code subagents (.claude/agents/*.md) correctly — frontmatter
  fields, what tools a dispatched subagent actually gets, and above all how to
  give a subagent MCP tools (the mcpServers frontmatter declaration, which
  works around the Agent-tool MCP-inheritance gap). Use when writing or
  debugging a subagent definition, when a subagent "can't see" a tool it should
  have, or when wiring an MCP server (playwright, ripgrep, github, …) into an
  agent.
---

## Where subagents are defined

- Project: `.claude/agents/<name>.md`
- User: `~/.claude/agents/<name>.md`
- Inline at launch: `claude --agents '<json>'`

A Markdown file with YAML frontmatter + a body (the system prompt). Dispatched
via the Agent/Task tool by `name`, or set as the session agent with
`claude --agent <name>`.

## Frontmatter fields

```yaml
---
name: my-agent
description: One line — used for routing/discovery, so say when to use it.
tools: Bash, Read, Write, Skill, mcp__playwright__*   # omit to inherit ALL tools
mcpServers:                                            # see "MCP tools" below
  - playwright
model: opus            # optional; omit to inherit the parent's model
# permissionMode: plan # optional
---
```

- **`tools`** — comma-separated (or a YAML list). **Omit to inherit every
  tool.** An explicit list restricts to what's named. Accepts MCP patterns:
  `mcp__<server>`, `mcp__<server>__*`, or a fully-qualified tool name.
- Some tools are **never** available to subagents even if listed:
  `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode` (unless `permissionMode:
  plan`), `ScheduleWakeup`, `WaitForMcpServers`.
- **`mcpServers`** — a list; each entry is a bare server name (reference an
  already-registered server, sharing the parent's connection) or an inline
  `name: {config}` definition. This is the field that matters for MCP — see below.

## MCP tools: the thing that bites you

**A subagent dispatched via the Agent tool does not reliably inherit the
parent's MCP tools** — [claude-code#30280](https://github.com/anthropics/claude-code/issues/30280).
The docs say subagents inherit all tools including MCP; in practice, Agent-tool
dispatch doesn't propagate MCP config, and some orchestrated/child-session
harnesses additionally strip `ToolSearch` from subagents — so the
"`ToolSearch` loads `mcp__*` on demand" path is dead too. Symptom: your
subagent reports only `Bash, Read, Write, Skill, …` and no `mcp__*` tools, no
matter what its `tools:` line says.

**The fix: declare the server in the agent's OWN frontmatter.** That forces the
MCP config to propagate to that subagent:

```yaml
tools: Bash, Read, Write, Skill, mcp__playwright__*
mcpServers:
  - playwright        # bare name → shares the parent session's connection
```

Verified patterns (behavior varies by version/harness — confirm with a probe,
below):

| Pattern | Result |
|---|---|
| `mcpServers: [name]` (named ref) | ✅ Grants that server's tools **directly** — no `ToolSearch`, no cold-start race. The reliable pattern. |
| `mcpServers: [name]` with the tools **not** in `tools:` | ✅ Still granted — a named `mcpServers` ref isn't gated by the `tools:` allowlist. Listing `mcp__name__*` in `tools:` too is belt-and-suspenders. |
| `tools: "*"` (or omitting `tools:`) | Broad inherit (gets `ToolSearch`, `Agent`, `Edit`, …), but MCP only via the broken inheritance path → hits #30280. Not reliable for MCP, and over-broad. |
| `mcpServers: ["*"]` | ❌ Scope-dependent and unreliable — observed granting project-scope (`.mcp.json`) servers but not user-scope (`~/.claude.json`) ones. **Don't use `"*"`; name the servers.** |

**Least-privilege caveat — `mcpServers` grants the server's WHOLE toolset.**
Declaring `mcpServers: [github]` gives the subagent *every* `mcp__github__*`
tool (read *and* write — `merge_pull_request`, `delete_file`, `push_files`, …),
even if `tools:` lists only one of them: a named `mcpServers` ref is not
narrowed by `tools:`. So only add a server whose entire surface is acceptable
for that agent. `ripgrep` (5 read-only search tools) is safe to hand out
widely; `github` is not — for a narrow need (e.g. posting one PR comment),
prefer `Bash` + `gh` over granting the whole server.

Practical: since `Grep`/`Glob` may not exist as tools in a given build (a
subagent falls back to `Bash`), wiring `mcpServers: [ripgrep]` +
`mcp__ripgrep__*` into search-heavy agents gives them real structured search.

## Verify what a subagent ACTUALLY gets

Don't trust the frontmatter — probe it. Write a throwaway agent that reports its
own tools:

```markdown
---
name: probe
tools: Bash, Read, Write, Skill, mcp__playwright__*
mcpServers:
  - playwright
---
Report ONLY: (1) every tool identifier you can call; (2) do you have ToolSearch?
(3) list any mcp__playwright__* tools, or NONE. Do nothing else.
```

Dispatch it and read the report.

**Registry caveat:** the Agent tool's list of dispatchable agents is fixed at
**session start**. A newly-created or newly-edited agent file is **not** picked
up mid-session — you must start a fresh session for it to register. Two ways:

- Restart the interactive session **rooted in the directory that holds the
  agent file** (the registry scans the startup root's `.claude/agents/`).
- Or drive a fresh headless session from a script, which reads agent files
  fresh each invocation:

  ```bash
  claude -p "Use the Task tool to launch the 'probe' subagent with prompt \
    'Run your probe.'. Output its report verbatim." \
    --dangerously-skip-permissions --model claude-haiku-4-5-20251001
  ```

Note a stock `claude -p` and an orchestrated/child session (`CLAUDE_CODE_CHILD_SESSION=1`)
can grant subagents **different** tool sets — the child harness may strip
`ToolSearch`/MCP-inheritance that stock keeps. `mcpServers`-named refs work in
both, which is why they're the pattern to reach for.

## Gotchas checklist

- Subagent missing `mcp__*` tools → add `mcpServers: [server]` to its frontmatter.
- Editing an agent file but nothing changes → registry is frozen; restart / use `claude -p`.
- `Grep`/`Glob` absent → normal in some builds; use `Bash`/ripgrep MCP.
- Want all servers via `mcpServers: ["*"]` → don't; it's scope-dependent. Name them.
- Over-broad `tools: "*"` still won't reliably grant MCP (#30280) — name the server.
