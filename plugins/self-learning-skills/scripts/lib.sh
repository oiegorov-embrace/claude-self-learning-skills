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

# Reviews and merges commit to the library, so they wait until it is inside a git work tree.
# That can be its own repo or a bigger one (for example a versioned ~/.claude).
library_ready() { [ -d "$SKILLS" ] && [ "$(git -C "$SKILLS" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; }

# Who runs the reviewer and the curator. "agent": a background subagent of the current session
# (agents/skill-reviewer.md), so it uses the session's own sign-in. "cli": a headless `claude -p`,
# which needs its own CLI sign-in. Default: agent inside the Claude desktop app, cli elsewhere.
# Override with SKILL_REVIEW_RUNNER=agent|cli in the env of settings.json.
runner() {
  case "${SKILL_REVIEW_RUNNER:-}" in
    agent|cli) echo "$SKILL_REVIEW_RUNNER" ;;
    *) [ -n "${CLAUDE_CODE_DESKTOP_APP_VERSION:-}" ] && echo agent || echo cli ;;
  esac
}

# The Agent tool takes a model alias, not a model id.
agent_model() {
  case "$1" in *haiku*) echo haiku ;; *sonnet*) echo sonnet ;; *fable*) echo fable ;; *) echo opus ;; esac
}

# Apply the reviewer answers that background subagents wrote since the last hook run
# (agent runner). A pending review is "<state>/<sid>.pending" holding its log path; the
# subagent writes "<log>.answer.md". One that has no answer after 3 hours is dropped
# with a note. Called by the Stop and UserPromptSubmit hooks.
apply_pending() {
  local p log
  for p in "$STATE"/state/*.pending; do
    [ -f "$p" ] || continue
    log=$(cat "$p")
    if [ -s "$log.answer.md" ]; then
      apply_review "$log" "$log.answer.md"
    elif [ -n "$(find "$p" -mmin +180 2>/dev/null)" ]; then
      echo "$(date '+%Y-%m-%d %H:%M')	Background skill review did not finish (no answer in 3 hours); see $log.prompt.txt" >>"$STATE/notices.pending"
    else
      continue
    fi
    rm -f "$p"; rmdir "${p%.pending}.lock" 2>/dev/null
  done
}

# Apply one reviewer answer (claude -p JSON or the subagent's Markdown) and queue the note.
apply_review() {   # <log prefix> <answer file>
  local summary
  if summary=$(/usr/bin/python3 -I "$CODE/apply-changes.py" "$2" "$SKILLS" 2>>"$1.err"); then
    [ "$summary" != "Nothing to save." ] && echo "$(date '+%Y-%m-%d %H:%M')	$summary" >>"$STATE/notices.pending"
  else
    echo "$(date '+%Y-%m-%d %H:%M')	Background skill review failed; see $1.err" >>"$STATE/notices.pending"
  fi
  return 0
}
