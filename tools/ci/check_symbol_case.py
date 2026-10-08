#!/usr/bin/env python3
"""Fail if two symbols differ only in case.

SNasm, the assembler of the real build, ignores case in symbol names, so
`RATE_BYTES equ ...` and `rate_bytes:` clash there but not in sjasmplus.
Each dot command is checked with the modules it includes.
"""

from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

SYMBOL = re.compile(r"(?m)^([A-Za-z_][A-Za-z0-9_]*)(?::|\s+equ\b)", re.IGNORECASE)
INCLUDE = re.compile(r'(?m)^\s*include\s+"([^"]+)"', re.IGNORECASE)


def gather(path: Path, seen: set[Path]) -> str:
    path = path.resolve()
    if path in seen or not path.exists():
        return ""
    seen.add(path)
    text = path.read_text(encoding="utf-8", errors="replace")
    for name in INCLUDE.findall(text):
        text += "\n" + gather(path.parent / name, seen)
    return text


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    roots = sorted((repo / "src" / "dot").glob("*.s")) + sorted((repo / "src" / "driver").glob("*.s"))
    failed = False
    for root in roots:
        names = collections.defaultdict(set)
        for symbol in SYMBOL.findall(gather(root, set())):
            names[symbol.lower()].add(symbol)
        for spellings in names.values():
            if len(spellings) > 1:
                print(f"{root.relative_to(repo)}: {' / '.join(sorted(spellings))}")
                failed = True
    if not failed:
        print(f"symbol case OK in {len(roots)} sources")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
