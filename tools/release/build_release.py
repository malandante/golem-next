#!/usr/bin/env python3
"""Build the golem-next SD package: binaries, docs, SHA256SUMS and a zip.

Assembles every shipped binary from a clean copy of src/ and include/, with
sjasmplus (CI, Linux) or SNasm (Windows, NextBuild), lays out the files the
way they go on the SD card and writes SHA256SUMS. The zip has fixed dates and
a fixed order, so the same sources and assembler give the same zip.

    python tools/release/build_release.py --version 1.0.0 --out dist
    python tools/release/build_release.py --assembler snasm --assembler-path SNasm.exe

Both assemblers must give the same binaries; compare the two SHA256SUMS.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ZIP_DATE = (2026, 1, 1, 0, 0, 0)
DOTS = ("GOLEM", "MT32", "GM", "GSQ")
SLOTS = ("4000", "6000", "8000", "A000", "C000", "E000")
DOCS = {
    "docs/guide.md": "docs/user/guide.md",
    "docs/programming.md": "docs/programming.md",
    "docs/guia.md": "docs/user/guia.md",
    "docs/gseq.md": "docs/m6-gseq.md",
    "docs/driver-api.md": "docs/driver-api.md",
    "docs/golem-protocol.md": "docs/mt32-pi-control.md",
    "LICENSE": "LICENSE",
    "RELEASE_NOTES.md": "RELEASE_NOTES.md",
}
LIB_SOURCES = {
    "lib/gseq.bas": "src/lib/gseq.bas",
    "lib/gseq.s": "src/lib/gseq.s",
    "lib/mt32_api.inc": "include/mt32_api.inc",
    "lib/golem_api.inc": "include/golem_api.inc",
    "tools/gseq.py": "tools/host/gseq.py",
}

README = """golem-next {version}
{rule}

MIDI driver, commands and music library for the ZX Spectrum Next, for a
Golem (Raspberry Pi with the Golem firmware, based on mt32-pi) or any MIDI
synthesiser.

Install (full guide: docs/guide.md, in Spanish docs/guia.md):

  nextzxos/GOLEM.DRV   -> c:/nextzxos/GOLEM.DRV
  dot/GOLEM, MT32, GM  -> c:/dot/
  dot/GSQ              -> c:/dot/

  .install "c:/nextzxos/GOLEM.DRV"
  .golem status
  .golem play song.mid      (.mt32 / .gm first select the MT-32 / GM engine)

lib/    GSEQ library banks (GSEQ4000.BIN ... GSEQE000.BIN, one per slot),
        the ZX Basic binding gseq.bas and the assembler source.
tools/  gseq.py, the MIDI to GSEQ converter (Python 3).

The Golem firmware is a separate program under GPL-3.0; its source and
kernels are at {firmware}.

golem-next is MIT licensed (LICENSE). Check the files with SHA256SUMS.
"""


def assemble(assembler: str, path: str, source: Path, output: Path) -> None:
    if assembler == "sjasmplus":
        command = [path, "--zxnext", "--nologo", "--msg=war", f"--raw={output}", source.name]
    else:
        command = [path, "-next", source.name, str(output)]
    subprocess.run(command, cwd=source.parent, check=True)
    if not output.is_file():
        sys.exit(f"{source.name}: no output")


def build(assembler: str, path: str, tree: Path, out: Path) -> None:
    shutil.copytree(REPO / "src", tree / "src")
    shutil.copytree(REPO / "include", tree / "include")
    (tree / "build").mkdir()
    if assembler == "sjasmplus":    # SNasm needs the directive, sjasmplus rejects it
        for source in (tree / "src").rglob("*.s"):
            text = source.read_text()
            source.write_text(re.sub(r"(?m)^(\s*)opt zxnext", r"\1; opt zxnext", text))

    driver = tree / "src" / "driver"
    assemble(assembler, path, driver / "mt32drv.s", tree / "build" / "mt32drv.bin")
    assemble(assembler, path, driver / "mt32_drv.s", out / "nextzxos" / "GOLEM.DRV")
    for name in DOTS:
        assemble(assembler, path, tree / "src" / "dot" / f"{name.lower()}.s", out / "dot" / name)
    for slot in SLOTS:
        assemble(assembler, path, tree / "src" / "lib" / f"gseq_{slot.lower()}.s",
                 out / "lib" / f"GSEQ{slot}.BIN")


def check(out: Path) -> None:
    driver = (out / "nextzxos" / "GOLEM.DRV").read_bytes()
    if len(driver) != 600 or driver[:4] != b"NDRV":
        sys.exit(f"GOLEM.DRV: {len(driver)} bytes, signature {driver[:4]!r}")
    for name in DOTS:
        size = (out / "dot" / name).stat().st_size
        if not 0 < size <= 8192:
            sys.exit(f"{name}: {size} bytes")
    for slot in SLOTS:
        data = (out / "lib" / f"GSEQ{slot}.BIN").read_bytes()
        if not 0 < len(data) <= 8192 or data[27:32] != b"GSEQ\x01":
            sys.exit(f"GSEQ{slot}.BIN: bad size or signature")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--assembler", choices=("sjasmplus", "snasm"), default="sjasmplus")
    parser.add_argument("--assembler-path", help="assembler executable (default: its name)")
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--firmware", default="https://github.com/malandante/mt32-pi/releases",
                        help="where the Golem firmware and its source are published")
    parser.add_argument("--out", type=Path, default=REPO / "dist")
    args = parser.parse_args()
    args.out = args.out.resolve()
    path = args.assembler_path or ("SNasm" if args.assembler == "snasm" else "sjasmplus")

    name = f"golem-next-{args.version}"
    package = args.out / name
    if package.exists():
        shutil.rmtree(package)
    for folder in ("nextzxos", "dot", "lib", "tools", "docs"):
        (package / folder).mkdir(parents=True)
    with tempfile.TemporaryDirectory() as tmp:
        build(args.assembler, path, Path(tmp), package)
    check(package)
    for target, source in {**DOCS, **LIB_SOURCES}.items():
        shutil.copyfile(REPO / source, package / target)
    title = f"golem-next {args.version}"
    readme = README.format(version=args.version, rule="=" * len(title), firmware=args.firmware)
    (package / "README.txt").write_text(readme.replace("\n", "\r\n"), newline="")

    files = sorted(p for p in package.rglob("*") if p.is_file())
    sums = "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(package).as_posix()}\n"
                   for p in files)
    (package / "SHA256SUMS").write_text(sums, newline="\n")
    files.append(package / "SHA256SUMS")

    archive = args.out / f"{name}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in sorted(files):
            info = zipfile.ZipInfo(f"{name}/{p.relative_to(package).as_posix()}", ZIP_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, p.read_bytes())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    print(sums, end="")
    print(f"{digest}  {archive.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
