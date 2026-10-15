#!/bin/bash
# Stop hook: after a reply is delivered, count tool calls since the last skill review.
# When they reach the threshold, start a detached background reviewer and return at once.
# Modeled on Hermes Agent's skills.creation_nudge_interval + background review.

THRESHOLD="${SKILL_REVIEW_THRESHOLD:-15}"
BASE="$HOME/.claude/skill-review"

[ "$SKILL_REVIEWER" = 1 ] && exit 0   # never review the reviewer

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
tp=$(jq -r '.transcript_path // empty' <<<"$input")
[ -n "$sid" ] && [ -f "$tp" ] || exit 0

mkdir -p "$BASE/state" "$BASE/logs"
st="$BASE/state/$sid"
last=$(cat "$st.line" 2>/dev/null || echo 0)
total=$(wc -l <"$tp" | tr -d ' ')

# Tool calls in the main conversation since the last review, and whether any of them
# already edited the skill library (then the session did the work itself: reset, like Hermes).
read -r count touched < <(tail -n +"$((last + 1))" "$tp" | jq -R -n -r '
  [inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not))
   | .message.content[]? | select(.type == "tool_use")] as $t
  | ($t | length) as $n
  | ($t | map(
      ((.name == "Write" or .name == "Edit") and ((.input.file_path // "") | test("/\\.claude/skills/")))
      or (.name == "Bash" and ((.input.command // "") | test("\\.claude/skills.*commit"))))
    | any) as $s
  | "\($n) \($s)"')

if [ "$touched" = true ]; then
  echo "$total" >"$st.line"
  exit 0
fi
[ "${count:-0}" -ge "$THRESHOLD" ] || exit 0

mkdir "$st.lock" 2>/dev/null || exit 0   # a review for this session is already running
echo "$total" >"$st.line"
nohup "$BASE/run-review.sh" "$sid" "$tp" "$last" </dev/null >/dev/null 2>&1 &
exit 0
