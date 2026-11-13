#!/bin/bash
# Offline test of the agent runner (the desktop default): the Stop hook asks the session for a
# skill-reviewer subagent, the subagent's answer file is applied by the next hook run, the
# curator splits into --prepare and --apply, and the guard hook confines the subagent.
# No model call: the test writes the answer files itself. A stub `claude` fails the test if called.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; PLUG="$REPO/plugins/self-learning-skills"
H=$(mktemp -d); DATA=$(mktemp -d); STUB=$(mktemp -d)
printf '#!/bin/bash\ntouch "%s/claude-was-called"\nexit 1\n' "$STUB" > "$STUB/claude"; chmod +x "$STUB/claude"
export HOME="$H" CLAUDE_PLUGIN_ROOT="$PLUG" CLAUDE_PLUGIN_DATA="$DATA" PATH="$STUB:$PATH" GIT_CONFIG_NOSYSTEM=1
unset SKILL_REVIEWER SKILLS_DIR SKILL_REVIEW_RUNNER SKILL_REVIEW_MODEL
export CLAUDE_CODE_DESKTOP_APP_VERSION=test   # the desktop app: agent runner by default
S="$PLUG/scripts"
pass=0; fail=0
ok() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty'; }
guard() { jq -nc --arg a "$1" --arg t "$2" --arg p "$3" '{agent_type:$a, tool_name:$t, tool_input:{file_path:$p, command:"ls"}}' | "$S/reviewer-guard.sh" | jq -r '.hookSpecificOutput.permissionDecision' | grep . || echo none; }

"$S/setup-library.sh" --git-name Test --git-email test@example.com >/dev/null
T="$H/transcript.jsonl"
for i in $(seq 1 16); do
  printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n' "$i"
done > "$T"
stop_input=$(jq -nc --arg t "$T" '{session_id:"s1", transcript_path:$t, stop_hook_active:false}')

out=$(echo "$stop_input" | "$S/stop-hook.sh")
log=$(cat "$DATA/state/s1.pending" 2>/dev/null)
ok "stop hook blocks with an Agent request"    '[ "$(jq -r .decision <<<"$out")" = block ] && [[ "$(jq -r .reason <<<"$out")" == *"self-learning-skills:skill-reviewer"* ]]'
ok "the request names input, output and model" '[[ "$(jq -r .reason <<<"$out")" == *"Input: $log.prompt.txt"*"Output: $log.answer.md"* && "$(jq -r .reason <<<"$out")" == *"model \"opus\""* ]]'
ok "the prompt file holds the session"         'grep -q "NEW SINCE THE LAST REVIEW" "$log.prompt.txt"'
ok "a pending review and its lock exist"       '[ -d "$DATA/state/s1.lock" ]'
out2=$(echo "$stop_input" | "$S/stop-hook.sh")
ok "next stop: no second request"              '[ -z "$out2" ]'

# The guard: the reviewer reaches only its two files; the main thread is untouched.
ok "guard allows Read of the input"            '[ "$(guard self-learning-skills:skill-reviewer Read "$log.prompt.txt")" = allow ]'
ok "guard allows Write of the output"          '[ "$(guard self-learning-skills:skill-reviewer Write "$log.answer.md")" = allow ]'
ok "guard denies Bash"                         '[ "$(guard self-learning-skills:skill-reviewer Bash "")" = deny ]'
ok "guard denies Write elsewhere"              '[ "$(guard self-learning-skills:skill-reviewer Write "$H/.claude/settings.json")" = deny ]'
ok "guard denies Read elsewhere"               '[ "$(guard self-learning-skills:skill-reviewer Read "$H/.gitconfig")" = deny ]'
ok "guard denies a path escape"                '[ "$(guard self-learning-skills:skill-reviewer Write "$DATA/logs/../notices.answer.md")" = deny ]'
ok "guard denies Write of the input"           '[ "$(guard self-learning-skills:skill-reviewer Write "$log.prompt.txt")" = deny ]'
ok "guard ignores the main thread"             '[ "$(guard "" Bash "")" = none ]'
ok "guard ignores other subagents"             '[ "$(guard general-purpose Write "$H/x")" = none ]'

# The subagent writes its answer; the next message applies it.
printf 'Review.\n<skill-changes>{"summary":"Created skill demo-skill (agent).","files":[{"path":"demo-skill/SKILL.md","content":"---\\nname: demo-skill\\ndescription: test\\n---\\nStep 1.\\n"}]}</skill-changes>\n' > "$log.answer.md"
out=$(echo '{}' | "$S/skill-learning-reminder.sh" | ctx)
ok "next message applies and shows the note"   '[[ "$out" == *"Created skill demo-skill (agent)."* ]]'
ok "the answer was committed with the marker"  'git -C "$H/.claude/skills" log --oneline | grep -q "background review" && grep -q "created-by: self-learning-skills" "$H/.claude/skills/demo-skill/SKILL.md"'
ok "pending and lock are gone"                 '[ ! -e "$DATA/state/s1.pending" ] && [ ! -d "$DATA/state/s1.lock" ]'

# A review that never answers is dropped after 3 hours with a note.
echo "$DATA/logs/never" > "$DATA/state/s2.pending"; mkdir "$DATA/state/s2.lock"; touch -t 202001010000 "$DATA/state/s2.pending"
out=$(echo '{}' | "$S/skill-learning-reminder.sh" | ctx)
ok "an unanswered review is dropped with a note" '[[ "$out" == *"did not finish"* ]] && [ ! -e "$DATA/state/s2.pending" ] && [ ! -d "$DATA/state/s2.lock" ]'

# The curator in two calls.
mkdir -p "$H/.claude/skills/other-skill"; printf -- '---\nname: other-skill\ndescription: x\nmetadata:\n  created-by: self-learning-skills\n---\ny\n' > "$H/.claude/skills/other-skill/SKILL.md"
git -C "$H/.claude/skills" add -A; git -C "$H/.claude/skills" commit -q -m "second managed skill"
clog=$("$S/curate.sh" --prepare)
ok "curator --prepare prints a log and keeps the lock" '[ -s "$clog.prompt.txt" ] && [ -d "$DATA/curator.lock" ]'
ok "curator --prepare again says BUSY"         '[ "$("$S/curate.sh" --prepare)" = BUSY ]'
echo '<curation>{"merges":[]}</curation>' > "$clog.answer.md"
res=$("$S/curate.sh" --apply "$clog")
ok "curator --apply applies and frees the lock" '[[ "$res" == *"no merges needed"* ]] && [ ! -d "$DATA/curator.lock" ]'

# SKILL_REVIEW_RUNNER=cli switches back to claude -p even in the app.
rm -f "$DATA/state/s1.line"; out=$(echo "$stop_input" | SKILL_REVIEW_RUNNER=cli "$S/stop-hook.sh")
for i in $(seq 1 50); do [ -e "$STUB/claude-was-called" ] && break; sleep 0.1; done
ok "SKILL_REVIEW_RUNNER=cli uses claude -p"    '[ -z "$out" ] && [ -e "$STUB/claude-was-called" ]'

echo "$pass passed, $fail failed (test home: $H)"
[ "$fail" = 0 ]
