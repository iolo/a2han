# a2han Plan

## Goal

Build a resident Apple II Hangul input/output system plus host-side utilities
and disk images, with behavior anchored in [`SPEC.md`](/home/iolo/workspace/retro/a2han/SPEC.md).

## Strategy

Do not start with resident hook code.

The project should advance in this order:

1. lock down behavior
2. implement a host-side reference
3. build packaging and tooling
4. add resident assembly incrementally
5. verify against golden vectors and manual Apple II tests

## Milestones

### M1. Freeze Specification

Deliverables:

- `SPEC.md` with exact encoding and error semantics
- resolved open points around `nbytes` grammar
- at least a small set of golden examples

Exit criteria:

- no unresolved ambiguity for host-side conversion logic
- enough precision to implement `hconv.py` without guessing

Current risks:

- incomplete `nbytes` table
- unspecified composition rules
- undefined malformed-input behavior

### M2. Host Reference Converter

Deliverables:

- `hconv.py`
- conversion support for `utf8`, `modified`, and `nbytes`
- command-line interface matching the README
- golden tests or fixtures

Exit criteria:

- conversions are reproducible
- known examples round-trip where expected
- error reporting is deterministic

Why this comes first:

- it becomes the executable spec
- it reduces risk before writing 6502 assembly

### M3. Build and Packaging Scaffold

Status:

- active for both ProDOS and DOS 3.3 packaging
- `make build` now produces separate `A2HAN.PRO` and `A2HAN.DOS` binaries from
  the shared `a2han.s` source
- `make po` and `make dsk` package the matching OS-specific binary into each
  image

Deliverables:

- `Makefile`
- `build/` output convention
- `make`, `make dsk`, and `make po` targets
- integration with `cc65/ca65` and `a2kit`

Exit criteria:

- a clean build produces binaries and disk images
- build steps are scripted rather than manual

### M4. Resident Skeleton

Status:

- complete for the current development path
- resident load/install is stable enough to continue parser work

Deliverables:

- `a2han.s`
- installation path for KSW/CSW hooks
- safe initialization
- defined memory usage and zero-page usage

Exit criteria:

- resident loads cleanly
- hooks install predictably
- machine remains stable even before full Hangul conversion is enabled

### M5. Keyboard Path

Status:

- implemented for the current parser scope
- delimiter detection, buffering, and composed Hangul emission are working
- standalone fallback is now based on neutral consonant/vowel tokens rather
  than positional `choseong` / `jongseong` assumptions

Deliverables:

- delimiter detection
- input buffering
- `nbytes` parsing
- Hangul composition/transcoding
- output emission

Exit criteria:

- `Ctrl-K ... Ctrl-E` sequences produce expected Hangul
- malformed input follows the decided fail-soft behavior

### M6. Console Output Path

Status:

- partially implemented
- current runtime behavior is close enough to continue, but this path still
  needs explicit cleanup and documentation against BASIC output examples

Deliverables:

- CSW-side detection and conversion
- consistent behavior with BASIC output
- compatibility notes for output edge cases

Exit criteria:

- documented BASIC examples behave as specified
- keyboard and console paths agree on encoding results

### M7. File Utility

Status:

- basic implementation is now in place
- `HCAT` prompts for filename and source encoding, then streams `utf8`,
  `modified`, or `nbytes` content to the display path
- content rendering now bypasses stdio/conio and writes Apple II text memory
  directly
- pagination now stops at the bottom line and waits for a key instead of
  scrolling
- richer operator UX and broader file-handling polish remain open
- current blocking issue: real Apple II runs can still drop to the monitor
  after some amount of `HCAT` output, so renderer stability needs investigation

Deliverables:

- `hcat.c` or `hcat.s`
- file display path with selectable source encoding

Exit criteria:

- text files in supported encodings can be shown on screen
- operator can choose the decoding mode at runtime

### M8. Demo and Verification

Status:

- host-side tests exist
- Apple II verification has been manual and iterative
- `demo.bas` is still pending

Deliverables:

- `demo.bas`
- host-side golden tests
- manual hardware/emulator verification checklist

Exit criteria:

- demo covers representative syllables/jamo and delimiter usage
- manual test procedure exists for real Apple II or emulator runs

### M9. Hardening

Deliverables:

- documentation of memory limits and compatibility constraints
- performance and footprint review
- reinstall behavior and lifecycle notes

Exit criteria:

- known limitations are written down
- major compatibility risks are visible before release

## Suggested Work Sequence

Immediate next steps:

1. investigate the real-hardware `HCAT` crash after paged output
2. document the current resident/runtime behavior clearly
3. add `demo.bas`
4. write a short manual verification checklist around `A2HAN` and `HCAT`

After that:

1. verify DOS 3.3 runtime behavior on real hardware or emulator
2. harden reinstall/lifecycle behavior
3. write a manual verification checklist

## Non-Goals for Early Milestones

- advanced UX
- generalized text editing features
- broad compatibility claims beyond the documented firmware path
- speculative optimization before behavior is stable

## Tracking Notes

- Treat the AppleII-VGA remap as ABI.
- Avoid mixing specification work with assembly implementation guesses.
- Prefer host-side proofs before 6502 integration.
- Keep README as project overview; move normative detail into `SPEC.md`.
