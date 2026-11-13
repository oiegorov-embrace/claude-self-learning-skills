#!/bin/bash
# PreToolUse hook. Inside the skill-reviewer subagent (agent runner), allow only a Read of a
# "<log>.prompt.txt" and a Write of a "<log>.answer.md" in the plugin's logs folder, and refuse
# every other call. So the subagent is as safe as the tool-less `claude -p` reviewer: text in a
# session cannot make it run a command or touch another file. Outside it, do nothing.
input=$(cat)
case "$input" in *skill-reviewer*) ;; *) exit 0 ;; esac
. "$(dirname "$0")/lib.sh"
agent=$(jq -r '.agent_type // empty' <<<"$input")
case "$agent" in skill-reviewer|*:skill-reviewer) ;; *) exit 0 ;; esac

decide() { jq -n --arg d "$1" --arg r "$2" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'; exit 0; }
tool=$(jq -r '.tool_name // empty' <<<"$input")
path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
logs=$(cd "$STATE/logs" 2>/dev/null && pwd -P) || decide deny "self-learning-skills: no logs folder"
dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)
name=$(basename "$path")
if [ "$dir" = "$logs" ] && [[ "$name" =~ ^[0-9A-Za-z._-]+$ ]]; then
  [ "$tool" = Read ] && [[ "$name" == *.prompt.txt ]] && decide allow "self-learning-skills: reviewer input"
  [ "$tool" = Write ] && [[ "$name" == *.answer.md ]] && decide allow "self-learning-skills: reviewer output"
fi
decide deny "self-learning-skills: the skill-reviewer may only Read its Input file and Write its Output file"
