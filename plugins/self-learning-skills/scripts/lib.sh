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

# Who runs the reviewer and the curator. "agent": the skill-reviewer subagent (agents/
# skill-reviewer.md) of an app session, so it uses the app's own sign-in; reviews then run once a
# day for all sessions (batch-review.sh, started by /self-learning-skills:review from a scheduled
# task). "cli": a headless `claude -p` every SKILL_REVIEW_THRESHOLD work steps, which needs its own
# CLI sign-in. Default: agent inside the Claude desktop app, cli elsewhere.
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

# Apply one reviewer answer (claude -p JSON or the subagent's Markdown) and queue the note.
apply_review() {   # <log prefix> <answer file>
  local summary
  if summary=$(/usr/bin/python3 -I "$CODE/apply-changes.py" "$2" "$SKILLS" 2>>"$1.err"); then
    [ "$summary" != "Nothing to save." ] && echo "$(date '+%Y-%m-%d %H:%M')	$summary" >>"$STATE/notices.pending"
    echo "$summary"
  else
    echo "$(date '+%Y-%m-%d %H:%M')	Background skill review failed; see $1.err" >>"$STATE/notices.pending"
    echo "Background skill review failed; see $1.err"
    return 1
  fi
}

digest() {   # transcript lines on stdin -> readable conversation
  jq -R -r 'fromjson? | select(.isSidechain | not) |
    if .type == "user" then
      (.message.content | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end)
      | select(length > 0) | "USER: " + .[0:3000]
    elif .type == "assistant" then
      .message.content[]? |
      if .type == "text" then "CLAUDE: " + .text[0:2000]
      elif .type == "tool_use" then "  [tool " + .name + "] " + ((.input | tostring)[0:300])
      else empty end
    else empty end'
}
