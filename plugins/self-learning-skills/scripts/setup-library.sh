#!/bin/bash
# Makes the skill library (~/.claude/skills) a git repository, so every skill change is a commit.
# Idempotent: it never changes existing skills, except the ones you adopt; it adds README.md and
# REDIRECTS.md only if missing.
# Usage: setup-library.sh [--git-name NAME --git-email EMAIL] [--adopt name,name|all]
#   --adopt  mark existing skills as created by self-learning-skills, so the reviewer and the
#            curator may change them. Without it, existing skills stay read-only to the system.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
LIB="$(cd "$CODE/../library" 2>/dev/null && pwd || echo "$CODE")"   # plugin: ../library; manual: next to the script
NAME="" EMAIL="" ADOPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --git-name) NAME="$2"; shift 2 ;;
    --git-email) EMAIL="$2"; shift 2 ;;
    --adopt) ADOPT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$EMAIL" ] && [ -z "$( (cd "$SKILLS" 2>/dev/null && git config user.email) || git config --global user.email || true)" ]; then
  echo "No git identity for the skill library. Rerun with --git-name and --git-email. Nothing was changed." >&2; exit 1
fi
mkdir -p "$SKILLS"
[ -f "$SKILLS/README.md" ] || cp "$LIB/README.md" "$SKILLS/"
[ -f "$SKILLS/REDIRECTS.md" ] || cp "$LIB/REDIRECTS.md" "$SKILLS/"
if [ ! -d "$SKILLS/.git" ]; then
  git -C "$SKILLS" init -q -b main
  [ -f "$SKILLS/.gitignore" ] || printf 'synced/\n.DS_Store\n' > "$SKILLS/.gitignore"
fi
[ -n "$NAME" ] && git -C "$SKILLS" config user.name "$NAME"
[ -n "$EMAIL" ] && git -C "$SKILLS" config user.email "$EMAIL"
git -C "$SKILLS" add -A
git -C "$SKILLS" diff --cached --quiet || git -C "$SKILLS" commit -q -m "Self-learning skills: set up the skill library"

OWN=(/usr/bin/python3 -I "$CODE/ownership.py")
if [ -n "$ADOPT" ]; then
  if [ "$ADOPT" = all ]; then names=$("${OWN[@]}" list "$SKILLS" unmanaged); else names=$(echo "$ADOPT" | tr ',' ' '); fi
  if [ -n "$names" ]; then
    adopted=$("${OWN[@]}" adopt "$SKILLS" $names | tr '\n' ' ')
    git -C "$SKILLS" add -A
    git -C "$SKILLS" diff --cached --quiet || git -C "$SKILLS" commit -q -m "Self-learning skills: adopt ${adopted% }"
    echo "Adopted: ${adopted:-none}"
  fi
fi
echo "Skill library ready: $SKILLS ($(git -C "$SKILLS" rev-list --count HEAD) commits)."
echo "Managed by self-learning-skills: $("${OWN[@]}" list "$SKILLS" managed | tr '\n' ' ')"
echo "Read-only (not created by self-learning-skills): $("${OWN[@]}" list "$SKILLS" unmanaged | tr '\n' ' ')"
