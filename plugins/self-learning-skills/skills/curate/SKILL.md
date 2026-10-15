---
description: Run the self-learning skills curator - merge overlapping personal skills in ~/.claude/skills, keeping old names reachable via aliases and REDIRECTS.md. Use when the user asks to curate or merge skills, or from a weekly scheduled task.
disable-model-invocation: true
allowed-tools: Bash
---

Run the weekly curator for my personal Claude Code skill library and report the result.

1. Run: `CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/curate.sh"` (it can take up to ~2 minutes; use a timeout of at least 300000 ms). If it says the library is not a git repo, tell the user to run /self-learning-skills:setup and stop. Do not edit the script or the skills yourself — the script does all the work: it asks a tool-less Claude which skills in ~/.claude/skills overlap, then merges them, archives the retired folders in ~/.claude/skills/.archive/, adds "Formerly: <old-name>" aliases, appends to ~/.claude/skills/REDIRECTS.md, commits to git, and calls ~/.claude/skill-review/on-skill-redirect if it exists.
2. Find what happened, newest first, in `${CLAUDE_PLUGIN_DATA}/logs/` (files named `<timestamp>-curator.*`):
   - a `.skipped` file means there were fewer than two skills, so nothing to curate;
   - otherwise read the `.err` file for problems, and `git -C ~/.claude/skills log --oneline -5` for any "(curator)" merge commits made in this run.
   Do not read or empty `${CLAUDE_PLUGIN_DATA}/notices.pending` — the user's next message picks those notes up.
3. Reply in at most three short lines: which skills were merged into which (or "No merges needed" / "Skipped: fewer than two skills"), plus any error with the log file path.