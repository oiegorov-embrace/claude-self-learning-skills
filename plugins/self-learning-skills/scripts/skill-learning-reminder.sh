#!/bin/bash
# UserPromptSubmit hook: reminds Claude of the self-learning skills rules each time the user
# sends a message (that's when corrections arrive), and passes on any notes the background
# reviewer or the curator left since the last message.
cat >/dev/null
. "$(dirname "$0")/lib.sh"
[ "$SKILL_REVIEWER" = 1 ] && exit 0
[ -n "$STATE" ] || exit 0
manual_also_installed && exit 0

ctx="Skill check (see the 'Self-learning skills' rules): if this message corrects or extends how we do a recurring activity, update the matching skill in ~/.claude/skills, or create one if none exists; then commit and tell the user in one line. Otherwise ignore this note."

R="$STATE"
if [ -s "$R/notices.pending" ] && mv "$R/notices.pending" "$R/notices.taking.$$" 2>/dev/null; then
  notes=$(cut -f2- "$R/notices.taking.$$")
  cat "$R/notices.taking.$$" >>"$R/notices.seen" && rm -f "$R/notices.taking.$$"
  ctx="$ctx

Background skill review ran since the user's last message. Tell the user in one line per item what changed:
$notes"
fi

jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
