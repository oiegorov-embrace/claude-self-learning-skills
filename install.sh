#!/bin/bash
# Installer for self-learning skills. Installs into ~/.claude (all projects of this user).
# Safe to run again: it replaces its own hook entries and its own CLAUDE.md block instead of
# adding duplicates, never overwrites your skills, and backs up settings.json, CLAUDE.md and
# any changed hook scripts it replaces.
#
# Usage:
#   ./install.sh                                   install or update
#   ./install.sh --git-name "Name" --git-email e   identity for the skills git repo, if git has none
#   ./install.sh --uninstall                       remove the hooks and the CLAUDE.md block
#                                                  (keeps your skills, scripts and logs)
# The weekly curator schedule is not set here; see AGENTS.md step 6.
set -euo pipefail

GIT_NAME="" GIT_EMAIL="" UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --git-name) GIT_NAME="$2"; shift 2 ;;
    --git-email) GIT_EMAIL="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

for c in claude jq git; do command -v "$c" >/dev/null || { echo "$c is required" >&2; exit 1; }; done
[ -x /usr/bin/python3 ] || { echo "/usr/bin/python3 is required (the scripts call it by that path)" >&2; exit 1; }

REPO="$(cd "$(dirname "$0")" && pwd)/dot-claude"
C="$HOME/.claude"
SETTINGS="$C/settings.json"
MD="$C/CLAUDE.md"
START='<!-- self-learning-skills:start -->'
END='<!-- self-learning-skills:end -->'
STAMP=$(date +%Y%m%d-%H%M%S)
if [ "$UNINSTALL" = 0 ] && [ -z "$GIT_EMAIL" ] && [ -z "$( (cd "$C/skills" 2>/dev/null && git config user.email) || git config --global user.email || true)" ]; then
  echo "No git identity for the skills repo. Rerun with --git-name and --git-email. Nothing was changed." >&2; exit 1
fi
mkdir -p "$C/backups" "$C/hooks" "$C/skill-review" "$C/skills"

# --- settings.json: remove our hook entries, then (on install) add them back once ---
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" || { echo "$SETTINGS is not valid JSON; fix it first" >&2; exit 1; }
cp "$SETTINGS" "$C/backups/settings.json.before-self-learning-$STAMP"
strip='def own: (.command // "") | test("skill-learning-reminder\\.sh|skill-review/stop-hook\\.sh");
  .hooks = ((.hooks // {})
    | with_entries(.value |= (map(.hooks |= map(select(own | not))) | map(select(.hooks | length > 0))))
    | with_entries(select(.value | length > 0)))
  | if .hooks == {} then del(.hooks) else . end'
apply() {
  if jq "$@" "$SETTINGS" > "$SETTINGS.tmp" && jq empty "$SETTINGS.tmp"; then cat "$SETTINGS.tmp" > "$SETTINGS"; rm -f "$SETTINGS.tmp"   # in place: keeps a symlink, mode and owner
  else rm -f "$SETTINGS.tmp"; echo "Could not update $SETTINGS; it is unchanged." >&2; exit 1; fi
}

# --- CLAUDE.md: remove our marked block (on install it is added back) ---
touch "$MD"
cp "$MD" "$C/backups/CLAUDE.md.before-self-learning-$STAMP"
strip_md() { awk -v s="$START" -v e="$END" '$0==s{skip=1;next} $0==e{skip=0;next} !skip' "$MD" > "$MD.tmp" && cat "$MD.tmp" > "$MD" && rm -f "$MD.tmp"; }

if [ "$UNINSTALL" = 1 ]; then
  apply "$strip"
  strip_md
  echo "Removed the self-learning hooks and the CLAUDE.md block. Skills, scripts and logs are kept."
  echo "Also pause or delete the weekly curator schedule, if you made one."
  exit 0
fi

# --- scripts (state/, logs/, notices and your on-skill-redirect are never touched) ---
# A script that exists and differs from the repo copy is backed up before it is replaced.
B="$C/backups/self-learning-scripts-$STAMP"
put() {  # put <source> <target-dir>
  local t="$2/$(basename "$1")"
  if [ -f "$t" ] && ! cmp -s "$1" "$t"; then mkdir -p "$B/$(basename "$2")"; cp "$t" "$B/$(basename "$2")/"; fi
  cp "$1" "$2/"
}
put "$REPO/hooks/skill-learning-reminder.sh" "$C/hooks"
for f in stop-hook.sh run-review.sh curate.sh apply-changes.py apply-curation.py review-prompt.md curator-prompt.md on-skill-redirect.example; do
  put "$REPO/skill-review/$f" "$C/skill-review"
done
[ -d "$B" ] && echo "Backed up replaced scripts to $B" 
chmod +x "$C/hooks/skill-learning-reminder.sh" "$C/skill-review/"*.sh

# --- skills library: add files only if missing, make it a git repo ---
[ -f "$C/skills/README.md" ] || cp "$REPO/skills/README.md" "$C/skills/"
[ -f "$C/skills/REDIRECTS.md" ] || cp "$REPO/skills/REDIRECTS.md" "$C/skills/"
if [ ! -d "$C/skills/.git" ]; then
  git -C "$C/skills" init -q -b main
  [ -f "$C/skills/.gitignore" ] || printf 'synced/\n.DS_Store\n' > "$C/skills/.gitignore"
fi
[ -n "$GIT_NAME" ] && git -C "$C/skills" config user.name "$GIT_NAME"
[ -n "$GIT_EMAIL" ] && git -C "$C/skills" config user.email "$GIT_EMAIL"
if [ -z "$(git -C "$C/skills" config user.email || true)" ]; then
  echo "The skills repo has no git identity. Rerun with --git-name and --git-email." >&2; exit 1
fi
git -C "$C/skills" add -A
git -C "$C/skills" diff --cached --quiet || git -C "$C/skills" commit -q -m "Self-learning skills: install or update library files"

# --- CLAUDE.md rules block ---
strip_md
if grep -q '^## Self-learning skills' "$MD"; then
  echo "NOTE: $MD already has a '## Self-learning skills' section without install markers; left it unchanged." >&2
else
  { [ -s "$MD" ] && echo; echo "$START"; sed -n '/^## Self-learning skills/,$p' "$REPO/claude-md-block.md"; echo "$END"; } >> "$MD"
fi

# --- hooks ---
add=$(jq '.hooks' "$REPO/settings.hooks.json")
apply --argjson add "$add" "$strip"' | .hooks = (reduce ($add | to_entries[]) as $e ((.hooks // {}); .[$e.key] = ((.[$e.key] // []) + $e.value)))'

echo "Installed self-learning skills in $C."
echo "Next: set up the weekly curator (AGENTS.md step 6), then start a new Claude Code session."
