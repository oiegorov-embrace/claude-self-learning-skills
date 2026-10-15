---
description: Set up the self-learning skills library (~/.claude/skills as a git repository). Use once after installing the self-learning-skills plugin, or when the session start note says "SETUP NEEDED".
disable-model-invocation: true
---

Set up the skill library for the self-learning-skills plugin.

1. Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-library.sh"`
2. If it prints `No git identity`, ask the user which name and email the skill library commits should use, then run:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-library.sh" --git-name "<name>" --git-email "<email>"`
3. Tell the user in two lines: the library path and that background reviews start from the next session. Mention that `/self-learning-skills:curate` merges overlapping skills, and that it can be scheduled weekly.

The script never changes existing skills. It only creates `~/.claude/skills` if needed, adds `README.md` and `REDIRECTS.md` if they are missing, makes the folder a git repository and commits.
