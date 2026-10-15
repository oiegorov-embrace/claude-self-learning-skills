#!/bin/bash
# SessionStart hook (plugin install only): gives Claude the self-learning skills rules at the
# start of each session and after compaction. A manual install keeps these rules in
# ~/.claude/CLAUDE.md instead, so this hook stays silent when one is registered.
cat >/dev/null
. "$(dirname "$0")/lib.sh"
[ "$SKILL_REVIEWER" = 1 ] && exit 0

if manual_also_installed; then
  ctx="Self-learning skills: two installs of the same system were found, the plugin and a manual install (install.sh) registered in ~/.claude/settings.json. Only the manual install runs. The plugin's hooks do nothing, so there are no double reviews. Tell the user once, in these words: 'The self-learning-skills plugin is switched off because the manual install is active. Keep one: to keep the plugin, run ./install.sh --uninstall in the claude-self-learning-skills repo; to keep the manual install, run claude plugin uninstall self-learning-skills@self-learning-skills.'"
else
  ctx=$(cat "$CODE/rules.md")
  if ! library_ready; then
    ctx="$ctx

SETUP NEEDED: the skill library $SKILLS is not a git repository yet, so background reviews are paused. Tell the user once to run /self-learning-skills:setup."
  fi
fi
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
