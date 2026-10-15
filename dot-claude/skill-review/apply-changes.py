"""Apply the background reviewer's <skill-changes> block to the skill library and commit.

Usage: python3 -I apply-changes.py <reviewer-json-output> <skills-dir>
Prints the one-line summary on success, or exits non-zero with a reason on stderr.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

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
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(str(f.get("content", "")))
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
