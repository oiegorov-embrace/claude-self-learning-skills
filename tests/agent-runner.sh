#!/bin/bash
# Offline test of the agent runner (the desktop default): the Stop hook only records sessions,
# the daily batch builds index prompts in parts and applies the subagents' answers, the curator
# splits into --prepare and --apply, and the guard hook confines the subagent.
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

# Two sessions; the Stop hook only records them.
T2="$H/transcript2.jsonl"
printf '{"type":"user","message":{"content":"no, use the short format"}}\n' > "$T2"
out=$(echo "$stop_input" | "$S/stop-hook.sh"); echo "$(jq -nc --arg t "$T2" '{session_id:"s2", transcript_path:$t}')" | "$S/stop-hook.sh" >/dev/null
ok "stop hook records only: no output, no lock" '[ -z "$out" ] && [ -f "$DATA/state/s1.tp" ] && [ -f "$DATA/state/s2.tp" ] && [ ! -e "$DATA/state/s1.lock" ]'

mkdir -p "$H/.claude/skills/demo-skill"; printf -- '---\nname: demo-skill\ndescription: demo steps\nmetadata:\n  created-by: self-learning-skills\n---\nStep 1.\n' > "$H/.claude/skills/demo-skill/SKILL.md"
git -C "$H/.claude/skills" add -A; git -C "$H/.claude/skills" commit -q -m demo
logs=$(SKILL_REVIEW_PART_BYTES=10 "$S/batch-review.sh" --prepare)
log=$(echo "$logs" | head -1)
ok "prepare splits the two sessions into two parts" '[ "$(echo "$logs" | wc -l | tr -d " ")" = 2 ]'
ok "the prompt holds an index, not the library"  'grep -q "## demo-skill (managed)" "$log.prompt.txt" && grep -q "demo-skill/SKILL.md (" "$log.prompt.txt" && ! grep -q "^Step 1.$" "$log.prompt.txt"'
ok "the prompt holds the session text"          'cat $(echo "$logs" | sed "s/$/.prompt.txt/") | grep -q "no, use the short format"'
ok "prepare again says BUSY"                    '[ "$("$S/batch-review.sh" --prepare)" = BUSY ]'

# The guard: the reviewer reaches only its files and the library; the main thread is untouched.
ok "guard allows Read of the input"            '[ "$(guard self-learning-skills:skill-reviewer Read "$log.prompt.txt")" = allow ]'
ok "guard allows Read of a skill"              '[ "$(guard self-learning-skills:skill-reviewer Read "$H/.claude/skills/demo-skill/SKILL.md")" = allow ]'
ok "guard denies Read of the library git"      '[ "$(guard self-learning-skills:skill-reviewer Read "$H/.claude/skills/.git/config")" = deny ]'
ok "guard allows Write of the output"          '[ "$(guard self-learning-skills:skill-reviewer Write "$log.answer.md")" = allow ]'
ok "guard denies Write of a skill"             '[ "$(guard self-learning-skills:skill-reviewer Write "$H/.claude/skills/demo-skill/SKILL.md")" = deny ]'
ok "guard denies Bash"                         '[ "$(guard self-learning-skills:skill-reviewer Bash "")" = deny ]'
ok "guard denies Write elsewhere"              '[ "$(guard self-learning-skills:skill-reviewer Write "$H/.claude/settings.json")" = deny ]'
ok "guard denies Read elsewhere"               '[ "$(guard self-learning-skills:skill-reviewer Read "$H/.gitconfig")" = deny ]'
ok "guard denies a path escape"                '[ "$(guard self-learning-skills:skill-reviewer Write "$DATA/logs/../notices.answer.md")" = deny ]'
ok "guard ignores the main thread"             '[ "$(guard "" Bash "")" = none ]'
ok "guard ignores other subagents"             '[ "$(guard general-purpose Write "$H/x")" = none ]'

# Part 1 answers with an edit; part 2 gives no answer.
log2=$(echo "$logs" | sed -n 2p)
printf 'Review.\n<skill-changes>{"summary":"Updated demo-skill: step 2.","edits":[{"path":"demo-skill/SKILL.md","old":"Step 1.","new":"Step 1.\\nStep 2."}]}</skill-changes>\n' > "$log.answer.md"
res=$("$S/batch-review.sh" --apply "$log" "$log2")
ok "apply applies the edit and commits"        'grep -q "^Step 2.$" "$H/.claude/skills/demo-skill/SKILL.md" && git -C "$H/.claude/skills" log -1 --format=%s | grep -q "background review"'
ok "apply reports both parts"                  '[[ "$res" == *"Updated demo-skill"* && "$res" == *"No answer file"* ]]'
first=$(head -1 "$log.lines" | cut -d" " -f1); second=$(head -1 "$log2.lines" | cut -d" " -f1)
ok "answered sessions move, others stay"       '[ -f "$DATA/state/$first.line" ] && [ ! -f "$DATA/state/$second.line" ]'
ok "apply frees the lock"                      '[ ! -d "$DATA/batch.lock" ]'
out=$(echo '{}' | "$S/skill-learning-reminder.sh" | ctx)
ok "next message shows the notes"              '[[ "$out" == *"Updated demo-skill"* ]]'
ok "next prepare takes only the open session"  '[ "$("$S/batch-review.sh" --prepare | wc -l | tr -d " ")" = 1 ]'
rmdir "$DATA/batch.lock"
printf '<skill-changes>{"summary":"x","edits":[{"path":"demo-skill/SKILL.md","old":"Nope","new":"y"}]}</skill-changes>' > "$H/bad.answer.md"
ok "an edit whose old text is missing fails"    '! /usr/bin/python3 -I "$S/apply-changes.py" "$H/bad.answer.md" "$H/.claude/skills" 2>/dev/null'

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
rm -f "$DATA/state/s1.line" "$DATA/state/s1.lock" 2>/dev/null; out=$(echo "$stop_input" | SKILL_REVIEW_RUNNER=cli "$S/stop-hook.sh")
for i in $(seq 1 50); do [ -e "$STUB/claude-was-called" ] && break; sleep 0.1; done
ok "SKILL_REVIEW_RUNNER=cli uses claude -p"    '[ -z "$out" ] && [ -e "$STUB/claude-was-called" ]'

echo "$pass passed, $fail failed (test home: $H)"
[ "$fail" = 0 ]
