#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from hconv import SPAN_END, SPAN_START, compose_syllable, encode_modified


STATE_IDLE = 0
STATE_ACTIVE = 1
STATE_INITIAL = 2
STATE_LV = 3
STATE_LVT = 4
STATE_LVTT = 5
STATE_LVV = 6
STATE_LVVT = 7
STATE_LVVTT = 8

INITIAL_MAP = {
    "R": 0,
    "r": 1,
    "-": 1,
    "S": 2,
    "E": 3,
    "e": 4,
    "=": 4,
    "F": 5,
    "A": 6,
    "Q": 7,
    "q": 8,
    "*": 8,
    "T": 9,
    "t": 10,
    "<": 10,
    "D": 11,
    "W": 12,
    "w": 13,
    ">": 13,
    "C": 14,
    "Z": 15,
    "X": 16,
    "V": 17,
    "G": 18,
}

VOWEL_SINGLE_MAP = {
    "K": 0,
    "O": 1,
    "I": 2,
    "o": 3,
    "J": 4,
    "P": 5,
    "U": 6,
    "p": 7,
    "H": 8,
    "Y": 12,
    "N": 13,
    "B": 17,
    "M": 18,
    "L": 20,
}

VOWEL_PAIR_MAP = {
    "HK": 9,
    "HO": 10,
    "HL": 11,
    "NJ": 14,
    "NP": 15,
    "NL": 16,
    "ML": 19,
}

FINAL_SINGLE_MAP = {
    "R": 1,
    "r": 2,
    "-": 2,
    "S": 4,
    "E": 7,
    "F": 8,
    "A": 16,
    "Q": 17,
    "T": 19,
    "t": 20,
    "<": 20,
    "D": 21,
    "W": 22,
    "C": 23,
    "Z": 24,
    "X": 25,
    "V": 26,
    "G": 27,
}

FINAL_PAIR_MAP = {
    "RT": 3,
    "SW": 5,
    "SG": 6,
    "FR": 9,
    "FA": 10,
    "FQ": 11,
    "FT": 12,
    "FX": 13,
    "FV": 14,
    "FG": 15,
    "QT": 18,
}

INITIAL_JAMO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
VOWEL_JAMO = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
FINAL_JAMO = [
    "",
    "ㄱ",
    "ㄲ",
    "ㄳ",
    "ㄴ",
    "ㄵ",
    "ㄶ",
    "ㄷ",
    "ㄹ",
    "ㄺ",
    "ㄻ",
    "ㄼ",
    "ㄽ",
    "ㄾ",
    "ㄿ",
    "ㅀ",
    "ㅁ",
    "ㅂ",
    "ㅄ",
    "ㅅ",
    "ㅆ",
    "ㅇ",
    "ㅈ",
    "ㅊ",
    "ㅋ",
    "ㅌ",
    "ㅍ",
    "ㅎ",
]


def emit_initial_jamo(index: int) -> bytes:
    return bytes((0x41, index))


def emit_vowel_jamo(index: int) -> bytes:
    return bytes((0x41, 0x61 + index))


def emit_syllable(l_index: int, v_index: int, t_index: int = 0) -> bytes:
    return encode_modified(compose_syllable(INITIAL_JAMO[l_index], VOWEL_JAMO[v_index], FINAL_JAMO[t_index]))


def emit_literal(masked: str) -> bytes:
    return bytes((ord(masked) | 0x80,))


def simulate_console_output(stream: str) -> bytes:
    out = bytearray()
    state = STATE_IDLE
    l_index = 0
    v_char = ""
    v_index = 0
    t_first_char = ""
    t_second_char = ""
    t_index = 0

    for ch in stream:
        masked = chr(ord(ch) & 0x7F)

        if state == STATE_IDLE:
            if masked == SPAN_START:
                state = STATE_ACTIVE
            else:
                out.extend(ch.encode("utf-8"))
            continue

        if masked == SPAN_START:
            continue

        if masked == SPAN_END:
            if state == STATE_INITIAL:
                out.extend(emit_initial_jamo(l_index))
            elif state in (STATE_LV, STATE_LVV):
                out.extend(emit_syllable(l_index, v_index))
            elif state in (STATE_LVT, STATE_LVTT, STATE_LVVT, STATE_LVVTT):
                out.extend(emit_syllable(l_index, v_index, t_index))
            state = STATE_IDLE
            continue

        if state == STATE_ACTIVE:
            if masked in INITIAL_MAP:
                l_index = INITIAL_MAP[masked]
                state = STATE_INITIAL
            elif masked in VOWEL_SINGLE_MAP:
                out.extend(emit_vowel_jamo(VOWEL_SINGLE_MAP[masked]))
            else:
                out.extend(emit_literal(masked))
            continue

        if state == STATE_INITIAL:
            if masked in INITIAL_MAP:
                out.extend(emit_initial_jamo(l_index))
                l_index = INITIAL_MAP[masked]
            elif masked in VOWEL_SINGLE_MAP:
                v_char = masked
                v_index = VOWEL_SINGLE_MAP[masked]
                state = STATE_LV
            else:
                out.extend(emit_initial_jamo(l_index))
                out.extend(emit_literal(masked))
                state = STATE_ACTIVE
            continue

        if state == STATE_LV:
            pair = v_char + masked
            if pair in VOWEL_PAIR_MAP:
                v_index = VOWEL_PAIR_MAP[pair]
                state = STATE_LVV
            elif masked in FINAL_SINGLE_MAP:
                t_first_char = masked
                t_index = FINAL_SINGLE_MAP[masked]
                state = STATE_LVT
            elif masked in INITIAL_MAP:
                out.extend(emit_syllable(l_index, v_index))
                l_index = INITIAL_MAP[masked]
                state = STATE_INITIAL
            elif masked in VOWEL_SINGLE_MAP:
                out.extend(emit_syllable(l_index, v_index))
                out.extend(emit_vowel_jamo(VOWEL_SINGLE_MAP[masked]))
                state = STATE_ACTIVE
            else:
                out.extend(emit_syllable(l_index, v_index))
                out.extend(emit_literal(masked))
                state = STATE_ACTIVE
            continue

        if state == STATE_LVT:
            pair = t_first_char + masked
            if pair in FINAL_PAIR_MAP:
                t_second_char = masked
                t_index = FINAL_PAIR_MAP[pair]
                state = STATE_LVTT
            elif masked in INITIAL_MAP:
                out.extend(emit_syllable(l_index, v_index, t_index))
                l_index = INITIAL_MAP[masked]
                state = STATE_INITIAL
            elif masked in VOWEL_SINGLE_MAP:
                out.extend(emit_syllable(l_index, v_index))
                l_index = INITIAL_MAP[t_first_char]
                v_char = masked
                v_index = VOWEL_SINGLE_MAP[masked]
                state = STATE_LV
            else:
                out.extend(emit_syllable(l_index, v_index, t_index))
                out.extend(emit_literal(masked))
                state = STATE_ACTIVE
            continue

        if state == STATE_LVTT:
            if masked in INITIAL_MAP:
                out.extend(emit_syllable(l_index, v_index, t_index))
                l_index = INITIAL_MAP[masked]
                state = STATE_INITIAL
            elif masked in VOWEL_SINGLE_MAP:
                out.extend(emit_syllable(l_index, v_index, FINAL_SINGLE_MAP[t_first_char]))
                l_index = INITIAL_MAP[t_second_char]
                v_char = masked
                v_index = VOWEL_SINGLE_MAP[masked]
                state = STATE_LV
            else:
                out.extend(emit_syllable(l_index, v_index, t_index))
                out.extend(emit_literal(masked))
                state = STATE_ACTIVE
            continue

        if state == STATE_LVV:
            if masked in FINAL_SINGLE_MAP:
                t_first_char = masked
                t_index = FINAL_SINGLE_MAP[masked]
                state = STATE_LVVT
            elif masked in INITIAL_MAP:
                out.extend(emit_syllable(l_index, v_index))
                l_index = INITIAL_MAP[masked]
                state = STATE_INITIAL
            elif masked in VOWEL_SINGLE_MAP:
                out.extend(emit_syllable(l_index, v_index))
                out.extend(emit_vowel_jamo(VOWEL_SINGLE_MAP[masked]))
                state = STATE_ACTIVE
            else:
                out.extend(emit_syllable(l_index, v_index))
                out.extend(emit_literal(masked))
                state = STATE_ACTIVE
            continue

        if state == STATE_LVVT:
            pair = t_first_char + masked
            if pair in FINAL_PAIR_MAP:
                t_second_char = masked
                t_index = FINAL_PAIR_MAP[pair]
                state = STATE_LVVTT
            elif masked in INITIAL_MAP:
                out.extend(emit_syllable(l_index, v_index, t_index))
                l_index = INITIAL_MAP[masked]
                state = STATE_INITIAL
            elif masked in VOWEL_SINGLE_MAP:
                out.extend(emit_syllable(l_index, v_index))
                l_index = INITIAL_MAP[t_first_char]
                v_char = masked
                v_index = VOWEL_SINGLE_MAP[masked]
                state = STATE_LV
            else:
                out.extend(emit_syllable(l_index, v_index, t_index))
                out.extend(emit_literal(masked))
                state = STATE_ACTIVE
            continue

        if masked in INITIAL_MAP:
            out.extend(emit_syllable(l_index, v_index, t_index))
            l_index = INITIAL_MAP[masked]
            state = STATE_INITIAL
        elif masked in VOWEL_SINGLE_MAP:
            out.extend(emit_syllable(l_index, v_index, FINAL_SINGLE_MAP[t_first_char]))
            l_index = INITIAL_MAP[t_second_char]
            v_char = masked
            v_index = VOWEL_SINGLE_MAP[masked]
            state = STATE_LV
        else:
            out.extend(emit_syllable(l_index, v_index, t_index))
            out.extend(emit_literal(masked))
            state = STATE_ACTIVE

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
            case_id="console_nested_ctrl_k_is_ignored",
            actual=simulate_console_output(SPAN_START + "R" + SPAN_START + "K" + SPAN_END),
            expected=bytes.fromhex("4c00"),
        ),
        require_equal(
            case_id="console_span_literals_set_high_bit",
            actual=simulate_console_output(SPAN_START + "!9" + SPAN_END),
            expected=bytes.fromhex("a1b9"),
        ),
        require_equal(
            case_id="console_standalone_h_then_k_emits_two_vowels",
            actual=simulate_console_output(SPAN_START + "HK" + SPAN_END),
            expected=bytes.fromhex("41694161"),
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
