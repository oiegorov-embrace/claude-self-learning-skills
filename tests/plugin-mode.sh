#!/bin/bash
# Offline test of the plugin scripts: a throwaway HOME, a throwaway plugin data folder, and a stub
# `claude` that returns a fixed reviewer answer (no model call, no real files touched).
# Checks: setup gate, setup, rules at session start, background review -> commit -> note,
# curator skip, state only in the data folder, and that the plugin steps aside for a manual install.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; PLUG="$REPO/plugins/self-learning-skills"
H=$(mktemp -d); DATA=$(mktemp -d); STUB=$(mktemp -d)
cat > "$STUB/claude" <<'EOF'
#!/bin/bash
cat >/dev/null
printf '%s\n' '{"result":"<skill-changes>{\"summary\":\"Created skill demo-skill (test).\",\"files\":[{\"path\":\"demo-skill/SKILL.md\",\"content\":\"---\\nname: demo-skill\\ndescription: test\\n---\\nStep 1.\\n\"}]}</skill-changes>"}'
EOF
chmod +x "$STUB/claude"
export HOME="$H" CLAUDE_PLUGIN_ROOT="$PLUG" CLAUDE_PLUGIN_DATA="$DATA" PATH="$STUB:$PATH" GIT_CONFIG_NOSYSTEM=1
unset SKILL_REVIEWER SKILLS_DIR
S="$PLUG/scripts"
pass=0; fail=0
ok() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty'; }

# A transcript with 16 work steps (one tool call per assistant message).
T="$H/transcript.jsonl"
for i in $(seq 1 16); do
  printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n' "$i"
done > "$T"
stop_input=$(jq -nc --arg t "$T" '{session_id:"s1", transcript_path:$t, stop_hook_active:false}')

out=$(echo '{}' | "$S/session-rules.sh" | ctx)
ok "before setup: rules + SETUP NEEDED note"   '[[ "$out" == *"## Self-learning skills"* && "$out" == *"SETUP NEEDED"* ]]'
echo "$stop_input" | "$S/stop-hook.sh"
ok "before setup: no review starts"            '[ ! -d "$DATA/state" ]'
"$S/setup-library.sh" >/dev/null 2>&1
ok "setup without git identity changes nothing" '[ ! -d "$H/.claude/skills" ]'
"$S/setup-library.sh" --git-name Test --git-email test@example.com >/dev/null
ok "setup makes the library a git repo"        '[ -d "$H/.claude/skills/.git" ] && [ -f "$H/.claude/skills/REDIRECTS.md" ]'
"$S/setup-library.sh" >/dev/null
ok "setup again: no new commit"                '[ "$(git -C "$H/.claude/skills" rev-list --count HEAD)" = 1 ]'
out=$(echo '{}' | "$S/session-rules.sh" | ctx)
ok "after setup: rules, no SETUP note"         '[[ "$out" == *"## Self-learning skills"* && "$out" != *"SETUP NEEDED"* ]]'

echo "$stop_input" | "$S/stop-hook.sh"
for i in $(seq 1 50); do [ -s "$DATA/notices.pending" ] && break; sleep 0.2; done
ok "review wrote a note in the data folder"    'grep -q "Created skill demo-skill" "$DATA/notices.pending"'
ok "review committed the new skill"            'git -C "$H/.claude/skills" log --oneline | grep -q "background review"'
out=$(echo '{}' | "$S/skill-learning-reminder.sh" | ctx)
ok "next message shows the note once"          '[[ "$out" == *"Skill check"* && "$out" == *"demo-skill"* ]] && [ ! -s "$DATA/notices.pending" ]'
"$S/curate.sh"
ok "curator skips with one skill (no model)"   'ls "$DATA"/logs/*-curator.skipped >/dev/null 2>&1'
ok "no state outside the data folder"          '[ ! -e "$H/.claude/skill-review" ] && [ "$(ls -A "$H/.claude")" = skills ]'

# A manual install is also registered: the plugin must step aside.
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.claude/skill-review/stop-hook.sh"}]}]}}\n' > "$H/.claude/settings.json"
out=$(echo '{}' | "$S/session-rules.sh" | ctx)
ok "with manual install: plugin says inactive" '[[ "$out" == *"Only the manual install runs"* && "$out" != *"## Self-learning skills"* ]]'
ok "with manual install: no reminder"          '[ -z "$(echo "{}" | "$S/skill-learning-reminder.sh")" ]'
rm -f "$DATA/state/s1.line"
echo "$stop_input" | "$S/stop-hook.sh"
ok "with manual install: no review"            '[ ! -f "$DATA/state/s1.line" ]'

echo "$pass passed, $fail failed (test home: $H)"
[ "$fail" = 0 ]
