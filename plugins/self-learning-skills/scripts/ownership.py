"""Which skills the self-learning system may change.

A skill is managed when its SKILL.md frontmatter has the marker

    metadata:
      created-by: self-learning-skills

The reviewer, the curator and in-session Claude add it to every skill they create.
Skills without it (installed by hand, from a team, etc.) are read-only to the system.

CLI (used by the shell scripts):
    python3 -I ownership.py list <skills-dir> managed|unmanaged
    python3 -I ownership.py adopt <skills-dir> <name>...   add the marker to these skills
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER_KEY = "created-by"
MARKER_VALUE = "self-learning-skills"
_FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.S)
_HAS = re.compile(rf"^\s*{MARKER_KEY}:\s*['\"]?{MARKER_VALUE}['\"]?\s*$", re.M)
SKIP = {"synced", ".archive"}


def is_managed_text(content: str) -> bool:
    m = _FRONT.match(content)
    return bool(m and _HAS.search(m.group(1)))


def is_managed(skill_dir: Path) -> bool:
    f = skill_dir / "SKILL.md"
    try:
        return f.is_file() and is_managed_text(f.read_text())
    except OSError:
        return False


def add_marker(content: str) -> str:
    """Return content with the marker in its frontmatter (unchanged if already there)."""
    if is_managed_text(content):
        return content
    m = _FRONT.match(content)
    if not m:
        raise ValueError("SKILL.md has no frontmatter")
    front = m.group(1)
    line = f"  {MARKER_KEY}: {MARKER_VALUE}"
    meta = re.search(r"^metadata:[ \t]*$", front, re.M)
    if meta:
        front = front[: meta.end()] + "\n" + line + front[meta.end():]
    else:
        front = front + "\nmetadata:\n" + line
    return f"---\n{front}\n---\n" + content[m.end():]


def skills(root: Path) -> list[Path]:
    return sorted(p.parent for p in root.glob("*/SKILL.md")
                  if p.parent.name not in SKIP and not p.parent.name.startswith("."))


def main(argv: list[str]) -> None:
    cmd, root = argv[0], Path(argv[1])
    if cmd == "list":
        want = argv[2] == "managed"
        for s in skills(root):
            if is_managed(s) == want:
                print(s.name)
    elif cmd == "adopt":
        for name in argv[2:]:
            f = root / name / "SKILL.md"
            if not f.is_file():
                print(f"no such skill: {name}", file=sys.stderr)
                continue
            f.write_text(add_marker(f.read_text()))
            print(name)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
