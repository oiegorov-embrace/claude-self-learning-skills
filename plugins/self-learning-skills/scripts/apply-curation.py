"""Apply the curator's <curation> block: merge skills, keeping every old name reachable.

Usage: python3 -I apply-curation.py <curator-json-output> <skills-dir> [redirect-hook]
For each merge: writes the survivor's SKILL.md (forcing a "Formerly: ..." alias into its
description), moves the retired skills' support files into the survivor, archives the
retired folders under .archive/, appends rows to REDIRECTS.md, commits, and calls
redirect-hook <old> <new> <date> <reason> if that file exists and is executable
(e.g. to store the redirect in Hindsight). Prints a one-line summary.
"""
from __future__ import annotations

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script dir
from ownership import add_marker, is_managed  # noqa: E402

NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
RESERVED = {"synced", ".archive"}


def ensure_alias(content: str, retired: list[str]) -> str:
    """Make sure the frontmatter description ends with 'Formerly: <every retired name>.'"""
    m = re.match(r"^---\n(.*?)\n---\n", content, re.S)
    if not m:
        raise ValueError("survivor SKILL.md has no frontmatter")
    front = m.group(1)
    d = re.search(r"^description:[ \t]*(.*)$", front, re.M)
    if not d:
        raise ValueError("survivor SKILL.md has no description")
    desc = d.group(1).rstrip()
    missing = [n for n in retired if not re.search(rf"\b{re.escape(n)}\b", desc)]
    if missing:
        desc = f"{desc} Formerly: {', '.join(missing)}."
    front = front[: d.start(1)] + desc + front[d.end(1):]
    return f"---\n{front}\n---\n" + content[m.end():]


def move_support_files(src: Path, dst: Path, old: str) -> None:
    for sub in ("references", "templates", "scripts"):
        if not (src / sub).is_dir():
            continue
        (dst / sub).mkdir(parents=True, exist_ok=True)
        for f in (src / sub).iterdir():
            target = dst / sub / f.name
            if target.exists():
                target = dst / sub / f"{old}-{f.name}"
            shutil.copy2(f, target)


def main(out_path: str, skills_dir: str, hook: str | None) -> None:
    result = json.loads(Path(out_path).read_text()).get("result") or ""
    blocks = re.findall(r"<curation>\s*(.*?)\s*</curation>", result, re.S)
    if not blocks:
        sys.exit("no <curation> block in curator output")
    plan = json.loads(blocks[-1])
    root = Path(skills_dir).resolve()
    today = datetime.date.today().isoformat()
    git = ["git", "-C", str(root)]
    done = []

    for merge in plan.get("merges") or []:
        into = str(merge.get("into", ""))
        retired = [str(n) for n in merge.get("from") or [] if str(n) != into]
        reason = " ".join(str(merge.get("reason", "")).split()) or "overlapping skills"
        bad = [n for n in [into] + retired if not NAME.match(n) or n in RESERVED]
        missing = [n for n in retired if not (root / n / "SKILL.md").is_file()]
        if bad or missing or not retired:
            print(f"skipped merge into {into!r}: bad={bad} missing={missing}", file=sys.stderr)
            continue
        foreign = [n for n in retired + [into] if (root / n / "SKILL.md").is_file() and not is_managed(root / n)]
        if foreign:
            print(f"skipped merge into {into!r}: not created by self-learning-skills: {foreign}", file=sys.stderr)
            continue
        try:
            content = add_marker(ensure_alias(str(merge.get("content", "")), retired))
        except ValueError as e:
            print(f"skipped merge into {into!r}: {e}", file=sys.stderr)
            continue
        content = re.sub(r"^name:.*$", f"name: {into}", content, count=1, flags=re.M)

        survivor = root / into
        survivor.mkdir(exist_ok=True)
        (survivor / "SKILL.md").write_text(content)
        archive = root / ".archive"
        archive.mkdir(exist_ok=True)
        for old in retired:
            move_support_files(root / old, survivor, old)
            dest = archive / old
            if dest.exists():
                dest = archive / f"{old}-{today}"
            shutil.move(str(root / old), dest)

        redirects = root / "REDIRECTS.md"
        with redirects.open("a") as f:
            for old in retired:
                f.write(f"| {old} | {into} | {today} | {reason.replace('|', '/')} |\n")

        subprocess.run(git + ["add", "-A", "--", "."], check=True)
        subprocess.run(git + ["commit", "-q", "-m",
                              f"Merge {', '.join(retired)} into {into} (curator)\n\n{reason}"], check=True)

        if hook and os.access(hook, os.X_OK):
            for old in retired:
                subprocess.run([hook, old, into, today, reason], check=False)
        done.append(f"merged {', '.join(retired)} into `{into}`")

    print("Skill curator: " + ("; ".join(done) if done else "no merges needed."))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
