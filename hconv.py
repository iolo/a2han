#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


class ConversionError(Exception):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


ENCODE_BASE_NBYTES_TO_JAMO = {
    "A": "ㅁ",
    "B": "ㅠ",
    "C": "ㅊ",
    "D": "ㅇ",
    "E": "ㄷ",
    "F": "ㄹ",
    "G": "ㅎ",
    "H": "ㅗ",
    "I": "ㅑ",
    "J": "ㅓ",
    "K": "ㅏ",
    "L": "ㅣ",
    "M": "ㅡ",
    "N": "ㅜ",
    "O": "ㅐ",
    "P": "ㅔ",
    "Q": "ㅂ",
    "R": "ㄱ",
    "S": "ㄴ",
    "T": "ㅅ",
    "U": "ㅕ",
    "V": "ㅍ",
    "W": "ㅈ",
    "X": "ㅌ",
    "Y": "ㅛ",
    "Z": "ㅋ",
    "e": "ㄸ",
    "o": "ㅒ",
    "p": "ㅖ",
    "q": "ㅃ",
    "r": "ㄲ",
    "t": "ㅆ",
    "w": "ㅉ",
}

LEGACY_DOUBLE_CONSONANT_NBYTES_TO_JAMO = {
    "-": "ㄲ",
    "=": "ㄸ",
    "*": "ㅃ",
    "<": "ㅆ",
    ">": "ㅉ",
}

BASE_NBYTES_TO_JAMO = dict(ENCODE_BASE_NBYTES_TO_JAMO)
BASE_NBYTES_TO_JAMO.update(LEGACY_DOUBLE_CONSONANT_NBYTES_TO_JAMO)

COMPOUND_NBYTES_TO_JAMO = {
    "HK": "ㅘ",
    "HO": "ㅙ",
    "HL": "ㅚ",
    "NJ": "ㅝ",
    "NP": "ㅞ",
    "NL": "ㅟ",
    "ML": "ㅢ",
    "RT": "ㄳ",
    "SW": "ㄵ",
    "SG": "ㄶ",
    "FR": "ㄺ",
    "FA": "ㄻ",
    "FQ": "ㄼ",
    "FT": "ㄽ",
    "FX": "ㄾ",
    "FV": "ㄿ",
    "FG": "ㅀ",
    "QT": "ㅄ",
}

JAMO_TO_NBYTES = {value: key for key, value in ENCODE_BASE_NBYTES_TO_JAMO.items()}
JAMO_TO_NBYTES.update({value: key for key, value in COMPOUND_NBYTES_TO_JAMO.items()})

L_TABLE = [
    "ㄱ",
    "ㄲ",
    "ㄴ",
    "ㄷ",
    "ㄸ",
    "ㄹ",
    "ㅁ",
    "ㅂ",
    "ㅃ",
    "ㅅ",
    "ㅆ",
    "ㅇ",
    "ㅈ",
    "ㅉ",
    "ㅊ",
    "ㅋ",
    "ㅌ",
    "ㅍ",
    "ㅎ",
]

V_TABLE = [
    "ㅏ",
    "ㅐ",
    "ㅑ",
    "ㅒ",
    "ㅓ",
    "ㅔ",
    "ㅕ",
    "ㅖ",
    "ㅗ",
    "ㅘ",
    "ㅙ",
    "ㅚ",
    "ㅛ",
    "ㅜ",
    "ㅝ",
    "ㅞ",
    "ㅟ",
    "ㅠ",
    "ㅡ",
    "ㅢ",
    "ㅣ",
]

T_TABLE = [
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

L_SET = set(L_TABLE)
V_SET = set(V_TABLE)
T_SET = set(T_TABLE[1:])
ASCII_SAFE_NBYTES = set(" \t\r\n0123456789!\"#$%&'()*+,-./:;<=>?[\\]^_`{|}~")
SPAN_START = "\x0b"
SPAN_END = "\x01"
SPAN_START_BYTE = 0x0B
SPAN_END_BYTE = 0x01

BASE_NBYTES_BYTE_TO_JAMO = {ord(key): value for key, value in BASE_NBYTES_TO_JAMO.items()}
COMPOUND_NBYTES_BYTE_TO_JAMO = {
    (ord(key[0]), ord(key[1])): value for key, value in COMPOUND_NBYTES_TO_JAMO.items()
}
C_BYTES = {ord(ch) for ch in "Rr-SEe=FAQq*Tt<DWw>CZXVG"}
CF_BYTES = {ord(ch) for ch in "Rr-SEFAQTt<DWCZXVG"}
CI_BYTES = {ord(ch) for ch in "e=q*w>"}
C1_BYTES = {ord(ch) for ch in "RSFQ"}
V_BYTES = {ord(ch) for ch in "KOIoJPUpHYNBML"}
V1_BYTES = {ord(ch) for ch in "HNM"}


@dataclass(frozen=True)
class ParsedInput:
    kind: str
    payload: str | bytes


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert between utf8, modified, and nbytes encodings.")
    parser.add_argument("-f", "--from-code", dest="from_code", required=True, choices=["utf8", "modified", "nbytes"])
    parser.add_argument("-t", "--to-code", dest="to_code", required=True, choices=["utf8", "modified", "nbytes"])
    parser.add_argument("-i", "--input", dest="input_path")
    parser.add_argument("-o", "--output", dest="output_path")
    parser.add_argument("--json", action="store_true", help="emit structured metadata to stdout")
    return parser.parse_args()


def read_input(path: str | None, encoding: str) -> ParsedInput:
    if path is None:
        raw = sys.stdin.buffer.read()
    else:
        raw = Path(path).read_bytes()

    if encoding in {"modified", "nbytes"}:
        return ParsedInput("bytes", raw)

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConversionError("invalid_utf8_input", f"invalid UTF-8 input: {exc}") from exc
    return ParsedInput("text", text)


def write_output(path: str | None, payload: str | bytes, encoding: str) -> None:
    if encoding in {"modified", "nbytes"}:
        data = ensure_bytes(payload)
    else:
        data = payload if isinstance(payload, bytes) else ensure_text(payload).encode("utf-8")

    if path is None:
        sys.stdout.buffer.write(data)
    else:
        Path(path).write_bytes(data)


def ensure_text(payload: str | bytes) -> str:
    if isinstance(payload, str):
        return payload
    raise TypeError("expected text payload")


def ensure_bytes(payload: str | bytes) -> bytes:
    if isinstance(payload, bytes):
        return payload
    raise TypeError("expected byte payload")


def decode_modified(raw: bytes) -> str:
    if len(raw) % 2:
        raise ConversionError("invalid_modified_length", "modified stream length must be even")

    chars: list[str] = []
    for i in range(0, len(raw), 2):
        code = (raw[i] << 8) | raw[i + 1]
        if 0x4100 <= code <= 0x41FF:
            chars.append(chr(code + 0xD000))
        elif 0x4C00 <= code <= 0x77A3:
            chars.append(chr(code + 0x6000))
        else:
            raise ConversionError("invalid_modified_codepoint", f"invalid modified code point: 0x{code:04x}")
    return "".join(chars)


def encode_modified(text: str) -> bytes:
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if 0x1100 <= cp <= 0x11FF:
            mapped = cp - 0xD000
        elif 0xAC00 <= cp <= 0xD7A3:
            mapped = cp - 0x6000
        else:
            raise ConversionError("unsupported_unicode_codepoint", f"cannot encode U+{cp:04X} as modified")
        out.extend(((mapped >> 8) & 0xFF, mapped & 0xFF))
    return bytes(out)


def compose_syllable(initial: str, medial: str, final: str = "") -> str:
    try:
        l_index = L_TABLE.index(initial)
        v_index = V_TABLE.index(medial)
        t_index = T_TABLE.index(final)
    except ValueError as exc:
        raise ConversionError("invalid_hangul_composition", "invalid Hangul composition triple") from exc
    return chr(0xAC00 + (l_index * 21 * 28) + (v_index * 28) + t_index)


def _append_passthrough_byte(out: list[str], value: int) -> None:
    out.append(chr(value))


def _flush_nbytes_state(
    out: list[str],
    state: str,
    initial: str | None,
    medial: str | None,
    final: str | None,
) -> None:
    if state == "S1":
        return
    if state == "S2":
        out.append(ensure_text(initial))
        return
    if state in {"S3", "S6"}:
        out.append(compose_syllable(ensure_text(initial), ensure_text(medial)))
        return
    if state in {"S4", "S5", "S7", "S8"}:
        out.append(compose_syllable(ensure_text(initial), ensure_text(medial), ensure_text(final)))
        return
    raise AssertionError(f"unknown nbytes state: {state}")


def decode_nbytes(raw: bytes) -> str:
    out: list[str] = []
    in_span = False
    state = "S1"
    initial: str | None = None
    initial_byte: int | None = None
    medial: str | None = None
    vowel_first_byte: int | None = None
    final: str | None = None
    final_first_byte: int | None = None
    final_first_jamo: str | None = None
    final_second_byte: int | None = None
    final_second_jamo: str | None = None

    def reset_buffer() -> None:
        nonlocal state, initial, initial_byte, medial, vowel_first_byte
        nonlocal final, final_first_byte, final_first_jamo, final_second_byte, final_second_jamo
        state = "S1"
        initial = None
        initial_byte = None
        medial = None
        vowel_first_byte = None
        final = None
        final_first_byte = None
        final_first_jamo = None
        final_second_byte = None
        final_second_jamo = None

    def flush_buffer() -> None:
        _flush_nbytes_state(out, state, initial, medial, final)
        reset_buffer()

    for value in raw:
        if not in_span:
            if value == SPAN_START_BYTE:
                in_span = True
                reset_buffer()
            else:
                _append_passthrough_byte(out, value)
            continue

        if value == SPAN_END_BYTE:
            flush_buffer()
            in_span = False
            continue

        if value == SPAN_START_BYTE:
            continue

        if value not in C_BYTES and value not in V_BYTES:
            flush_buffer()
            _append_passthrough_byte(out, value)
            continue

        if state == "S1":
            if value in C_BYTES:
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                state = "S2"
            else:
                out.append(BASE_NBYTES_BYTE_TO_JAMO[value])
            continue

        if state == "S2":
            if value in V_BYTES:
                medial = BASE_NBYTES_BYTE_TO_JAMO[value]
                vowel_first_byte = value
                state = "S3"
            else:
                out.append(ensure_text(initial))
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                state = "S2"
            continue

        if state == "S3":
            pair = (ensure_bytes(bytes([vowel_first_byte]))[0], value)
            if pair in COMPOUND_NBYTES_BYTE_TO_JAMO:
                medial = COMPOUND_NBYTES_BYTE_TO_JAMO[pair]
                state = "S6"
            elif value in CF_BYTES:
                final = BASE_NBYTES_BYTE_TO_JAMO[value]
                final_first_byte = value
                final_first_jamo = final
                state = "S4"
            elif value in CI_BYTES:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial)))
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                medial = None
                vowel_first_byte = None
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S2"
            else:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial)))
                out.append(BASE_NBYTES_BYTE_TO_JAMO[value])
                reset_buffer()
            continue

        if state == "S4":
            pair = (ensure_bytes(bytes([final_first_byte]))[0], value)
            if pair in COMPOUND_NBYTES_BYTE_TO_JAMO:
                final = COMPOUND_NBYTES_BYTE_TO_JAMO[pair]
                final_second_byte = value
                final_second_jamo = BASE_NBYTES_BYTE_TO_JAMO[value]
                state = "S5"
            elif value in C_BYTES:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial), ensure_text(final)))
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                medial = None
                vowel_first_byte = None
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S2"
            else:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial)))
                initial = ensure_text(final)
                initial_byte = final_first_byte
                medial = BASE_NBYTES_BYTE_TO_JAMO[value]
                vowel_first_byte = value
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S3"
            continue

        if state == "S5":
            if value in C_BYTES:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial), ensure_text(final)))
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                medial = None
                vowel_first_byte = None
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S2"
            else:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial), ensure_text(final_first_jamo)))
                initial = ensure_text(final_second_jamo)
                initial_byte = final_second_byte
                medial = BASE_NBYTES_BYTE_TO_JAMO[value]
                vowel_first_byte = value
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S3"
            continue

        if state == "S6":
            if value in CF_BYTES:
                final = BASE_NBYTES_BYTE_TO_JAMO[value]
                final_first_byte = value
                final_first_jamo = final
                state = "S7"
            elif value in CI_BYTES:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial)))
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                medial = None
                vowel_first_byte = None
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S2"
            else:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial)))
                out.append(BASE_NBYTES_BYTE_TO_JAMO[value])
                reset_buffer()
            continue

        if state == "S7":
            pair = (ensure_bytes(bytes([final_first_byte]))[0], value)
            if pair in COMPOUND_NBYTES_BYTE_TO_JAMO:
                final = COMPOUND_NBYTES_BYTE_TO_JAMO[pair]
                final_second_byte = value
                final_second_jamo = BASE_NBYTES_BYTE_TO_JAMO[value]
                state = "S8"
            elif value in C_BYTES:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial), ensure_text(final)))
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                medial = None
                vowel_first_byte = None
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S2"
            else:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial)))
                initial = ensure_text(final)
                initial_byte = final_first_byte
                medial = BASE_NBYTES_BYTE_TO_JAMO[value]
                vowel_first_byte = value
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S6"
            continue

        if state == "S8":
            if value in C_BYTES:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial), ensure_text(final)))
                initial = BASE_NBYTES_BYTE_TO_JAMO[value]
                initial_byte = value
                medial = None
                vowel_first_byte = None
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S2"
            else:
                out.append(compose_syllable(ensure_text(initial), ensure_text(medial), ensure_text(final_first_jamo)))
                initial = ensure_text(final_second_jamo)
                initial_byte = final_second_byte
                medial = BASE_NBYTES_BYTE_TO_JAMO[value]
                vowel_first_byte = value
                final = None
                final_first_byte = None
                final_first_jamo = None
                final_second_byte = None
                final_second_jamo = None
                state = "S3"
            continue

        raise AssertionError(f"unknown nbytes state: {state}")

    if in_span:
        raise ConversionError("unterminated_nbytes_span", "unterminated nbytes span")

    return "".join(out)


def decompose_syllable(ch: str) -> tuple[str, str, str]:
    code = ord(ch)
    if not (0xAC00 <= code <= 0xD7A3):
        raise ConversionError("unsupported_unicode_codepoint", f"U+{code:04X} is not a Hangul syllable")
    offset = code - 0xAC00
    l_index = offset // (21 * 28)
    v_index = (offset % (21 * 28)) // 28
    t_index = offset % 28
    return L_TABLE[l_index], V_TABLE[v_index], T_TABLE[t_index]


def encode_nbytes_syllables(text: str) -> bytes:
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if ch in ASCII_SAFE_NBYTES:
            out.extend(ch.encode("ascii"))
        elif 0xAC00 <= cp <= 0xD7A3:
            initial, medial, final = decompose_syllable(ch)
            out.extend(jamo_to_nbytes(initial).encode("ascii"))
            out.extend(jamo_to_nbytes(medial).encode("ascii"))
            if final:
                out.extend(jamo_to_nbytes(final).encode("ascii"))
        elif ch in JAMO_TO_NBYTES:
            out.extend(jamo_to_nbytes(ch).encode("ascii"))
        else:
            raise ConversionError("unsupported_unicode_codepoint", f"cannot encode U+{cp:04X} as nbytes syllables")
    return bytes(out)


def jamo_to_nbytes(ch: str) -> str:
    try:
        return JAMO_TO_NBYTES[ch]
    except KeyError as exc:
        raise ConversionError("unsupported_unicode_codepoint", f"cannot encode jamo {ch!r} as nbytes") from exc


def _is_hangul_encodable_in_nbytes(ch: str) -> bool:
    cp = ord(ch)
    return (0xAC00 <= cp <= 0xD7A3) or (ch in JAMO_TO_NBYTES)


def encode_nbytes(text: str) -> bytes:
    out = bytearray()

    for ch in text:
        if _is_hangul_encodable_in_nbytes(ch):
            out.append(SPAN_START_BYTE)
            out.extend(encode_nbytes_syllables(ch))
            out.append(SPAN_END_BYTE)
            continue
        cp = ord(ch)
        if cp > 0x7F:
            raise ConversionError("unsupported_unicode_codepoint", f"cannot encode U+{cp:04X} outside nbytes span")
        out.append(cp)

    return bytes(out)


def convert(from_code: str, to_code: str, payload: str | bytes) -> str | bytes:
    if from_code == to_code:
        return payload

    if from_code == "modified":
        text = decode_modified(ensure_bytes(payload))
    elif from_code == "nbytes":
        text = decode_nbytes(ensure_bytes(payload))
    else:
        text = ensure_text(payload)

    if to_code == "utf8":
        return text
    if to_code == "modified":
        return encode_modified(text)
    if to_code == "nbytes":
        return encode_nbytes(text)
    raise AssertionError(f"unsupported target encoding: {to_code}")


def maybe_emit_json(from_code: str, to_code: str, output: str | bytes) -> None:
    if isinstance(output, bytes):
        body = {"from": from_code, "to": to_code, "output_hex": output.hex()}
    else:
        body = {"from": from_code, "to": to_code, "output_text": output}
    json.dump(body, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def main() -> int:
    args = parse_args()
    try:
        parsed = read_input(args.input_path, args.from_code)
        output = convert(args.from_code, args.to_code, parsed.payload)
        if args.json:
            maybe_emit_json(args.from_code, args.to_code, output)
        else:
            write_output(args.output_path, output, args.to_code)
    except ConversionError as exc:
        print(f"{exc.code}: {exc.detail}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
