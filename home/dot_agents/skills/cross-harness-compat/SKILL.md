---
name: cross-harness-compat
description: >
  Write skills, agents, plugins and hooks that work under more than one
  harness (Claude Code, Copilot CLI, OpenCode). Covers *.agent.md naming,
  omitting model:, listing both mcp__server__* and server/* in tools:,
  harness-specific frontmatter, plugin dependencies, hook payload differences,
  and equipping OpenCode. Use when authoring or debugging a skill or agent
  that "works in one harness but not another", or when adding an MCP tool
  grant to an agent.
---

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

## Generating other harnesses from a Claude Code plugin (acplugin)

Write the plugin once in Claude Code format
(`plugins/<name>/.claude-plugin/plugin.json` plus a top-level
`.claude-plugin/marketplace.json`). Let `acplugin`
(`TokenRollAI/acplugin-action`) generate the Codex, OpenCode, Cursor and
Antigravity copies. Copilot reads the Claude format directly, so it is not a
target.

```yaml
- run: npm install -g @anthropic-ai/claude-code && claude plugin validate .
- uses: TokenRollAI/acplugin-action@v1
  with:
    platforms: codex,opencode,cursor,antigravity
    commit-message: 🔃 Regenerate cross-harness outputs
```

- **Validate first.** `claude plugin validate .` runs before conversion, so a
  broken source never gets converted.
- **Commit the output.** Cursor's Auto Refresh needs files in git, and
  OpenCode has no marketplace, so the directory is the install. The action
  auto-commits to `main`.
- **Sequence it.** If another workflow also pushes to `main` (a version
  stamper, say), trigger on `workflow_run` of that workflow. The action has
  no retry for a non-fast-forward push. A preflight `git diff --quiet
  HEAD~1 HEAD -- <paths>` skips runs where nothing relevant changed.
- **Never edit generated files.** Fix the Claude source and let the next
  run overwrite them.
- **Output layout.** Per-plugin trees land in flat top-level directories
  named after the plugin (`<plugin>/.opencode/`, `<plugin>/.agents/`,
  `<plugin>/.cursor-plugin/`, `<plugin>/.codex-plugin/`), next to the
  `plugins/<name>/` source. Don't confuse the two.
- **Known gaps (acplugin is v0.x).**
  - Every generated manifest says `version: "1.0.0"`. The real version
    lives in the Claude manifest.
  - `PostToolUse/Write|Edit` and `PreToolUse/Bash` hooks don't convert to
    Antigravity or OpenCode. Those harnesses skip them with a warning.
  - Codex hooks need the user to trust them with `/hooks` before they fire.
  - Generated agents all get OpenCode `mode: subagent`. To make one
    tab-selectable, edit `mode:` in the consumer's copy, or post-process in
    the workflow.
- **OpenCode still needs a copy step.** The generated tree is not in a
  discovery root. See the next section.

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
