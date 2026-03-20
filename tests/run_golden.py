#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
HCONV = ROOT / "hconv.py"
CASES = ROOT / "tests" / "golden_cases.json"


def run_case(case: dict[str, str]) -> tuple[bool, str]:
    cmd = [sys.executable, str(HCONV), "-f", case["from"], "-t", case["to"]]
    if case["from"] == "modified":
        data = bytes.fromhex(case["input_hex"])
    else:
        data = case["input_text"].encode("utf-8")

    proc = subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    if "expect_error" in case:
        if proc.returncode == 0:
            return False, f"{case['id']}: expected error {case['expect_error']}, got success"
        stderr = proc.stderr.decode("utf-8", errors="replace")
        if not stderr.startswith(case["expect_error"] + ":"):
            return False, f"{case['id']}: expected error {case['expect_error']}, got {stderr.strip()!r}"
        return True, f"{case['id']}: expected error"

    if proc.returncode != 0:
        return False, f"{case['id']}: conversion failed: {proc.stderr.decode('utf-8', errors='replace').strip()}"

    if case["to"] == "modified":
        actual_hex = proc.stdout.hex()
        if actual_hex != case["expected_hex"]:
            return False, f"{case['id']}: expected hex {case['expected_hex']}, got {actual_hex}"
    else:
        actual_text = proc.stdout.decode("utf-8")
        if actual_text != case["expected_text"]:
            return False, f"{case['id']}: expected text {case['expected_text']!r}, got {actual_text!r}"
    return True, f"{case['id']}: ok"


def main() -> int:
    cases = json.loads(CASES.read_text(encoding="utf-8"))
    failures = 0
    for case in cases:
        ok, message = run_case(case)
        print(message)
        if not ok:
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
