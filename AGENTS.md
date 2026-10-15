# AGENTS.md: install self-learning skills for the user

You are an AI agent. The user pointed you at this repository so that you set it up for them.
Follow these steps in order. README.md has the background and the design; you don't need it to install.
If you fetch this file, fetch the raw file (https://raw.githubusercontent.com/oiegorov-embrace/claude-self-learning-skills/main/AGENTS.md), not the GitHub page, so you get every command verbatim.

## What this installs (all in `~/.claude/`, for every project of this user)

| Part | Effect |
| --- | --- |
| Rules block in `~/.claude/CLAUDE.md` | Tells Claude to turn the user's corrections into skills in `~/.claude/skills/` and commit them. |
| `UserPromptSubmit` hook | Adds a one-line "skill check" note to each message, and passes on notes from background reviews. |
| `Stop` hook + background reviewer | After ~15 work steps, runs a tool-less `claude -p` reviewer in the background that may add or edit skills. **Costs about USD 0.25–0.40 per review with Opus.** |
| Weekly curator (optional schedule) | Merges overlapping skills; old names stay reachable through aliases and `REDIRECTS.md`. |
| `~/.claude/skills/` git repo | Every skill change is a commit, so it can be reviewed and reverted. |

## Step 1: get consent and two facts

Tell the user, in two or three lines, what the table above says, including the background cost and that `~/.claude/CLAUDE.md` gets a marked block. Ask:

1. "OK to install?" Stop if not.
2. "Which name and email should the skills git repo use?" Skip if `git config --global user.email` already prints one and the user is fine with it.
3. "Run the weekly curator? If yes, which day and time?" Default: Monday 10:00 local time.

## Step 2: check prerequisites

```bash
claude --version && jq --version && git --version && /usr/bin/python3 --version
```

Expected: four version lines and no error.

Platform: macOS or Linux. If something is missing, stop and tell the user what to install.

## Step 3: get the files

```bash
git clone https://github.com/oiegorov-embrace/claude-self-learning-skills.git
cd claude-self-learning-skills
```

## Step 4: install

```bash
./install.sh                                              # git identity already set globally
./install.sh --git-name "<name>" --git-email "<email>"    # otherwise
```

The script is idempotent. It backs up `settings.json`, `CLAUDE.md` and any existing hook scripts it replaces to `~/.claude/backups/`, keeps the user's other hooks, never overwrites existing skills, and puts its rules between `<!-- self-learning-skills:start -->` and `<!-- self-learning-skills:end -->` in `CLAUDE.md`.
If it prints `NOTE: ... already has a '## Self-learning skills' section`, an older manual install exists. The script then adds no marked block (the existing section already has the rules). Tell the user and leave that section as it is.
Don't edit `settings.json` or `CLAUDE.md` by hand.

## Step 5: verify

```bash
echo '{}' | ~/.claude/hooks/skill-learning-reminder.sh | jq -r .hookSpecificOutput.additionalContext   # expect text that starts with: Skill check (see 'Self-learning skills'
jq -r '.hooks | keys[]' ~/.claude/settings.json            # expect: Stop and UserPromptSubmit among them
git -C ~/.claude/skills log --oneline | head -3            # expect: at least one commit
grep -c 'self-learning-skills:start' ~/.claude/CLAUDE.md   # expect: 1; expect 0 only if step 4 printed the NOTE
```

## Step 6: schedule the weekly curator (only if the user said yes in step 1)

Use the day and time from step 1. Use the first option that you can do.

1. **You have a scheduled-task tool (Claude desktop app):** create a task named `weekly-skill-curator`, with the prompt from `dot-claude/scheduled-tasks/weekly-skill-curator/SKILL.md` (the text below its front matter) and the cron expression for the chosen time (default `0 10 * * 1`). It runs while the app is open, and a missed run starts when the app opens.
2. **Otherwise:** add this line to the user's crontab (`crontab -e`), with the chosen time:
   `0 10 * * 1 /bin/bash "$HOME/.claude/skill-review/curate.sh"`
3. **Neither is possible:** tell the user to run `~/.claude/skill-review/curate.sh` by hand now and then.

## Step 7: report to the user

Tell the user, briefly:

1. What you installed, and that it applies to all their Claude Code projects from the next session.
2. That background reviews cost about USD 0.25–0.40 each, and that `SKILL_REVIEW_MODEL=claude-sonnet-5-5` makes them cheaper.
3. Whether and when the curator runs.
4. How to undo a skill change: `git -C ~/.claude/skills revert <commit>`.
5. How to remove the system: `./install.sh --uninstall` (keeps skills and logs), then remove the curator schedule: delete the `weekly-skill-curator` scheduled task in the Claude app, or delete the `curate.sh` line with `crontab -e`.

## Rules for you

- Never write into `~/.claude/skills/synced/`; the claude.ai sync owns it.
- Never delete skills, logs or backups.
- Ask before anything not listed here.
- If a step's output differs from the expected output, stop and show the user the output.
