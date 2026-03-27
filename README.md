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

Status: active target. `make dsk` now packages the DOS-specific `A2HAN`
binary built from the shared `a2han.s` source.

### Create Apple II ProDOS disk image

```
make po
```

Status: active target. `make po` packages the ProDOS-specific `A2HAN` binary
built from the shared `a2han.s` source.

### Run the program

Boot the Apple II from the generated disk image, then load `A2HAN`.
The current manual load/install path is:

```
] BLOAD A2HAN
] CALL 24576
```

This applies to both the ProDOS and DOS 3.3 disk images. `BRUN A2HAN` should
not yet be treated as the primary development workflow.

Run the Applesoft BASIC demo:

```
] RUN DEMO
```

Status: TODO/TBD.

Run `A2HVIEW` to display a Hangul text file:

```
] BRUN A2HVIEW
FILENAME: ...
ENCODING: (U)nicode, (M)odified, (N)bytes:
...
```

Status: basic implementation is in place. `A2HVIEW` can prompt for a filename and
source encoding, then display:

- `utf8`: ASCII plus modern Hangul syllables/jamo transcoded to `modified`
- `modified`: raw framebuffer-oriented Hangul bytes streamed directly
- `nbytes`: mixed text plus delimited Hangul spans decoded and rendered

Current limits:

- UTF-8 support is intentionally narrow; unsupported non-Hangul Unicode code
  points stop the display with an error.
- `nbytes` spans are validated and must terminate cleanly.
- `A2HVIEW` now renders file content by writing Apple II text-page memory
  directly rather than using stdio/conio character output for the content
  stream.
- `A2HVIEW` no longer scrolls; when it reaches the bottom line it waits for a key
  press, clears the screen, and resumes from the top.
- Real Apple II testing found that `A2HVIEW` now displays content correctly, but
  it can still crash to the monitor after some amount of output. This remains
  under investigation.

The generated disk images currently bundle matching pangram samples for each
mode:

- `PANGUTF8` for `ENCODING: U`
- `PANGMOD` for `ENCODING: M`
- `PANGNBYTES` for `ENCODING: N`

These samples are the current recommended smoke-test inputs for `A2HVIEW` on real
hardware.

## Directory Structure

```
a2han.s         ; main program source code
a2hview.c       ; interactive Hangul file viewer built with cc65
Makefile        ; build script
hconv.py        ; utility to convert between different encodings
build/          ; build output directory
    A2HAN.PRO   ; ProDOS-specific build from a2han.s
    A2HAN.DOS   ; DOS 3.3-specific build from a2han.s
    A2HVIEW     ; Apple II file viewer binary
    a2han.po    ; Apple II ProDOS disk image
    a2han.dsk   ; Apple II DOS disk image
```

## Technical Details

- `a2han` is written in 6502 assembly language and assembled using the `cc65`
  toolchain.
- `a2han` is built from a single shared source file, `a2han.s`, with
  build-time conditionals selecting either the ProDOS BASIC vectors or the DOS
  3.3 `KSW`/`CSW` hook path.
- `a2hview` now provides a minimal interactive file-view utility for `utf8`,
  `modified`, and `nbytes` input files.
- The resident install path now supports both ProDOS and DOS 3.3 builds.
- The resident parser currently supports delimiter detection, buffered spans,
  simple syllables, compound vowels, compound final clusters in syllable
  position, and explicit lowercase doubled tokens.
- The program hooks keyboard input and console output to provide Hangul input
  and output.
- Plain text is the default mode.
- Public `nbytes` is a mixed-text encoding: plain text passes through unchanged, and bytes between `Ctrl-K` and `Ctrl-A` are treated as Hangul payloads.
- The bytes inside a delimited `nbytes` span use the internal Hangul composition grammar and are transcoded into **modified Unicode** before reaching the text framebuffer.

Design model:

- On a modern machine, UTF-8 is decoded into Unicode before rendering.
- In this project, `nbytes` is decoded/transcoded into `modified` before rendering.
- The analogy is useful, but not exact: public `nbytes` is a mixed-text transport, and its delimited payload is closer to an input grammar over Hangul components than a strict byte serialization of `modified`.

### Runtime Model

- Keyboard path: intercept raw input, preserve `Ctrl-K ... Ctrl-A` text as
  `nbytes` for Applesoft/BASIC storage, and optionally provide user feedback
  such as delimiter bells. The keyboard hook does not render Hangul directly.
- Output path: intercept console output, detect encoded Hangul sequences, and write framebuffer-compatible bytes.
- Rendering path: the AppleII-VGA custom firmware interprets the remapped code points and draws glyphs.
- Standalone fallback should be understood as neutral `ja-eum` / `mo-eum`
  tokens. Positional roles like `choseong` and `jongseong` exist only inside a
  composed syllable.

### Hook Rules

- ProDOS and DOS 3.3 do not use equivalent hook chaining semantics even though
  both expose input/output vectors.
- In the ProDOS build, `a2han` installs into the BASIC vectors and chains
  through the original saved vectors for pass-through behavior.
- In the DOS 3.3 build, `a2han` installs into `CSW`/`KSW` and must call
  `DOSFET` (`JSR $03EA`) immediately after patching those vectors.
- In the DOS 3.3 build, pass-through must not chain through the pre-install
  `CSW`/`KSW` targets. That path can loop back into the hook machinery and
  recurse.
- Instead, DOS 3.3 pass-through should use stable ROM entry points:
  `COUT1` for output and `KEYIN` for input.
- Practical rule: ProDOS chains through saved vectors; DOS 3.3 bypasses saved
  hook targets and uses ROM routines after installing `CSW`/`KSW`.

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

Standard Hangul code points cannot be written directly into the
[Apple II character set](https://en.wikipedia.org/wiki/Apple_II_character_set)
space without conflicts:

- ASCII characters `0x00-0x7F` are displayed as `0x80-0xFF` in the Apple II text framebuffer.
- `0x00-0x4F` maps to `INVERSE` characters.
- `0x40-0x7F` maps to `FLASH` characters and MouseText.

This project reuses the `FLASH` range for Hangul characters:

- Hangul syllables `0xAC00-0xD7A3` are mapped to `0x4C00-0x77A3`
- Hangul jamo `0x1100-0x11FF` are mapped to `0x4100-0x41FF`

### Examples

- `PRINT "ABC";CHR$(11);"GKS";CHR$(5)` in Applesoft BASIC displays `ABC한`.
  The corresponding text buffer bytes are `41 42 43 c1 c2 c3 75 5c`.
- Typing `ABC<Ctrl-K>GKS<Ctrl-A>` from the keyboard also displays `ABC한`.
  The corresponding text framebuffer bytes are `c1 c2 c3 75 5c`.
- `RHK` composes `과`.
- `RHOS` composes `괜`.

Interpretation:

- `CHR$(11)` is `Ctrl-K`, the start delimiter for N-byte Hangul input.
- `CHR$(1)` is `Ctrl-A`, the end delimiter.
- `GKS` is the internal Hangul payload for `한`.
- `75 5c` is the `modified` code point written for that syllable.

## Host Utilities

### Convert Between `UTF-8`, `Modified Unicode`, and `N-byte Hangul`

```
python3 hconv.py <options>
  -f, --from-code=<encoding>   `utf8`, `modified`, or `nbytes`
  -t, --to-code=<encoding>     `utf8`, `modified`, or `nbytes`
  -i, --input <file>           input file; reads from stdin if omitted
  -o, --output <file>          output file; writes to stdout if omitted
  -h, --help                   show this help message and exit
```

## Notes for Humans and Agents

- Treat the AppleII-VGA firmware mapping as part of the ABI. Do not change the remap ranges casually.
- Distinguish clearly between three layers: public `nbytes` transport, internal Hangul payload grammar, and `modified` framebuffer encoding.
- When documenting behavior, describe which path is being discussed: keyboard hook, console hook, file conversion, or firmware rendering.
- The README describes encoding intent and externally visible behavior. Assembly source remains the authority for exact hook and memory semantics.
- Keep unfinished pieces like `demo.bas` visible in the docs, but do not label
  shipped build targets as TODO when they are already implemented.

---
May the **SOURCE** be with you!
