#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from hconv import convert

SOURCE = ROOT / "tests" / "han_pangram.utf8.txt"
OUT_DIR = ROOT / "build" / "samples"

UTF8_OUT = OUT_DIR / "pangram_hcat.utf8.txt"
MODIFIED_OUT = OUT_DIR / "pangram_hcat.modified.bin"
NBYTES_OUT = OUT_DIR / "pangram_hcat.nbytes.txt"


def build_hcat_utf8_sample(text: str) -> str:
    lines: list[str] = []

    for line in text.splitlines():
        if line.startswith("* "):
            lines.append(line[2:])

    return "\n".join(lines)


def encode_hcat_modified_sample(text: str) -> bytes:
    out = bytearray()

    for ch in text:
        cp = ord(ch)
        if cp < 0x80:
            out.append(cp)
        elif 0x1100 <= cp <= 0x11FF:
            mapped = cp - 0xD000
            out.extend(((mapped >> 8) & 0xFF, mapped & 0xFF))
        elif 0xAC00 <= cp <= 0xD7A3:
            mapped = cp - 0x6000
            out.extend(((mapped >> 8) & 0xFF, mapped & 0xFF))
        else:
            raise ValueError(f"unsupported character for HCAT modified sample: U+{cp:04X}")

    return bytes(out)


def main() -> int:
    source_text = SOURCE.read_text(encoding="utf-8")
    sample_text = build_hcat_utf8_sample(source_text)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    UTF8_OUT.write_text(sample_text, encoding="utf-8")
    MODIFIED_OUT.write_bytes(encode_hcat_modified_sample(sample_text))
    NBYTES_OUT.write_text(convert("utf8", "nbytes", sample_text), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
