"""Apply the background reviewer's <skill-changes> block to the skill library and commit.

Usage: python3 -I apply-changes.py <reviewer-json-output> <skills-dir>
Prints the one-line summary on success, or exits non-zero with a reason on stderr.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script dir
from ownership import add_marker, is_managed  # noqa: E402

ALLOWED = re.compile(r"^[a-z0-9][a-z0-9-]*/(SKILL\.md|(references|templates|scripts)/[A-Za-z0-9._-]+)$")


def main(out_path: str, skills_dir: str) -> None:
    result = json.loads(Path(out_path).read_text()).get("result") or ""
    blocks = re.findall(r"<skill-changes>\s*(.*?)\s*</skill-changes>", result, re.S)
    if not blocks:
        sys.exit("no <skill-changes> block in reviewer output")
    changes = json.loads(blocks[-1])
    summary = " ".join(str(changes.get("summary", "")).split()) or "Nothing to save."
    files = changes.get("files") or []

    root = Path(skills_dir).resolve()
    new_skills = {str(f.get("path", "")).split("/")[0] for f in files
                  if str(f.get("path", "")).endswith("/SKILL.md")}
    written = []
    for f in files:
        rel = str(f.get("path", ""))
        if not ALLOWED.match(rel) or rel.split("/")[0] in ("synced",):
            print(f"skipped disallowed path: {rel!r}", file=sys.stderr)
            continue
        target = (root / rel).resolve()
        if root not in target.parents:
            print(f"skipped path outside library: {rel!r}", file=sys.stderr)
            continue
        skill = root / rel.split("/")[0]
        if (skill / "SKILL.md").exists() and not is_managed(skill):
            print(f"skipped skill not created by self-learning-skills: {rel!r}", file=sys.stderr)
            continue
        if not (skill / "SKILL.md").exists() and skill.name not in new_skills:
            print(f"skipped support file for a skill that does not exist: {rel!r}", file=sys.stderr)
            continue
        content = str(f.get("content", ""))
        if rel.endswith("/SKILL.md"):
            try:
                content = add_marker(content)
            except ValueError as e:
                print(f"skipped {rel!r}: {e}", file=sys.stderr)
                continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        written.append(rel)

    if written:
        git = ["git", "-C", str(root)]
        subprocess.run(git + ["add", "--"] + written, check=True)
        subprocess.run(git + ["commit", "-q", "-m", f"{summary} (background review)"], check=True)
    elif files:
        sys.exit("reviewer proposed changes but none had an allowed path")
    print(summary)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
