# herdr-agents.sh — the agent CLIs purse knows about.
#
# Sourced by ~/.local/bin/purse-agent, ~/.local/bin/dcsh and
# ~/.config/shell/aliases.sh. Defines functions only, sets no shell options,
# and stays POSIX sh, so it is safe to source from bash, zsh, or a script
# under any flags.
#
# Three facts per agent, keyed by the command you type:
#
#   kind     the label herdr knows it by, from `herdr agent start --kind`.
#            Empty when herdr has no such agent — auggie, for one. Those
#            still get installed on first use; they just stay unlabelled.
#   install  the shell command that installs it. Empty when purse has no
#            recipe, which is most of them: an agent installed by hand or
#            baked into an image still gets wrapped, it just never gets
#            installed for you.
#   command  the name itself, which is not always the label. herdr calls
#            Cursor's CLI `cursor`, but the binary is `cursor-agent`.
#
# The npm packages here are the same ones `purse-install-agents` installs in
# bulk from .chezmoidata/packages.yaml. That script is the "outfit the whole
# machine now" door; this is the "outfit what I reached for" one.

# Every command we are willing to wrap. Order is display order.
purse_agent_commands() {
  echo "claude codex gemini cursor-agent agy auggie opencode copilot amp droid grok kimi hermes qoder qwen kiro kilo maki cline devin omp pi mastracode"
}

# The herdr agent label for a command, or nothing when herdr has no such agent.
purse_agent_kind() {
  case "$1" in
    cursor-agent) echo cursor ;;
    qoder)        echo qodercli ;;
    auggie)       echo "" ;;
    claude|codex|gemini|agy|opencode|copilot|amp|droid|grok|kimi|hermes|qwen|kiro|kilo|maki|cline|devin|omp|pi|mastracode)
                  echo "$1" ;;
    *)            echo "" ;;
  esac
}

# How to install a command, or nothing when purse has no recipe for it.
purse_agent_install_command() {
  case "$1" in
    claude)       echo "npm install -g --force @anthropic-ai/claude-code" ;;
    codex)        echo "npm install -g --force @openai/codex" ;;
    auggie)       echo "npm install -g --force @augmentcode/auggie" ;;
    opencode)     echo "npm install -g --force opencode-ai" ;;
    copilot)      echo "npm install -g --force @github/copilot" ;;
    cursor-agent) echo "curl https://cursor.com/install -fsS | bash" ;;
    agy)          echo "curl -fsSL https://antigravity.google/cli/install.sh | bash" ;;
    *)            echo "" ;;
  esac
}

# The commands purse can install unaided. These are the ones worth a host-side
# `dc<agent>` door, since a container can be sent to fetch any of them whether
# or not this machine has it.
purse_agent_installable_commands() {
  for _pa_cmd in $(purse_agent_commands); do
    [ -n "$(purse_agent_install_command "$_pa_cmd")" ] && echo "$_pa_cmd"
  done
  unset _pa_cmd
}

# The short name an agent goes by when it needs one word: herdr's label where
# there is one, the command itself otherwise. `cursor-agent` becomes `cursor`.
purse_agent_short_name() {
  _pa_kind="$(purse_agent_kind "$1")"
  if [ -n "$_pa_kind" ]; then echo "$_pa_kind"; else echo "$1"; fi
  unset _pa_kind
}

# The commands worth defining a shell wrapper for right now: the ones purse can
# install, plus any that are already here. Wrapping a name we can neither
# install nor find would replace the shell's own "command not found" with a
# worse message, so it stays unwrapped.
purse_agent_wrappable_commands() {
  for _pa_cmd in $(purse_agent_commands); do
    if [ -n "$(purse_agent_install_command "$_pa_cmd")" ] ||
       command -v "$_pa_cmd" > /dev/null 2>&1; then
      echo "$_pa_cmd"
    fi
  done
  unset _pa_cmd
}
