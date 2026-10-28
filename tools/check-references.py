#!/usr/bin/env python3
"""Fail when a Markdown page names a scenario that is not there."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", ".make", "build", "runs", "vendor", "node_modules"}
SCENARIO_REF = re.compile(r"(?<![\w/])(scenarios/[A-Za-z0-9._/-]+\.json)")


def markdown_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*.md"):
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        files.append(path)
    return files


def main() -> int:
    missing: list[str] = []
    for path in markdown_files():
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for match in SCENARIO_REF.finditer(line):
                reference = match.group(1)
                if not (ROOT / reference).is_file():
                    missing.append(f"{path.relative_to(ROOT)}:{number}: {reference}")

    if missing:
        for line in missing:
            print(f"check-references: {line}", file=sys.stderr)
        return 1
    print("check-references: every scenario reference resolves")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
