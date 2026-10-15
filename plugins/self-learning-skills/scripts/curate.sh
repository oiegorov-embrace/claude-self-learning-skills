#!/bin/bash
# Weekly skill curator. Run by the plugin skill /self-learning-skills:curate (for example from a
# scheduled task), or directly for a manual install: ~/.claude/skill-review/curate.sh.
# Shows a headless, tool-less Claude the whole skill library, asks which skills overlap enough
# to merge, and applies the merges with apply-curation.py: survivor gets "Formerly: <old>"
# aliases, old folders go to .archive/, REDIRECTS.md gets a row, all committed, and
# on-skill-redirect (if executable) is called per old name, e.g. to tell Hindsight.
# Env overrides (for testing): SKILLS_DIR, NOTICES, CURATOR_MODEL, REDIRECT_HOOK.

. "$(dirname "$0")/lib.sh"
[ -n "$STATE" ] || { echo "CLAUDE_PLUGIN_DATA is not set; run this through /self-learning-skills:curate" >&2; exit 1; }
library_ready || { echo "The skill library $SKILLS is not a git repo yet; run /self-learning-skills:setup first" >&2; exit 1; }
NOTICES="${NOTICES:-$STATE/notices.pending}"
MODEL="${CURATOR_MODEL:-claude-opus-5-5}"
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
log="$STATE/logs/$(date +%Y%m%d-%H%M%S)-curator"
mkdir -p "$STATE/logs"

mkdir "$STATE/curator.lock" 2>/dev/null || exit 0
trap 'rmdir "$STATE/curator.lock" 2>/dev/null' EXIT

# Fewer than two skills: nothing to merge, skip the model call.
# Only skills created by self-learning-skills (metadata created-by marker) are curated.
managed=" $(/usr/bin/python3 -I "$CODE/ownership.py" list "$SKILLS" managed | tr '\n' ' ') "
count=$(echo $managed | wc -w | tr -d ' ')
[ "$count" -ge 2 ] || { echo "$(date) skipped: $count skill(s)" >"$log.skipped"; exit 0; }

{
  cat "$CODE/curator-prompt.md"
  echo
  echo "Today is $(date +%Y-%m-%d)."
  echo
  echo "<skill-library>"
  ( cd "$SKILLS" && for f in REDIRECTS.md */SKILL.md */references/* */templates/* */scripts/*; do
      [ -f "$f" ] || continue
      case "$f" in synced/*|.archive/*) continue ;; REDIRECTS.md) ;; *) [[ "$managed" == *" ${f%%/*} "* ]] || continue ;; esac
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

if summary=$(/usr/bin/python3 -I "$CODE/apply-curation.py" "$log.json" "$SKILLS" "${REDIRECT_HOOK:-$HOME/.claude/skill-review/on-skill-redirect}" 2>>"$log.err"); then
  [ "$summary" != "Skill curator: no merges needed." ] && echo "$(date '+%Y-%m-%d %H:%M')	$summary" >>"$NOTICES"
else
  echo "$(date '+%Y-%m-%d %H:%M')	Weekly skill curator failed; see $log.err" >>"$NOTICES"
fi
exit 0
