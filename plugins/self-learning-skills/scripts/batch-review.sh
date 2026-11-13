#!/bin/bash
# Daily skill review for the agent runner (the desktop default), in two calls from the skill
# /self-learning-skills:review, which a scheduled task starts once a day:
#   batch-review.sh --prepare           writes one prompt per part, prints each "<log>" on a line,
#                                       or NOTHING (no new session text) or BUSY (a run is open)
#   batch-review.sh --apply <log>...    applies each <log>.answer.md that the skill-reviewer
#                                       subagent wrote, moves the sessions' review positions,
#                                       prints one summary line per part, and frees the lock
# The prompt holds an index of the skill library, not the library: the subagent reads only the
# skills that it changes. That keeps the prompt small (the whole library was ~80% of it).
# Env: SKILL_REVIEW_PART_BYTES (session text per part, default 300000),
#      SKILL_REVIEW_SESSION_BYTES (newest text kept per session, default 120000).

. "$(dirname "$0")/lib.sh"
[ -n "$STATE" ] || { echo "CLAUDE_PLUGIN_DATA is not set; run this through /self-learning-skills:review" >&2; exit 1; }
library_ready || { echo "The skill library $SKILLS is not a git repo yet; run /self-learning-skills:setup first" >&2; exit 1; }
PART="${SKILL_REVIEW_PART_BYTES:-300000}"
PER="${SKILL_REVIEW_SESSION_BYTES:-120000}"
mkdir -p "$STATE/state" "$STATE/logs"
lock="$STATE/batch.lock"

if [ "${1:-}" = --apply ]; then
  shift; rc=0
  for log in "$@"; do
    if [ -s "$log.answer.md" ] && apply_review "$log" "$log.answer.md"; then
      while read -r sid line; do echo "$line" >"$STATE/state/$sid.line"; done <"$log.lines"
    else
      [ -s "$log.answer.md" ] || { echo "$(date '+%Y-%m-%d %H:%M')	Daily skill review: no answer in $log.answer.md; its sessions stay for the next run" >>"$STATE/notices.pending"; echo "No answer file $log.answer.md; its sessions stay for the next run"; }
      rc=1
    fi
  done
  rmdir "$lock" 2>/dev/null
  exit $rc
fi

[ "${1:-}" = --prepare ] || { echo "usage: batch-review.sh --prepare | --apply <log>..." >&2; exit 2; }
[ -n "$(find "$lock" -maxdepth 0 -mmin +180 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null   # left by a run that never finished
mkdir "$lock" 2>/dev/null || { echo BUSY; exit 0; }

index() {   # one block per skill: name, owner, description, files with sizes
  local managed d f desc
  managed=" $(/usr/bin/python3 -I "$CODE/ownership.py" list "$SKILLS" managed | tr '\n' ' ') "
  echo "Library root: $SKILLS"
  ( cd "$SKILLS" && for d in */; do
      d=${d%/}; f="$d/SKILL.md"
      case "$d" in synced|.archive) continue ;; esac
      [ -f "$f" ] || continue
      desc=$(awk '/^---/{n++; next} n==1 && /^description:/{sub(/^description:[ ]*/,""); print; exit}' "$f" | cut -c1-400)
      if [[ "$managed" == *" $d "* ]]; then echo; echo "## $d (managed)"; else echo; echo "## $d (READ-ONLY: not created by self-learning-skills)"; fi
      echo "description: $desc"
      # Only files that git tracks: a skill folder can hold a .venv or caches.
      git ls-files -- "$d" | while read -r x; do [ -f "$x" ] && echo "- $x ($(wc -c <"$x" | tr -d ' ') bytes)"; done
    done
    [ -f REDIRECTS.md ] && { echo; echo "=== FILE: REDIRECTS.md ==="; tail -c 20000 REDIRECTS.md; } )
}

header() {   # <part file>
  cat "$CODE/review-prompt.md"
  cat <<'TXT'

## This run: the daily batch (it overrides the sections above where they differ)

- You have two tools: Read and Write. A hook lets you read only the Input file and files in the
  skill library, and write only the Output file.
- The library section below is an INDEX, not the library. Before you change a file, Read it whole
  from the library root. Never return a change to a file that you did not read in this run.
- To change an existing file, return `edits`, not the whole file: each edit replaces one exact,
  unique piece of text. Return `files` (whole content) only for a new file.
- The transcript holds several sessions since the last daily review. Review each one. One summary
  line names every skill that you created or changed.
- Write your whole answer to the Output file, ending with the block:

<skill-changes>
{"edits": [{"path": "<skill>/SKILL.md", "old": "<exact text, unique in the file>", "new": "<replacement>"}],
 "files": [{"path": "<new-skill>/SKILL.md", "content": "<the whole new file>"}],
 "summary": "<one line>"}
</skill-changes>
TXT
  echo; echo "<skill-library-index>"; index; echo "</skill-library-index>"
  echo; echo "<transcript>"; cat "$1"; echo "</transcript>"
}

stamp=$(date +%Y%m%d-%H%M%S); n=0; logs=()
start_part() { n=$((n+1)); log="$STATE/logs/$stamp-batch-$n"; : >"$log.sessions"; : >"$log.lines"; logs+=("$log"); }
start_part
for t in "$STATE"/state/*.tp; do
  [ -f "$t" ] || continue
  sid=$(basename "$t" .tp); tp=$(cat "$t")
  [ -f "$tp" ] || { rm -f "$t"; continue; }
  last=$(cat "$STATE/state/$sid.line" 2>/dev/null || echo 0)
  total=$(wc -l <"$tp" | tr -d ' ')
  [ "$total" -gt "$last" ] || continue
  text=$(tail -n +"$((last + 1))" "$tp" | digest | tail -c "$PER")
  [ -n "$text" ] || { echo "$total" >"$STATE/state/$sid.line"; continue; }
  [ -s "$log.sessions" ] && [ $(( $(wc -c <"$log.sessions") + ${#text} )) -gt "$PART" ] && start_part
  printf '\n=== SESSION %s (%s) ===\n%s\n' "$sid" "$(basename "$(dirname "$tp")")" "$text" >>"$log.sessions"
  echo "$sid $total" >>"$log.lines"
done

if [ ! -s "${logs[0]}.sessions" ]; then rm -f "${logs[0]}".*; rmdir "$lock"; echo NOTHING; exit 0; fi
for log in "${logs[@]}"; do header "$log.sessions" >"$log.prompt.txt"; rm -f "$log.sessions"; echo "$log"; done
