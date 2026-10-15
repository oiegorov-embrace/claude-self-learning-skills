#!/bin/bash
# Stop hook: after a reply is delivered, count work steps since the last skill review.
# When they reach the threshold, start a detached background reviewer and return at once.
# Modeled on Hermes Agent's skills.creation_nudge_interval + background review.
# A work step = one model response that called at least one tool (parallel calls count once),
# like Hermes's tool-calling iterations. Every tool counts, MCP tools included, except the
# bookkeeping tools matched by IGNORE (the desktop app's task list and wrap-up, ToolSearch).

THRESHOLD="${SKILL_REVIEW_THRESHOLD:-15}"
IGNORE="${SKILL_REVIEW_IGNORE_TOOLS:-^(mcp__ccd_turn__.*|ToolSearch)$}"
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

# Work steps in the main conversation since the last review, and whether any tool call
# already edited the skill library (then the session did the work itself: reset, like Hermes).
# A response is stored as several transcript lines sharing one message.id, so steps are
# counted as distinct message ids.
read -r count touched < <(tail -n +"$((last + 1))" "$tp" | jq -R -n -r --arg ignore "$IGNORE" '
  [inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not))
   | {id: .message.id, tool: (.message.content[]? | select(.type == "tool_use"))}
   | select(.tool.name | test($ignore) | not)] as $w
  | ($w | map(.tool)) as $t
  | ($w | map(.id) | unique | length) as $n
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
