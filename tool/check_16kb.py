#!/usr/bin/env python3
"""Verify 16 KB page-size support of native libraries in an APK or AAB.

Google Play requires 16 KB page-size support for 64-bit apps targeting
Android 15+ (mandatory since November 1, 2025). For the shipped artifacts
that means:

1. Every 64-bit .so must be linked with PT_LOAD segment alignment of at
   least 16384 bytes (what `-Wl,-z,max-page-size=16384` produces).
2. In an APK, .so files must be stored uncompressed so the OS can map them
   page-aligned (AGP: useLegacyPackaging = false).

This script checks both with nothing but the Python standard library —
no Android SDK required. Anything it cannot verify is reported; only an
explicit PASS counts.

Usage:
    python3 tool/check_16kb.py build/app/outputs/flutter-apk/app-release.apk
    python3 tool/check_16kb.py build/app/outputs/bundle/release/app-release.aab
    python3 tool/check_16kb.py some_lib.so        # single library
    python3 tool/check_16kb.py --selftest         # built-in parser test

Exit codes: 0 = pass, 1 = failure(s) found, 2 = usage/setup error.
"""

from __future__ import annotations

import io
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

PAGE_SIZE = 16384
REQUIRED_ABIS = {"arm64-v8a", "x86_64"}  # the 16 KB rule covers 64-bit only
KNOWN_ABIS = {"arm64-v8a", "x86_64", "armeabi-v7a", "x86"}

PT_LOAD = 1


def elf_load_alignments(data: bytes):
    """Parse an ELF image; return (kind, detail, pt_load_alignments)."""
    if len(data) < 64 or data[:4] != b"\x7fELF":
        return ("not-elf", "not an ELF image", [])
    ei_class, ei_data = data[4], data[5]
    if ei_class == 1:
        return ("elf32", "32-bit ELF (16 KB rule does not apply)", [])
    if ei_class != 2:
        return ("bad", f"unknown ELF class {ei_class}", [])
    if ei_data != 1:
        return ("bad", "unexpected big-endian ELF", [])
    (e_phoff,) = struct.unpack_from("<Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)
    aligns = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if off + 0x38 > len(data):
            return ("bad", "truncated program header table", [])
        (p_type,) = struct.unpack_from("<I", data, off)
        if p_type == PT_LOAD:
            (p_align,) = struct.unpack_from("<Q", data, off + 0x30)
            aligns.append(p_align)
    if not aligns:
        return ("bad", "no PT_LOAD segments", [])
    return ("elf64", f"{len(aligns)} PT_LOAD segment(s)", aligns)


def _so_paths(names):
    """Yield (zip_entry_name, abi) for every native library in the archive."""
    for name in names:
        parts = name.split("/")
        if not name.endswith(".so"):
            continue
        abi = next((seg for seg in parts[:-1] if seg in KNOWN_ABIS), None)
        if abi is not None:
            yield name, abi


def _judge(short: str, kind: str, detail: str, aligns: list[int], compressed: bool):
    """Return (line, ok) for one library."""
    if kind == "not-elf":
        return f"WARN  {short} — {detail}", True
    if kind == "elf32":
        return f"INFO  {short} — {detail}", True
    if kind == "bad":
        return f"FAIL  {short} — {detail}", False
    worst = min(aligns)
    if worst < PAGE_SIZE:
        return (
            f"FAIL  {short} — PT_LOAD alignment {worst:#x} < {PAGE_SIZE:#x} "
            f"({worst // 1024} KB); relink with max-page-size=16384",
            False,
        )
    if compressed:
        return (
            f"FAIL  {short} — aligned but stored compressed; install-time "
            "extraction breaks 16 KB mapping (keep useLegacyPackaging=false)",
            False,
        )
    return (
        f"PASS  {short} — {detail}, alignment up to {max(aligns):#x}, stored uncompressed",
        True,
    )


def check_ziplike(path: Path):
    """Check every native library in an APK/AAB. Returns (lines, ok)."""
    try:
        z = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        return [f"ERROR: {path} is not a readable zip archive (APK/AAB expected)"], False
    lines, ok, found = [], True, False
    with z:
        for name, _abi in _so_paths(z.namelist()):
            found = True
            info = z.getinfo(name)
            compressed = info.compress_type != zipfile.ZIP_STORED
            short = name if len(name) <= 72 else "…" + name[-71:]
            line, line_ok = _judge(short, *elf_load_alignments(z.read(name)), compressed)
            lines.append(line)
            ok = ok and line_ok
        if not found:
            lines.append("WARN  no native libraries found under a lib/<abi>/ folder — nothing to verify")
    return lines, ok


def check_single_so(path: Path):
    kind, detail, aligns = elf_load_alignments(path.read_bytes())
    line, ok = _judge(path.name, kind, detail, aligns, compressed=False)
    return [line], ok


def _make_elf64(load_align: int) -> bytes:
    """Build a minimal synthetic ELF64 (two PT_LOAD segments) for the selftest."""
    eh = bytearray(64)
    eh[0:4] = b"\x7fELF"
    eh[4], eh[5], eh[6] = 2, 1, 1  # ELFCLASS64, little-endian, EV_CURRENT
    struct.pack_into("<HHI", eh, 16, 3, 183, 1)  # ET_DYN, EM_AARCH64, version
    struct.pack_into("<Q", eh, 0x20, 64)  # e_phoff
    struct.pack_into("<HH", eh, 0x36, 56, 2)  # e_phentsize, e_phnum
    ph = b""
    for i in range(2):
        ph += struct.pack(
            "<IIQQQQQQ",
            PT_LOAD, 5,
            0x1000 + i * 0x100, 0x1000 + i * 0x100, 0x1000 + i * 0x100,
            0x100, 0x100,
            load_align,
        )
    return bytes(eh) + ph


def _run_check(zip_bytes: bytes):
    with tempfile.NamedTemporaryFile(suffix=".apk", delete=False) as tmp:
        tmp.write(zip_bytes)
        tmp_path = Path(tmp.name)
    try:
        return check_ziplike(tmp_path)
    finally:
        tmp_path.unlink(missing_ok=True)


def selftest() -> int:
    good, bad = _make_elf64(0x10000), _make_elf64(0x1000)
    buf_only_good = io.BytesIO()
    with zipfile.ZipFile(buf_only_good, "w") as z:
        z.writestr("lib/arm64-v8a/libgood.so", good)
    buf_mixed = io.BytesIO()
    with zipfile.ZipFile(buf_mixed, "w") as z:
        z.writestr("lib/arm64-v8a/libgood.so", good)
        z.writestr("lib/arm64-v8a/libbad.so", bad)
    lines_good, ok_good = _run_check(buf_only_good.getvalue())
    lines_mixed, ok_mixed = _run_check(buf_mixed.getvalue())
    for line in lines_good + lines_mixed:
        print(line)
    passes = sum(1 for l in lines_mixed if l.startswith("PASS"))
    fails = sum(1 for l in lines_mixed if l.startswith("FAIL"))
    if ok_good and (not ok_mixed) and passes == 1 and fails == 1:
        print("selftest OK: aligned-only archive passes, mixed archive fails")
        return 0
    print("selftest FAILED: unexpected results")
    return 1


def main(argv: list[str]) -> int:
    args = argv[1:]
    if "--selftest" in args:
        return selftest()
    if "--help" in args or not args:
        print(__doc__)
        return 2
    path = Path(args[0])
    if not path.exists():
        print(f"ERROR: {path} does not exist")
        return 2
    lines, ok = (
        check_single_so(path) if path.suffix == ".so" else check_ziplike(path)
    )
    for line in lines:
        print(line)
    print()
    print(
        "RESULT: PASS — all 64-bit native libraries are 16 KB page-aligned "
        "and stored uncompressed"
        if ok
        else "RESULT: FAIL — fix the libraries above before uploading to Google Play"
    )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
