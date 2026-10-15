#!/bin/bash
# UserPromptSubmit hook: reminds Claude of the self-learning skills rule in ~/.claude/CLAUDE.md
# each time the user sends a message (that's when corrections arrive), and passes on any
# notes the background skill reviewer (~/.claude/skill-review) left since the last message.
cat >/dev/null
[ "$SKILL_REVIEWER" = 1 ] && exit 0

ctx="Skill check (see 'Self-learning skills' in ~/.claude/CLAUDE.md): if this message corrects or extends how we do a recurring activity, update the matching skill in ~/.claude/skills, or create one if none exists; then commit and tell the user in one line. Otherwise ignore this note."

R="$HOME/.claude/skill-review"
if [ -s "$R/notices.pending" ] && mv "$R/notices.pending" "$R/notices.taking.$$" 2>/dev/null; then
  notes=$(cut -f2- "$R/notices.taking.$$")
  cat "$R/notices.taking.$$" >>"$R/notices.seen" && rm -f "$R/notices.taking.$$"
  ctx="$ctx

Background skill review ran since the user's last message. Tell the user in one line per item what changed:
$notes"
fi

jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
