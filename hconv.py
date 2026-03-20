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


BASE_NBYTES_TO_JAMO = {
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

JAMO_TO_NBYTES = {value: key for key, value in BASE_NBYTES_TO_JAMO.items()}
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
CTRL_K = "\x0b"
CTRL_E = "\x05"


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

    if encoding == "modified":
        return ParsedInput("bytes", raw)

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConversionError("invalid_utf8_input", f"invalid UTF-8 input: {exc}") from exc
    return ParsedInput("text", text)


def write_output(path: str | None, payload: str | bytes, encoding: str) -> None:
    if encoding == "modified":
        data = ensure_bytes(payload)
    else:
        data = ensure_text(payload).encode("utf-8")

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


def tokenize_nbytes_syllables(text: str) -> list[str]:
    tokens: list[str] = []
    i = 0
    while i < len(text):
        pair = text[i : i + 2]
        if len(pair) == 2 and pair in COMPOUND_NBYTES_TO_JAMO:
            tokens.append(COMPOUND_NBYTES_TO_JAMO[pair])
            i += 2
            continue

        ch = text[i]
        if ch in BASE_NBYTES_TO_JAMO:
            tokens.append(BASE_NBYTES_TO_JAMO[ch])
            i += 1
            continue
        if ch in ASCII_SAFE_NBYTES:
            tokens.append(ch)
            i += 1
            continue
        raise ConversionError("invalid_nbytes_byte", f"invalid nbytes byte: {ch!r}")
    return tokens


def compose_syllable(initial: str, medial: str, final: str = "") -> str:
    try:
        l_index = L_TABLE.index(initial)
        v_index = V_TABLE.index(medial)
        t_index = T_TABLE.index(final)
    except ValueError as exc:
        raise ConversionError("invalid_hangul_composition", "invalid Hangul composition triple") from exc
    return chr(0xAC00 + (l_index * 21 * 28) + (v_index * 28) + t_index)


def decode_nbytes_syllables(text: str) -> str:
    tokens = tokenize_nbytes_syllables(text)
    out: list[str] = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok in L_SET and i + 1 < len(tokens) and tokens[i + 1] in V_SET:
            initial = tok
            medial = tokens[i + 1]
            final = ""
            consumed = 2

            if i + 2 < len(tokens) and tokens[i + 2] in T_SET:
                candidate = tokens[i + 2]
                if i + 3 < len(tokens) and tokens[i + 3] in V_SET and candidate in L_SET:
                    final = ""
                else:
                    final = candidate
                    consumed = 3

            out.append(compose_syllable(initial, medial, final))
            i += consumed
            continue

        if tok in L_SET or tok in V_SET or tok in T_SET:
            out.append(tok)
            i += 1
            continue

        out.append(tok)
        i += 1

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


def encode_nbytes_syllables(text: str) -> str:
    out: list[str] = []
    for ch in text:
        cp = ord(ch)
        if ch in ASCII_SAFE_NBYTES:
            out.append(ch)
        elif 0xAC00 <= cp <= 0xD7A3:
            initial, medial, final = decompose_syllable(ch)
            out.append(jamo_to_nbytes(initial))
            out.append(jamo_to_nbytes(medial))
            if final:
                out.append(jamo_to_nbytes(final))
        elif ch in JAMO_TO_NBYTES:
            out.append(jamo_to_nbytes(ch))
        else:
            raise ConversionError("unsupported_unicode_codepoint", f"cannot encode U+{cp:04X} as nbytes syllables")
    return "".join(out)


def jamo_to_nbytes(ch: str) -> str:
    try:
        return JAMO_TO_NBYTES[ch]
    except KeyError as exc:
        raise ConversionError("unsupported_unicode_codepoint", f"cannot encode jamo {ch!r} as nbytes") from exc


def decode_nbytes(text: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch != CTRL_K:
            out.append(ch)
            i += 1
            continue

        end = text.find(CTRL_E, i + 1)
        if end == -1:
            raise ConversionError("unterminated_nbytes_span", "unterminated nbytes span")
        payload = text[i + 1 : end]
        out.append(decode_nbytes_syllables(payload))
        i = end + 1

    return "".join(out)


def _is_hangul_encodable_in_nbytes(ch: str) -> bool:
    cp = ord(ch)
    return (0xAC00 <= cp <= 0xD7A3) or (ch in JAMO_TO_NBYTES)


def encode_nbytes(text: str) -> str:
    out: list[str] = []

    for ch in text:
        if _is_hangul_encodable_in_nbytes(ch):
            out.append(CTRL_K)
            out.append(encode_nbytes_syllables(ch))
            out.append(CTRL_E)
            continue
        out.append(ch)

    return "".join(out)


def convert(from_code: str, to_code: str, payload: str | bytes) -> str | bytes:
    if from_code == to_code:
        return payload

    if from_code == "modified":
        text = decode_modified(ensure_bytes(payload))
    elif from_code == "nbytes":
        text = decode_nbytes(ensure_text(payload))
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
