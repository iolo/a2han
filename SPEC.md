# a2han Specification

## Scope

This document defines the externally visible behavior of `a2han`.

It is the implementation target for:

- the host-side converter
- the resident Apple II program
- utilities such as `HCAT`
- future tests and golden vectors

Assembly source remains the authority for exact machine-level details such as
entry points, memory locations, register usage, and hook installation
mechanics. This document defines behavior, not binary layout.

## System Model

`a2han` operates across three encoding domains:

1. `utf8`
2. `modified`
3. `nbytes`

### Design Analogy

The intended mental model is:

- modern systems: `utf8 bytes -> unicode code points -> rendered glyphs`
- `a2han`: `nbytes bytes -> modified code points -> rendered glyphs`

This analogy is useful, but it is not exact.

- UTF-8 is a standardized byte encoding of Unicode code points.
- Public `nbytes` is a mixed-text transport.
- Its delimited payload is closer to a byte-oriented Hangul input grammar that
  composes jamo-like symbols and then maps the result into `modified`.

Use this analogy to reason about layering, not to assume exact equivalence.

### `utf8`

- Host-side UTF-8 byte streams.
- Decodes to Unicode scalar values, practically limited to Hangul syllables,
  Hangul jamo, and ASCII for this project.
- Used by host tools and documentation.

### `modified`

- A framebuffer-oriented remapping derived from Unicode.
- Intended to be written into Apple II text memory and interpreted by the
  AppleII-VGA custom firmware.
- Not standard Unicode.

### `nbytes`

- A byte-oriented Hangul input representation that avoids Applesoft BASIC's
  MSB/token conflicts.
- Used for delimited inline Hangul input and text interchange where direct
  framebuffer codes are not appropriate.
- Public `nbytes` uses plain text as the default mode.
- Bytes inside a `Ctrl-K` ... `Ctrl-E` span are interpreted as the internal
  Hangul syllable grammar rather than literal ASCII text.

## Runtime Paths

There are three relevant runtime paths:

### Keyboard Path

1. User enters normal ASCII or a delimited `nbytes` sequence.
2. `a2han` intercepts keyboard input through KSW.
3. Bytes inside the delimiter pair are parsed as the internal Hangul payload grammar.
4. Parsed Hangul is transcoded to `modified`.
5. The resulting bytes are emitted through the display/output path.

### Console Output Path

1. Program output reaches CSW.
2. `a2han` inspects the outgoing stream.
3. Delimited Hangul data is recognized and transcoded.
4. Transcoded bytes are written in a form compatible with the Apple II text
   framebuffer and AppleII-VGA custom firmware.

Resident fail-soft behavior on this path is:

- stray `Ctrl-E` outside an active span passes through unchanged
- nested `Ctrl-K` inside an active span is treated as literal payload data
- if a span overflows the resident buffer, the closing `Ctrl-E` flushes the
  buffered span back out as raw delimited text rather than emitting partial
  Hangul conversion
- if output ends before `Ctrl-E` arrives, the span remains unterminated and no
  Hangul conversion occurs for the buffered bytes

### File/Host Conversion Path

1. Host data is read as `utf8`, `modified`, or `nbytes`.
2. `hconv.py` converts between encodings according to this specification.
3. `HCAT` and other utilities may reuse the same conversion rules.

## Delimiter Semantics

Delimited Hangul input is framed by:

- `Ctrl-K` (`0x0B`): start delimiter
- `Ctrl-E` (`0x05`): end delimiter

Normative behavior:

- Bytes outside delimiters are treated as non-Hangul data and pass through
  unchanged unless another feature explicitly says otherwise.
- Bytes inside delimiters are parsed as the internal Hangul payload grammar.
- The delimiters themselves are control syntax and are not rendered as text.
- An empty delimited sequence is valid and produces no Hangul output.

Open point:

- Behavior for nested delimiters, missing end delimiters, or invalid `nbytes`
  sequences differs by environment.
- Resident code should treat nested start delimiters as literal data inside the
  active `nbytes` span.
- Resident code should treat a missing end delimiter as an unterminated span and
  fail soft.
- Host-side conversion remains strict: malformed delimited input is still an
  error rather than resident-style fail-soft behavior.

## `nbytes` Encoding

### Purpose

Applesoft BASIC uses the MSB to distinguish plain characters from tokens.
Because of that, Hangul cannot be introduced by simply setting the high bit on
ASCII-like bytes. `nbytes` exists to encode Hangul using ordinary bytes.

### Mapping Table

The current documented mapping is:

```text
A: ㅁ, B: ㅠ, C: ㅊ, D: ㅇ, E: ㄷ, F: ㄹ, G: ㅎ, H: ㅗ, I: ㅑ, J: ㅓ,
K: ㅏ, L: ㅣ, M: ㅡ, N: ㅜ, O: ㅐ, P: ㅔ, Q: ㅂ, R: ㄱ, S: ㄴ, T: ㅅ,
U: ㅕ, V: ㅍ, W: ㅈ, X: ㅌ, Y: ㅛ, Z: ㅋ,
e: ㄸ, o: ㅒ, p: ㅖ, q: ㅃ, r: ㄲ, t: ㅆ, w: ㅉ
```

This table defines the base symbol inventory. `nbytes` follows a composition
model similar to the standard two-beolsik keyboard layout, but with this
project's own letter assignment:

- single symbols map to basic jamo
- lowercase symbols are used only for `ㄲ`, `ㄸ`, `ㅃ`, `ㅆ`, `ㅉ`, `ㅒ`, and `ㅖ`
- compound vowels and compound final consonants are represented as multi-byte
  sequences of base symbols

### Compound Jamo Sequences

Lowercase letters are reserved for the single-byte symbols already defined in
the base table:

```text
e: ㄸ, o: ㅒ, p: ㅖ, q: ㅃ, r: ㄲ, t: ㅆ, w: ㅉ
```

Compound jamo are encoded as multi-byte sequences of their component base
symbols:

```text
HK: ㅘ, HO: ㅙ, HL: ㅚ
NJ: ㅝ, NP: ㅞ, NL: ㅟ
ML: ㅢ

RT: ㄳ, SW: ㄵ, SG: ㄶ
FR: ㄺ, FA: ㄻ, FQ: ㄼ, FT: ㄽ, FX: ㄾ, FV: ㄿ, FG: ㅀ
QT: ㅄ
```

Standalone jamo are representable directly:

- basic jamo use the one-byte mapping above
- double consonants use the documented lowercase single-byte forms
- compound vowels use the multi-byte sequences in this section
- compound final clusters are not standalone tokens by default; they become
  meaningful only when assigned to the `T` position during syllable composition

### Composition Rules

The delimited `nbytes` payload is a composition grammar, not a direct
byte-to-codepoint map.

For delimited payload `nbytes -> utf8` conversion, parse greedily from left to
right using the following model:

1. Decode each byte or byte pair into a neutral jamo-like token stream using
   the base table and the compound-jamo table above.
2. Attempt to form a Hangul syllable by assigning positional roles:
   `L` initial consonant + `V` medial vowel + optional `T` final consonant.
3. Use standard Unicode Hangul composition:
   `0xAC00 + (L_index * 21 * 28) + (V_index * 28) + T_index`
4. Use maximal munch for `V` and `T`.
5. If a potential final consonant can also begin the next syllable, treat it as
   final only when the following token cannot start a valid medial sequence for
   the current syllable split. This matches normal two-beolsik parsing.

Important interpretation note:

- outside a composed syllable, tokens are just consonants (`ja-eum`) or vowels
  (`mo-eum`)
- `choseong` and `jongseong` are positional roles assigned during syllable
  composition, not inherent token identities
- consecutive consonant bytes do not merge into a doubled consonant unless the
  explicit lowercase doubled token is used; for example, `RR` is `ㄱ` + `ㄱ`,
  not `ㄲ`

Normative token classes:

- valid initial consonants:
  `ㄱ ㄲ ㄴ ㄷ ㄸ ㄹ ㅁ ㅂ ㅃ ㅅ ㅆ ㅇ ㅈ ㅉ ㅊ ㅋ ㅌ ㅍ ㅎ`
- valid medial vowels:
  `ㅏ ㅐ ㅑ ㅒ ㅓ ㅔ ㅕ ㅖ ㅗ ㅘ ㅙ ㅚ ㅛ ㅜ ㅝ ㅞ ㅟ ㅠ ㅡ ㅢ ㅣ`
- valid final consonants:
  empty, `ㄱ ㄲ ㄳ ㄴ ㄵ ㄶ ㄷ ㄹ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅁ ㅂ ㅄ ㅅ ㅆ ㅇ ㅈ ㅊ ㅋ ㅌ ㅍ ㅎ`

Fallback rules:

- an isolated consonant token that cannot participate in a syllable is emitted
  as a standalone consonant jamo
- an isolated vowel token that cannot participate in a syllable is emitted as a
  standalone vowel jamo
- a compound final cluster token should not be emitted as a standalone final by
  default; if no valid syllable uses it as `T`, resident behavior may fail soft
  rather than invent a standalone `jongseong`
- ASCII digits, spaces, and punctuation bytes that are not part of the mapping
  pass through unchanged when they appear inside a delimited `nbytes` span
- an invalid byte terminates host-side conversion with an error

### Canonical `utf8 -> nbytes` Rules

For `utf8 -> nbytes`, emit plain text by default and use the shortest canonical
internal payload for each encodable Hangul character:

- ASCII text outside Hangul runs passes through unchanged
- precomposed Hangul syllables are decomposed into `L`, `V`, optional `T`, then
  re-encoded as canonical internal `nbytes` payloads
- standalone Hangul jamo are encoded using the base or compound-jamo table
- each encodable Hangul character is wrapped in `Ctrl-K` ... `Ctrl-E`

Canonical examples:

```text
가 -> <Ctrl-K>RK<Ctrl-E>
각 -> <Ctrl-K>RKR<Ctrl-E>
과 -> <Ctrl-K>RHK<Ctrl-E>
괜 -> <Ctrl-K>RHOS<Ctrl-E>
한 -> <Ctrl-K>GKS<Ctrl-E>
힣 -> <Ctrl-K>GLG<Ctrl-E>
ㅘ -> <Ctrl-K>HK<Ctrl-E>
ㄳ -> <Ctrl-K>RT<Ctrl-E>
```

## `modified` Encoding

### Purpose

Decoded Hangul code points cannot be written directly into the Apple II text
framebuffer without colliding with Apple II character semantics.

Relevant Apple II text-space constraints:

- ASCII `0x00-0x7F` appears as `0x80-0xFF`
- `0x00-0x4F` corresponds to inverse characters
- `0x40-0x7F` corresponds to flash characters and MouseText

`a2han` therefore remaps Hangul codepoints into a region interpreted by the
custom AppleII-VGA firmware.

### Mapping Rules

- Hangul syllables `0xAC00-0xD7A3` map to `0x4C00-0x77A3`
- Hangul jamo `0x1100-0x11FF` map to `0x4100-0x41FF`

Derived formulas over decoded Unicode code points:

- syllable: `modified = unicode - 0x6000`
- jamo: `modified = unicode - 0xD000`

Inverse formulas to recover decoded Unicode code points:

- syllable: `unicode = modified + 0x6000`
- jamo: `unicode = modified + 0xD000`

These ranges are part of the effective firmware ABI.

## Data Examples

### BASIC Output Example

Input:

```text
PRINT "ABC";CHR$(11);"GKS";CHR$(5)
```

Meaning:

- `ABC` is ordinary ASCII
- `CHR$(11)` starts an `nbytes` sequence
- `GKS` encodes the Hangul syllable `한`
- `CHR$(5)` ends the sequence

Expected visible result:

```text
ABC한
```

Documented resulting text bytes:

```text
41 42 43 c1 c2 c3 75 5c
```

Interpretation note:

- The ASCII display bytes and the Hangul `modified` bytes live in different
  representational layers. The exact staging of those bytes through hooks and
  framebuffer writes should be verified against the assembly implementation.

### Keyboard Input Example

Input:

```text
ABC<Ctrl-K>GKS<Ctrl-E>
```

Expected visible result:

```text
ABC한
```

Documented framebuffer bytes:

```text
c1 c2 c3 75 5c
```

## Required Error Semantics

Host-side policy:

- invalid `nbytes` byte: fail with error
- invalid byte inside a delimited `nbytes` span: fail with error
- unterminated delimited `nbytes` span: fail with error
- stray `Ctrl-E` outside a delimited span: pass through unchanged
- invalid UTF-8 input: fail with error
- decoded code points outside ASCII and supported Hangul ranges: fail with error
- out-of-range `modified` values: fail with error
- odd-length `modified` byte stream: fail with error

Resident policy:

- malformed delimited sequence: fail soft
- unterminated delimited sequence: fail soft
- preserve machine stability over perfect fidelity
- prefer visible pass-through or dropped conversion over buffer corruption

## Conformance Targets

The following components should conform to this document:

- `hconv.py`
- `a2han.s`
- `hcat.s`
- Applesoft demo cases
- host-side tests and golden vectors

## Pending Decisions

The remaining unresolved points are narrower:

1. Whether CSW sees raw delimiters or already-processed bytes in every target
   usage mode.
2. Exact resident lifecycle: install-only, reinstall-safe, or uninstallable.
3. Whether resident fail-soft behavior should pass malformed spans through
   literally or suppress only the broken fragment.
