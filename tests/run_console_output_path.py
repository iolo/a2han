#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from hconv import (
    BASE_NBYTES_TO_JAMO,
    COMPOUND_NBYTES_TO_JAMO,
    SPAN_END,
    SPAN_START,
    L_SET,
    T_SET,
    V_SET,
    compose_syllable,
    convert,
    encode_modified,
)


NBYTES_MAX = 0x20
INITIAL_ORDER = "RrSEeFAQqTtDWwCZXVG"
VOWEL_SINGLE_ORDER = "KOIoJPUpHYNBML"
VOWEL_PAIR_ORDER = ("HK", "HO", "HL", "NJ", "NP", "NL", "ML")
FINAL_SINGLE_ORDER = "RrSEFAQTtDWCZXVG"
FINAL_PAIR_ORDER = ("RT", "SW", "SG", "FR", "FA", "FQ", "FT", "FX", "FV", "FG", "QT")

INITIAL_INDEX = {ch: index for index, ch in enumerate(INITIAL_ORDER)}
VOWEL_INDEX = {
    **{ch: index for index, ch in enumerate(VOWEL_SINGLE_ORDER)},
    **{pair: index for index, pair in enumerate(VOWEL_PAIR_ORDER, start=9)},
}
FINAL_INDEX = {
    **{ch: index for index, ch in enumerate(FINAL_SINGLE_ORDER, start=1)},
    **{pair: index for index, pair in enumerate(FINAL_PAIR_ORDER, start=3)},
}


def decode_token(payload: str, index: int) -> tuple[str | None, int]:
    pair = payload[index : index + 2]
    if len(pair) == 2 and pair in COMPOUND_NBYTES_TO_JAMO:
        return COMPOUND_NBYTES_TO_JAMO[pair], 2

    ch = payload[index]
    if ch in BASE_NBYTES_TO_JAMO:
        return BASE_NBYTES_TO_JAMO[ch], 1
    return None, 1


def emit_standalone_jamo_bytes(payload: str, index: int) -> tuple[bytes | None, int]:
    pair = payload[index : index + 2]
    if len(pair) == 2 and pair in VOWEL_INDEX:
        return bytes((0x41, 0x61 + VOWEL_INDEX[pair])), 2

    ch = payload[index]
    if ch in VOWEL_INDEX:
        return bytes((0x41, 0x61 + VOWEL_INDEX[ch])), 1
    if ch in INITIAL_INDEX:
        return bytes((0x41, INITIAL_INDEX[ch])), 1
    return None, 1


def convert_payload_fail_soft(payload: str) -> bytes:
    out = bytearray()
    i = 0

    while i < len(payload):
        initial, initial_size = decode_token(payload, i)
        if initial_size == 1 and initial in L_SET:
            vowel_index = i + initial_size
            if vowel_index < len(payload):
                medial, medial_size = decode_token(payload, vowel_index)
                if medial in V_SET:
                    final = ""
                    consumed = initial_size + medial_size
                    final_index = vowel_index + medial_size
                    if final_index < len(payload):
                        candidate, candidate_size = decode_token(payload, final_index)
                        if candidate in T_SET:
                            use_final = True
                            if candidate_size == 1 and final_index + 1 < len(payload):
                                lookahead, _ = decode_token(payload, final_index + 1)
                                if lookahead in V_SET and payload[final_index] in INITIAL_INDEX:
                                    use_final = False
                            if use_final:
                                final = candidate
                                consumed += candidate_size

                    out.extend(encode_modified(compose_syllable(initial, medial, final)))
                    i += consumed
                    continue

        standalone, consumed = emit_standalone_jamo_bytes(payload, i)
        if standalone is not None:
            out.extend(standalone)
            i += consumed
            continue

        out.extend(payload[i].encode("utf-8"))
        i += 1

    return bytes(out)


def simulate_console_output(stream: str) -> bytes:
    out = bytearray()
    state_active = False
    overflow = False
    buffer: list[str] = []

    for ch in stream:
        masked = chr(ord(ch) & 0x7F)
        if masked == SPAN_START:
            if state_active:
                if len(buffer) >= NBYTES_MAX:
                    overflow = True
                else:
                    buffer.append(ch)
            else:
                state_active = True
                overflow = False
                buffer.clear()
            continue

        if masked == SPAN_END:
            if not state_active:
                out.extend(ch.encode("utf-8"))
                continue
            if overflow:
                out.extend(SPAN_START.encode("utf-8"))
                out.extend("".join(buffer).encode("utf-8"))
                out.extend(SPAN_END.encode("utf-8"))
            else:
                out.extend(convert_payload_fail_soft("".join(buffer)))
            state_active = False
            overflow = False
            buffer.clear()
            continue

        if not state_active:
            out.extend(ch.encode("utf-8"))
            continue

        if len(buffer) >= NBYTES_MAX:
            overflow = True
        else:
            buffer.append(ch)

    return bytes(out)


def require_equal(*, case_id: str, actual: bytes, expected: bytes) -> tuple[bool, str]:
    if actual == expected:
        return True, f"{case_id}: ok"
    return False, f"{case_id}: expected {expected.hex()}, got {actual.hex()}"


def main() -> int:
    cases = [
        require_equal(
            case_id="console_basic_span_to_modified",
            actual=simulate_console_output(SPAN_START + "GKS" + SPAN_END),
            expected=bytes.fromhex("755c"),
        ),
        require_equal(
            case_id="console_stray_span_end_passthrough",
            actual=simulate_console_output("A" + SPAN_END + "B"),
            expected=("A" + SPAN_END + "B").encode("utf-8"),
        ),
        require_equal(
            case_id="console_nested_ctrl_k_is_literal_and_fails_soft",
            actual=simulate_console_output(SPAN_START + "R" + SPAN_START + "K" + SPAN_END),
            expected=bytes.fromhex("41000b4161"),
        ),
        require_equal(
            case_id="console_overflow_span_roundtrips_raw",
            actual=simulate_console_output(SPAN_START + ("R" * (NBYTES_MAX + 1)) + SPAN_END),
            expected=(SPAN_START + ("R" * NBYTES_MAX) + SPAN_END).encode("utf-8"),
        ),
        require_equal(
            case_id="console_standalone_vowel_emits_modified_jamo",
            actual=simulate_console_output(SPAN_START + "HK" + SPAN_END),
            expected=bytes.fromhex("416a"),
        ),
    ]

    failures = 0
    for ok, message in cases:
        print(message)
        if not ok:
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
