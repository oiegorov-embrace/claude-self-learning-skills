# AGENTS.md: install self-learning skills for the user

You are an AI agent. The user pointed you at this repository so that you set it up for them.
Follow these steps in order. README.md has the background and the design; you don't need it to install.
If you fetch this file, fetch the raw file (https://raw.githubusercontent.com/oiegorov-embrace/claude-self-learning-skills/main/AGENTS.md), not the GitHub page, so you get every command verbatim.

## What this installs

A Claude Code plugin, `self-learning-skills@self-learning-skills`, for all projects of this user.

| Part | Effect |
| --- | --- |
| `SessionStart` hook | Gives Claude the rules for turning the user's corrections into skills in `~/.claude/skills/`. |
| `UserPromptSubmit` hook | Adds a one-line "skill check" note to each message, and passes on notes from background reviews. |
| `Stop` hook + background reviewer | After ~15 work steps, runs a tool-less `claude -p` reviewer in the background that may add or edit skills. **Costs about USD 0.25–0.40 per review with Opus.** |
| `/self-learning-skills:setup` | One-time: makes `~/.claude/skills/` a git repository and asks which existing skills the system may manage. |
| Ownership | The system changes only skills marked `metadata: created-by: self-learning-skills`; others stay read-only. |
| `/self-learning-skills:curate` | On demand or scheduled: merges overlapping skills; old names stay reachable. |

The plugin does not edit `settings.json` or `CLAUDE.md`. Claude Code adds one `extraKnownMarketplaces` entry and one `enabledPlugins` entry. State lives in the plugin data folder, which Claude Code deletes on uninstall; the skill library stays.

## Step 1: get consent and two facts

Tell the user, in two or three lines, what the table above says, including the background cost. Ask:

1. "OK to install?" Stop if not.
2. "Which name and email should the skill library's git commits use?" Skip if `git config --global user.email` already prints one and the user is fine with it.
3. "Run the curator weekly? If yes, which day and time?" Default: Monday 10:00 local time.

## Step 2: check prerequisites

```bash
claude --version && jq --version && git --version && /usr/bin/python3 --version
```

Expected: four version lines and no error. Platform: macOS or Linux. If something is missing, stop and tell the user what to install.

## Step 3: detect an existing install (avoid running twice)

```bash
claude plugin list 2>/dev/null | grep -A4 'self-learning-skills@'
grep -E 'skill-review/stop-hook\.sh|hooks/skill-learning-reminder\.sh' ~/.claude/settings.json
```

- No output from either command → continue.
- The plugin is already enabled → skip to step 5.
- `grep` prints a line → a manual install (`install.sh`) exists. Tell the user; the plugin would stay inactive next to it. If the user wants the plugin, clone this repo and run `./install.sh --uninstall` first (it keeps skills and logs). Otherwise stop here.

## Step 4: install

```bash
claude plugin install self-learning-skills --marketplace oiegorov-embrace/claude-self-learning-skills
# expect: ✔ Successfully installed plugin: self-learning-skills@self-learning-skills (scope: user)
```

If it fails with a git/SSH error, retry with `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` set.

Then set up the skill library. A plugin skill can't run from a shell, so run the setup script from the installed plugin:

```bash
ROOT=$(claude plugin list --json | jq -r '.[] | select(.id=="self-learning-skills@self-learning-skills") | .installPath')
bash "$ROOT/scripts/setup-library.sh"                                            # git identity set globally
bash "$ROOT/scripts/setup-library.sh" --git-name "<name>" --git-email "<email>"  # otherwise
# expect: Skill library ready: <home>/.claude/skills (<n> commits).
```

If it prints `No git identity ... Nothing was changed.`, ask the user for a name and email and run the second form.

The last line lists read-only skills (no `created-by: self-learning-skills` marker). The reviewer and the curator never change those. Show the list to the user and ask which of them this system created or may manage (typical after a move from a manual install). Adopt only the ones the user names:

```bash
bash "$ROOT/scripts/setup-library.sh" --adopt <name>,<name>     # or --adopt all, only if the user says all
``` If `ROOT` is empty, tell the user to type `/self-learning-skills:setup` in their next Claude Code session instead.

**Fallback, only if plugins are blocked** (for example by organization policy): `git clone https://github.com/oiegorov-embrace/claude-self-learning-skills.git && cd claude-self-learning-skills && ./install.sh` (add `--git-name`/`--git-email` if asked). It merges into `settings.json` and `CLAUDE.md` (never replaces), writes through symlinks, is safe to rerun, and `--uninstall` removes only its own entries.

## Step 5: verify

```bash
claude plugin list | grep -A4 'self-learning-skills@'   # expect: Status: ✔ enabled
git -C ~/.claude/skills log --oneline | head -3          # expect: at least one commit
```

## Step 6: schedule the curator (only if the user said yes in step 1)

Use the day and time from step 1. Use the first option that you can do.

1. **You have a scheduled-task tool (Claude desktop app):** create a task named `weekly-skill-curator` with the prompt `/self-learning-skills:curate` and the cron expression for the chosen time (default `0 10 * * 1`). It runs while the app is open; a missed run starts when the app opens.
2. **Otherwise:** add a crontab line with the chosen time (keeps existing entries, adds no duplicate):
   ```bash
   LINE="0 10 * * 1 $(command -v claude) -p '/self-learning-skills:curate' --allowedTools Bash"
   crontab -l 2>/dev/null | grep -qF 'self-learning-skills:curate' || ( crontab -l 2>/dev/null; echo "$LINE" ) | crontab -
   crontab -l | grep curate   # expect: the line above, with the full path to claude (cron has a short PATH)
   ```
   For a manual install, use `/bin/bash "$HOME/.claude/skill-review/curate.sh"` as the command instead.
3. **Neither is possible:** tell the user to type `/self-learning-skills:curate` now and then.

## Step 7: report to the user

Tell the user, briefly:

1. What you installed, and that reviews start in their next Claude Code session.
2. That background reviews cost about USD 0.25–0.40 each, and that `SKILL_REVIEW_MODEL=claude-sonnet-5-5` in the `env` of `settings.json` makes them cheaper.
3. Whether and when the curator runs.
4. How to undo a skill change: `git -C ~/.claude/skills revert <commit>`.
5. How to remove it: `claude plugin uninstall self-learning-skills@self-learning-skills` (skills stay), then remove the schedule: delete the scheduled task in the Claude app, or `crontab -l | grep -vF 'self-learning-skills:curate' | crontab -`.

## Rules for you

- Never write into `~/.claude/skills/synced/`; the claude.ai sync owns it.
- Never delete skills, logs or backups.
- Don't edit `settings.json` or `CLAUDE.md` by hand.
- Ask before anything not listed here.
- If a step's output differs from the expected output, stop and show the user the output.
