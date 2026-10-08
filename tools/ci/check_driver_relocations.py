#!/usr/bin/env python3
"""Verify the GOLEM.DRV relocation table against the code itself (#18).

The resident image is assembled twice with sjasmplus, at origin $0000 and at
$0100. Every byte that differs by exactly one between the two images is the
high byte of an absolute address inside the driver, so it needs a relocation.
That set must equal the table at the end of the image, and the count in the
.DRV header (src/driver/mt32_drv.s) must match it.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RESIDENT = 512


def assemble(sjasmplus: str, repo: Path, origin: int, work: Path) -> bytes:
    tree = work / f"org{origin:04x}"
    shutil.copytree(repo / "src", tree / "src")
    shutil.copytree(repo / "include", tree / "include")
    source = tree / "src" / "driver" / "mt32drv.s"
    text = source.read_text()
    text = re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", text)
    text, count = re.subn(r"(?m)^(\s*)org \$0000\b", rf"\1org ${origin:04x}", text)
    if count != 1:
        sys.exit("expected exactly one 'org $0000' in mt32drv.s")
    source.write_text(text)
    output = tree / "out.bin"
    subprocess.run(
        [sjasmplus, "--zxnext", "--nologo", "--msg=war", f"--raw={output}", source.name],
        cwd=source.parent,
        check=True,
    )
    return output.read_bytes()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sjasmplus", default="sjasmplus")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        base = assemble(args.sjasmplus, args.repo, 0x0000, Path(tmp))
        moved = assemble(args.sjasmplus, args.repo, 0x0100, Path(tmp))

    if len(base) < RESIDENT or (len(base) - RESIDENT) % 2:
        print(f"unexpected image size {len(base)}")
        return 1
    needed = set()
    for offset in range(RESIDENT):
        delta = (moved[offset] - base[offset]) & 0xFF
        if delta == 1:
            needed.add(offset)
        elif delta:
            print(f"offset {offset:#05x}: unexpected difference {delta:#04x}")
            return 1
    table = [base[i] | base[i + 1] << 8 for i in range(RESIDENT, len(base), 2)]
    listed = set(table)

    header = (args.repo / "src" / "driver" / "mt32_drv.s").read_text()
    match = re.search(r"(?m)^\s*db\s+(\d+)\s*;\s*relocation entries", header)
    header_count = int(match.group(1)) if match else -1

    ok = True
    for offset in sorted(needed - listed):
        print(f"missing relocation for offset {offset:#05x}")
        ok = False
    for offset in sorted(listed - needed):
        print(f"relocation {offset:#05x} does not point at an absolute high byte")
        ok = False
    if len(table) != len(listed):
        print("duplicate relocation entries")
        ok = False
    if header_count != len(table):
        print(f"mt32_drv.s declares {header_count} relocations, table has {len(table)}")
        ok = False
    if ok:
        print(f"relocations OK: {len(table)} entries, resident {RESIDENT} bytes")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
