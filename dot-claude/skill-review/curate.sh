#!/bin/bash
# Weekly skill curator (run by the Claude app scheduled task "weekly-skill-curator").
# Shows a headless, tool-less Claude the whole skill library, asks which skills overlap enough
# to merge, and applies the merges with apply-curation.py: survivor gets "Formerly: <old>"
# aliases, old folders go to .archive/, REDIRECTS.md gets a row, all committed, and
# on-skill-redirect (if executable) is called per old name, e.g. to tell Hindsight.
# Env overrides (for testing): SKILLS_DIR, NOTICES, CURATOR_MODEL, REDIRECT_HOOK.

BASE="$HOME/.claude/skill-review"
SKILLS="${SKILLS_DIR:-$HOME/.claude/skills}"
NOTICES="${NOTICES:-$BASE/notices.pending}"
MODEL="${CURATOR_MODEL:-claude-opus-5-5}"
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
log="$BASE/logs/$(date +%Y%m%d-%H%M%S)-curator"
mkdir -p "$BASE/logs"

mkdir "$BASE/curator.lock" 2>/dev/null || exit 0
trap 'rmdir "$BASE/curator.lock" 2>/dev/null' EXIT

# Fewer than two skills: nothing to merge, skip the model call.
count=$(cd "$SKILLS" && ls -d */SKILL.md 2>/dev/null | grep -v -e '^synced/' -e '^\.archive/' | wc -l | tr -d ' ')
[ "$count" -ge 2 ] || { echo "$(date) skipped: $count skill(s)" >"$log.skipped"; exit 0; }

{
  cat "$BASE/curator-prompt.md"
  echo
  echo "Today is $(date +%Y-%m-%d)."
  echo
  echo "<skill-library>"
  ( cd "$SKILLS" && for f in REDIRECTS.md */SKILL.md */references/* */templates/* */scripts/*; do
      [ -f "$f" ] || continue
      case "$f" in synced/*|.archive/*) continue ;; esac
      printf '\n=== FILE: %s ===\n' "$f"; head -c 20000 "$f"
    done ) | head -c 300000
  echo "</skill-library>"
} >"$log.prompt.txt"

SKILL_REVIEWER=1 "$CLAUDE_BIN" -p \
  --model "$MODEL" \
  --tools "" \
  --no-session-persistence \
  --output-format json \
  <"$log.prompt.txt" >"$log.json" 2>"$log.err"

if summary=$(/usr/bin/python3 -I "$BASE/apply-curation.py" "$log.json" "$SKILLS" "${REDIRECT_HOOK:-$BASE/on-skill-redirect}" 2>>"$log.err"); then
  [ "$summary" != "Skill curator: no merges needed." ] && echo "$(date '+%Y-%m-%d %H:%M')	$summary" >>"$NOTICES"
else
  echo "$(date '+%Y-%m-%d %H:%M')	Weekly skill curator failed; see $log.err" >>"$NOTICES"
fi
exit 0
