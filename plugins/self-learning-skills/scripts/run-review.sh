#!/bin/bash
# Background skill reviewer, started by stop-hook.sh. Builds a digest of the session,
# asks a headless, tool-less Claude for skill changes,
# applies them with apply-changes.py (which commits), and queues a one-line note
# that the UserPromptSubmit hook shows on the user's next message.
# Usage: run-review.sh <session_id> <transcript_path> <last_reviewed_line>

sid="$1"; tp="$2"; last="${3:-0}"
. "$(dirname "$0")/lib.sh"
MODEL="${SKILL_REVIEW_MODEL:-claude-opus-5-5}"
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
log="$STATE/logs/$(date +%Y%m%d-%H%M%S)-$sid"
trap 'rmdir "$STATE/state/$sid.lock" 2>/dev/null' EXIT

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

{
  cat "$CODE/review-prompt.md"
  echo
  echo "<skill-library>"
  managed=" $(/usr/bin/python3 -I "$CODE/ownership.py" list "$SKILLS" managed | tr '\n' ' ') "
  ( cd "$SKILLS" && for f in REDIRECTS.md */SKILL.md */references/* */templates/* */scripts/*; do
      [ -f "$f" ] || continue
      case "$f" in synced/*|.archive/*) continue ;; esac
      tag=""; case "$f" in REDIRECTS.md) ;; *) [[ "$managed" == *" ${f%%/*} "* ]] || tag=" (READ-ONLY: not created by self-learning-skills)" ;; esac
      printf '\n=== FILE: %s%s ===\n' "$f" "$tag"; head -c 20000 "$f"
    done ) | head -c 150000
  echo "</skill-library>"
  echo
  echo "<transcript>"
  echo "=== EARLIER IN THE SESSION (already reviewed; context only) ==="
  [ "$last" -gt 0 ] && head -n "$last" "$tp" | digest | tail -c 60000
  echo
  echo "=== NEW SINCE THE LAST REVIEW (review this) ==="
  tail -n +"$((last + 1))" "$tp" | digest | tail -c 200000
  echo "</transcript>"
} >"$log.prompt.txt"

SKILL_REVIEWER=1 "$CLAUDE_BIN" -p \
  --model "$MODEL" \
  --tools "" \
  --no-session-persistence \
  --output-format json \
  <"$log.prompt.txt" >"$log.json" 2>"$log.err"

if summary=$(/usr/bin/python3 -I "$CODE/apply-changes.py" "$log.json" "$SKILLS" 2>>"$log.err"); then
  [ "$summary" != "Nothing to save." ] && echo "$(date '+%Y-%m-%d %H:%M')	$summary" >>"$STATE/notices.pending"
else
  echo "$(date '+%Y-%m-%d %H:%M')	Background skill review failed; see $log.err" >>"$STATE/notices.pending"
fi
