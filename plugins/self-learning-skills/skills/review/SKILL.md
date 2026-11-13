---
description: Run the daily self-learning skill review - one skill-reviewer subagent per part reviews every session since the last run and updates personal skills in ~/.claude/skills. Use from the daily scheduled task, or when the user asks to run the skill review now.
disable-model-invocation: true
allowed-tools: Bash, Agent
---

Run the daily skill review and report the result. Do not edit skills yourself: the subagents
propose the changes and the script applies and commits them.

1. Run `CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/batch-review.sh" --prepare`.
   - If it prints `NOTHING`, reply "Skill review: no new session text." and stop.
   - If it prints `BUSY`, reply "Skill review: another run is open." and stop.
   - If it says the library is not a git repo, tell the user to run /self-learning-skills:setup and stop.
   - Otherwise each output line is a log path `<log>`.
2. For each `<log>`, call the Agent tool, all calls in one message so they run in parallel, in the
   foreground: subagent_type `self-learning-skills:skill-reviewer`, description `Skill review part N`,
   and the prompt `Input: <log>.prompt.txt` and `Output: <log>.answer.md` on two lines. Pass `model`
   only when `SKILL_REVIEW_MODEL` is set (`opus`, `sonnet`, `haiku` or `fable`).
3. Run `CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/batch-review.sh" --apply <log> <log>...`
   with every log path. Run it also when a subagent failed: it keeps those sessions for the next run
   and frees the lock.
4. Reply with its output lines, one per part, and nothing else.
