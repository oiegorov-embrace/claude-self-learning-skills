---
description: Run the self-learning skills curator - merge overlapping personal skills in ~/.claude/skills, keeping old names reachable via aliases and REDIRECTS.md. Use when the user asks to curate or merge skills, or from a weekly scheduled task.
disable-model-invocation: true
allowed-tools: Bash, Agent
---

Run the weekly curator for my personal Claude Code skill library and report the result.

0. Inside the Claude desktop app (the env var `CLAUDE_CODE_DESKTOP_APP_VERSION` is set, and `SKILL_REVIEW_RUNNER` is not `cli`), use the agent runner instead of step 1, so the curator uses this session's sign-in and no `claude -p`:
   1. Run `CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/curate.sh" --prepare`. It prints one line: a log path, `SKIPPED` (fewer than two skills: reply "Skipped: fewer than two skills" and stop) or `BUSY` (another curator runs: say so and stop).
   2. Call the Agent tool once, in the foreground: subagent_type `self-learning-skills:skill-reviewer`, description `Skill curator`, and the prompt `Input: <log>.prompt.txt` and `Output: <log>.answer.md` on two lines. The model comes from the agent; pass `model` only when `CURATOR_MODEL` is set (`opus`, `sonnet`, `haiku` or `fable`).
   3. Run `CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/curate.sh" --apply <log>`. It prints the summary. Then go to step 2 below.
1. Otherwise run: `CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/curate.sh"` (it can take up to ~2 minutes; use a timeout of at least 300000 ms). If it says the library is not a git repo, tell the user to run /self-learning-skills:setup and stop. Do not edit the script or the skills yourself — the script does all the work: it asks a tool-less Claude which skills in ~/.claude/skills overlap, then merges them, archives the retired folders in ~/.claude/skills/.archive/, adds "Formerly: <old-name>" aliases, appends to ~/.claude/skills/REDIRECTS.md, commits to git, and calls ~/.claude/skill-review/on-skill-redirect if it exists.
2. Find what happened, newest first, in `${CLAUDE_PLUGIN_DATA}/logs/` (files named `<timestamp>-curator.*`):
   - a `.skipped` file means there were fewer than two skills, so nothing to curate;
   - otherwise read the `.err` file for problems, and `git -C ~/.claude/skills log --oneline -5` for any "(curator)" merge commits made in this run.
   Do not read or empty `${CLAUDE_PLUGIN_DATA}/notices.pending` — the user's next message picks those notes up.
3. Reply in at most three short lines: which skills were merged into which (or "No merges needed" / "Skipped: fewer than two skills"), plus any error with the log file path.