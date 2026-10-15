---
description: Set up the self-learning skills library (~/.claude/skills as a git repository). Use once after installing the self-learning-skills plugin, or when the session start note says "SETUP NEEDED".
disable-model-invocation: true
---

Set up the skill library for the self-learning-skills plugin.

1. Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-library.sh"`
2. If it prints `No git identity`, ask the user which name and email the skill library commits should use, then run:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-library.sh" --git-name "<name>" --git-email "<email>"`
3. If the last line lists read-only skills, show them to the user and explain: the reviewer and the curator change only skills marked `created-by: self-learning-skills`; the others stay as they are. Ask which of them this system created or may manage (for example after a move from a manual install). For the ones the user names, run:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-library.sh" --adopt <name>,<name>` (or `--adopt all`). Adopt nothing the user did not name.
4. Tell the user in two lines: the library path and that background reviews start from the next session. Mention that `/self-learning-skills:curate` merges overlapping skills, and that it can be scheduled weekly.

The script never changes existing skills, except the ones adopted with `--adopt` (it adds the marker to their frontmatter). It only creates `~/.claude/skills` if needed, adds `README.md` and `REDIRECTS.md` if they are missing, makes the folder a git repository and commits.
