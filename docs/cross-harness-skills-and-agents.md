# Skills and agents that work in more than one harness

Distilled from 410Labs/agent-infra's `docs/cross-runtime-agent-authoring.md`
(verified against vendor docs and real sessions, 2026-09/10). Check that file
for current detail; this is the short version for writing new skills and
agents anywhere.

## Skills

`SKILL.md` with `name` / `description` frontmatter is a shared standard.
Claude Code, Copilot CLI and OpenCode read it the same way. Write once.

OpenCode only looks in `.opencode/skills/`, `.claude/skills/`,
`.agents/skills/` (plus global equivalents). It does not read Claude Code's
plugin cache. A plugin installed for Claude Code gives OpenCode nothing, so
link or copy the skills into one of those directories.

## Agents

Name every agent file `<name>.agent.md`.

- Copilot skips a plain `*.md` agent file without an error.
- Claude Code matches by the `name:` field, so `.agent.md` works there too.

Do not set `model:`. Claude (`opus`, `sonnet`) and Copilot use different
value sets. Name a relative class (`fast`, `balanced`, `strongest`) in the
prompt and let the caller map it.

### `tools:` — list both spellings

Each harness silently ignores a name it does not know. A wrong name looks
fine and does nothing.

```yaml
# Claude Code uses mcp__<server>__*, Copilot uses <server>/*
tools: Read, Grep, Bash, mcp__ripgrep__*, ripgrep/*
```

| Concern | Claude Code | Copilot |
|---|---|---|
| Built-in tools | `Read, Grep, Bash, ...` | own aliases (`read`, `search`, `execute`); also accepts the Claude names |
| All tools of one MCP server | `mcp__server__*` | `server/*` |
| Declare an MCP server | `mcpServers:` (ignored for plugin-shipped subagents) | `mcp-servers:` (full config object; `stdio` is `local`) |

### Fields with no twin

Unknown keys are ignored, so a runtime-specific key is safe. The other
harness will not act on it.

- Claude only: `disallowedTools`, `permissionMode`, `hooks`, `maxTurns`,
  `skills`, `memory`, `background`, `effort`, `isolation`, `color`.
- Copilot only: `target`, `disable-model-invocation`, `user-invocable`,
  `metadata`.
- OpenCode: `mode: subagent | primary | all`. `subagent` hides the agent
  from the `/agents` switcher. It is a UI label, not a separate process.

## Plugins

- `"dependencies": ["baseline"]` in `plugin.json` works in Claude Code only.
  In Copilot, list every needed plugin in `enabledPlugins` yourself.
- Hooks load in both Claude Code and Copilot CLI (`hooks/hooks.json`).
  Event names match; payload fields differ (`tool_input.file_path` in
  Claude, `tool_input.path` in Copilot). Write the hook to read both.
- Agent Plugins 1.0 (Copilot) only makes skills and MCP config portable.
  Skip its `$schema` unless you want Copilot-specific agent paths.

## Equipping OpenCode (and other harnesses)

Run a script that symlinks the generated skills and agents into
`.opencode/`. agent-infra's `script/equip-agents` does this and is safe to
re-run, so call it from setup (devcontainer `postCreateCommand`, CI setup
step) and from the project's update script.

Check the result with `opencode debug agents`. It lists every loaded agent,
including `mode: subagent` ones.

## Verify

Reading the docs is not enough, because a bad name is ignored without a
message. Check each harness:

- Copilot: `/agent`
- OpenCode: `opencode debug agents`
- Claude Code: `/agents`
