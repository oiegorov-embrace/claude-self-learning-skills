## Self-learning skills

I want my way of working captured as skills, so that when I hand you a task you approach it the way I would. You're not limited to a skill, but go through its steps as I do.

Personal skills live in `~/.claude/skills/<skill-name>/SKILL.md`. Never write into `~/.claude/skills/synced/`; it is overwritten by the claude.ai sync.

**When to create a skill.** You notice a distinct, specialized activity we're doing (not a one-off question), and I've corrected or steered how you do it, or it's clearly something I'll repeat. Create the skill on your own; don't wait for me to ask.

**When to update a skill.** You're working on an activity an existing skill covers, and I correct a step, add a new step, or reject part of the approach. Fold that into the skill at once: edit the steps themselves, don't just append notes. Keep the skill as one coherent procedure.

**How to write it.**
- Frontmatter: `name` (kebab-case) and a `description` that says what the activity is and when to use it, in the words I'd use to ask for it.
- Body: my approach as ordered steps, with the *why* behind each correction, so you can apply it to cases the skill doesn't spell out.
- End with a short `## Changelog` (date and one line per change).
- Keep it generic to the activity. Project-specific facts belong in memory or the project's CLAUDE.md, not in a skill.

**After every create or update:**
1. Commit it: `git -C ~/.claude/skills add -A -- . && git -C ~/.claude/skills commit -m "<skill>: <what changed>" -- .` (the `-- .` keeps the commit to the skill library when it sits inside a bigger repo).
2. Tell me in one line, e.g. "Updated skill `code-review`: added step to check migrations first." I'll say so if I disagree.

**Which skills are yours to change.** A skill this system created has `created-by: self-learning-skills` under `metadata:` in its frontmatter; add exactly that to every skill you create:
```
metadata:
  created-by: self-learning-skills
```
Skills without it were installed from elsewhere (by hand, from a team or a plugin). Read and use them, but don't edit, merge or rename them unless I ask for that skill by name.

**Don't** make a skill for trivia, a single fix, or something already covered. Extend the existing skill instead of making a near-duplicate.

**Background review.** A Stop hook runs a separate background reviewer after every ~15 work steps; it may create or patch skills on its own. When my message carries a "Background skill review" note, tell me in one line what it changed.

### Merging, renaming and retiring skills

Old skill names live on in my memory and in any external memory (e.g. Hindsight) that recalls "I used skill X". So a skill name must never just disappear:
- Merge or rename only when I ask, or in a dedicated curator pass (the weekly curator: `/self-learning-skills:curate` for a plugin install, `~/.claude/skill-review/curate.sh` for a manual install; it applies all the steps below automatically). Never during normal work or a background review.
- Move the old folder to `~/.claude/skills/.archive/<old-name>/`; never delete it.
- Add the old name to the surviving skill's `description` as an alias ("Formerly: review-investment-signals"), so a request in the old words still matches.
- Append `old-name → new-name (date, reason)` to `~/.claude/skills/REDIRECTS.md`.
- If an external memory is connected (Hindsight etc.), also store a note there: "Skill X was merged into Y on <date>; use Y."
- Whenever memory or I mention a skill that doesn't exist, check `REDIRECTS.md` before concluding it's gone.
