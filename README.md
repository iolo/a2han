# a2han

Hangul input/output support for Apple II systems using an
[AppleII-VGA card](https://github.com/markadev/AppleII-VGA) with
[custom firmware](https://github.com/iolo/AppleII-VGA).

This repository is a low-level Apple II project. The intended reader is someone
already comfortable with 6502-era constraints, Applesoft BASIC quirks, disk
images, and patched firmware behavior.

## Prerequisites

- [cc65/ca65](https://cc65.github.io/)
- [a2kit](https://github.com/dfgordon/a2kit): manipulate Apple II disk images (`.dsk`, `.po`)
- [AppleII-VGA](https://github.com/markadev/AppleII-VGA): VGA output for Apple II
- [AppleII-VGA Custom Firmware](https://github.com/iolo/AppleII-VGA): firmware support for the `modified` character mapping

## Build and Run

### Build the program

```
make
```

### Create Apple II DOS disk image

```
make dsk
```

### Create Apple II ProDOS disk image

```
make po
```

### Run the program

Boot the Apple II from the generated disk image, then run `A2HAN`:

```
] BRUN A2HAN
```

Run the Applesoft BASIC demo:

```
] RUN DEMO
```

Run `HCAT` to display a Hangul text file:

```
] BRUN HCAT
FILENAME: ...
ENCODING: (U)nicode, (M)odified, (N)bytes:
...
```

## Directory Structure

```
a2han.s         ; main program source code
demo.bas        ; demo program written in Applesoft BASIC
hcat.s          ; utility to display a Hangul text file on the Apple II screen
Makefile        ; build script
hconv.py        ; utility to convert between different encodings
build/          ; build output directory
    a2han.po    ; Apple II ProDOS disk image
    a2han.dsk   ; Apple II DOS disk image
```

## Technical Details

- The program is written in 6502 assembly language, and assembled using `ca65` from the `cc65` toolchain.
- The program hooks keyboard input (KSW) and console output (CSW) to provide Hangul input and output.
- Character sequences entered between `Ctrl-E` and `Ctrl-K` are treated as **N-byte Hangul** and transcoded into **modified Unicode** before reaching the text framebuffer.

### Runtime Model

- Keyboard path: intercept raw input, recognize Hangul sequences, transcode them, then emit display bytes.
- Output path: intercept console output, detect encoded Hangul sequences, and write framebuffer-compatible bytes.
- Rendering path: the AppleII-VGA custom firmware interprets the remapped code points and draws glyphs.

> Note: The custom AppleII-VGA firmware renders the `modified` encoding from the Apple II text framebuffer (`0x400-0x7FF`). That rendering logic is out of scope for this project; see the firmware source for details.

### N-byte Hangul Encoding

- Applesoft BASIC uses the MSB to distinguish ASCII characters from tokens, so the MSB cannot be reused for Hangul encoding.
- Instead, this project encodes Hangul characters as one or more bytes using the following mapping:

```
A: ㅁ, B: ㅠ, C: ㅊ, D: ㅇ, E: ㄷ, F: ㄹ, G: ㅎ, H: ㅗ, I: ㅑ, J: ㅓ,
K: ㅏ, L: ㅣ, M: ㅡ, N: ㅜ, O: ㅐ, P: ㅔ, Q: ㅂ, R: ㄱ, S: ㄴ, T: ㅅ,
U: ㅕ, V: ㅍ, W: ㅈ, X: ㅌ, Y: ㅛ, Z: ㅋ,
e: ㄸ, o: ㅒ, p: ㅖ, q: ㅃ, r: ㄲ, t: ㅆ, w: ㅉ,
...
```

### Modified Unicode Encoding

Standard UCS-2 conflicts with the [Apple II character set](https://en.wikipedia.org/wiki/Apple_II_character_set):

- ASCII characters `0x00-0x7F` are displayed as `0x80-0xFF` in the Apple II text framebuffer.
- `0x00-0x4F` maps to `INVERSE` characters.
- `0x40-0x7F` maps to `FLASH` characters and MouseText.

This project reuses the `FLASH` range for Hangul characters:

- Hangul syllables `0xAC00-0xD7A3` are mapped to `0x4C00-0x77A3`
- Hangul jamo `0x1100-0x11FF` are mapped to `0x4100-0x41FF`

### Examples

- `PRINT "ABC";CHR$(5);"RK";CHR$(11)` in Applesoft BASIC displays `ABC가`.
  The corresponding text buffer bytes are `41 42 43 c1 c2 c3 4c 00`.
- Typing `ABC<Ctrl-E>RK<Ctrl-K>` from the keyboard also displays `ABC가`.
  The corresponding text framebuffer bytes are `c1 c2 c3 4c 00`.

Interpretation:

- `CHR$(5)` is `Ctrl-E`, the start delimiter for N-byte Hangul input.
- `CHR$(11)` is `Ctrl-K`, the end delimiter.
- `RK` is the N-byte input sequence for `가`.
- `4c 00` is the `modified` code point written for that syllable.

## Host Utilities

### Convert Between `N-byte Hangul` and `Unicode`

```
python3 hconv.py <options>
  -f, --from-code=<encoding>   `unicode`, `modified`, or `nbytes`
  -t, --to-code=<encoding>     `unicode`, `modified`, or `nbytes`
  -i, --input <file>           input file; reads from stdin if omitted
  -o, --output <file>          output file; writes to stdout if omitted
  -h, --help                   show this help message and exit
```

## Notes for Humans and Agents

- Treat the AppleII-VGA firmware mapping as part of the ABI. Do not change the remap ranges casually.
- Distinguish clearly between three layers: `nbytes` input encoding, `modified` framebuffer encoding, and Unicode on the host side.
- When documenting behavior, describe which path is being discussed: keyboard hook, console hook, file conversion, or firmware rendering.
- The README describes encoding intent and externally visible behavior. Assembly source remains the authority for exact hook and memory semantics.

---
May the **SOURCE** be with you!
