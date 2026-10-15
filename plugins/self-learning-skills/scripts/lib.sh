# Shared paths for the self-learning scripts; sourced, not run.
# Manual install (install.sh): scripts and state live in ~/.claude/skill-review
# (the reminder hook in ~/.claude/hooks). Plugin install: scripts live in the plugin,
# state in ${CLAUDE_PLUGIN_DATA}. The skill library is ~/.claude/skills in both cases.
CODE="$(cd "$(dirname "$0")" && pwd)"
SKILLS="${SKILLS_DIR:-$HOME/.claude/skills}"
case "$CODE" in
  "$HOME/.claude/hooks"|"$HOME/.claude/skill-review") MODE=manual; STATE="$HOME/.claude/skill-review" ;;
  *) MODE=plugin; STATE="${CLAUDE_PLUGIN_DATA:-}" ;;
esac

# The plugin steps aside when a manual install is also registered, so nothing runs twice.
manual_also_installed() {
  [ "$MODE" = plugin ] && grep -qsE 'skill-review/stop-hook\.sh|hooks/skill-learning-reminder\.sh' "$HOME/.claude/settings.json"
}

# Reviews and merges commit to the library, so they wait until it is a git repo.
library_ready() { [ -d "$SKILLS/.git" ]; }
