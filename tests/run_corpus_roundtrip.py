#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
HCONV = ROOT / "hconv.py"
CORPUS = ROOT / "tests" / "han_pangram.utf8.txt"

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from hconv import convert


def run_hconv(from_code: str, to_code: str, data: bytes) -> subprocess.CompletedProcess[bytes]:
    cmd = [sys.executable, str(HCONV), "-f", from_code, "-t", to_code]
    return subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def require_success(
    proc: subprocess.CompletedProcess[bytes],
    *,
    case_id: str,
) -> tuple[bool, str]:
    if proc.returncode == 0:
        return True, f"{case_id}: ok"
    detail = proc.stderr.decode("utf-8", errors="replace").strip()
    return False, f"{case_id}: conversion failed: {detail}"


def require_error_prefix(
    proc: subprocess.CompletedProcess[bytes],
    *,
    case_id: str,
    error_code: str,
) -> tuple[bool, str]:
    if proc.returncode == 0:
        return False, f"{case_id}: expected error {error_code}, got success"
    detail = proc.stderr.decode("utf-8", errors="replace").strip()
    if not detail.startswith(error_code + ":"):
        return False, f"{case_id}: expected error {error_code}, got {detail!r}"
    return True, f"{case_id}: expected error"


def extract_modified_roundtrip_subset(text: str) -> str:
    # `modified` only supports Hangul syllables and modern jamo, not the
    # compatibility jamo or punctuation present in the markdown corpus.
    return "".join(ch for ch in text if 0xAC00 <= ord(ch) <= 0xD7A3)


def roundtrip_char(ch: str, *, via: str) -> tuple[bool, str]:
    if via == "modified":
        encoded = convert("utf8", "modified", ch)
        actual = convert("modified", "utf8", encoded)
    else:
        encoded = convert("utf8", "nbytes", ch)
        actual = convert("nbytes", "utf8", encoded)
    if actual != ch:
        return False, f"char_utf8_{via}_utf8_roundtrip: output mismatch for {ch!r}"
    return True, ""


def run_nbytes_char_roundtrip(corpus_text: str) -> tuple[bool, str]:
    seen: set[str] = set()
    checked = 0
    for ch in corpus_text:
        if ch in seen:
            continue
        seen.add(ch)
        ok, message = roundtrip_char(ch, via="nbytes")
        if not ok:
            return ok, message
        checked += 1
    return True, f"pangram_unique_chars_utf8_nbytes_utf8_roundtrip: ok ({checked} chars)"


def run_delimited_transport_roundtrip(corpus_text: str) -> tuple[bool, str]:
    actual = convert("nbytes", "utf8", convert("utf8", "nbytes", corpus_text))
    if actual != corpus_text:
        return False, "pangram_delimited_transport_roundtrip: output mismatch"
    return True, "pangram_delimited_transport_roundtrip: ok"


def run_modified_subset_roundtrip(corpus_text: str) -> tuple[bool, str]:
    subset = extract_modified_roundtrip_subset(corpus_text)
    if not subset:
        return False, "pangram_utf8_modified_utf8_subset_roundtrip: empty subset"

    encoded = run_hconv("utf8", "modified", subset.encode("utf-8"))
    ok, message = require_success(encoded, case_id="pangram_subset_utf8_to_modified")
    if not ok:
        return ok, message

    decoded = run_hconv("modified", "utf8", encoded.stdout)
    ok, message = require_success(decoded, case_id="pangram_subset_modified_to_utf8")
    if not ok:
        return ok, message

    actual = decoded.stdout.decode("utf-8")
    if actual != subset:
        return False, "pangram_utf8_modified_utf8_subset_roundtrip: output mismatch"
    return True, "pangram_utf8_modified_utf8_subset_roundtrip: ok"


def run_modified_full_corpus_failure(corpus_text: str) -> tuple[bool, str]:
    proc = run_hconv("utf8", "modified", corpus_text.encode("utf-8"))
    return require_error_prefix(
        proc,
        case_id="pangram_full_utf8_to_modified",
        error_code="unsupported_unicode_codepoint",
    )


def main() -> int:
    corpus_text = CORPUS.read_text(encoding="utf-8")
    checks = [
        run_nbytes_char_roundtrip(corpus_text),
        run_delimited_transport_roundtrip(corpus_text),
        run_modified_subset_roundtrip(corpus_text),
        run_modified_full_corpus_failure(corpus_text),
    ]

    failures = 0
    for ok, message in checks:
        print(message)
        if not ok:
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
