# AGENTS.md

This file provides guidance to AI Coding Agents working with code in this repository.

## General Principles

- Explict than Implicit
- Readability over Performance
- Composition over Inheritance
- Avoid redudant Comment. ex. `/* Create a page */ function createPage() {}`

## Apple2ts Workflow

- For repeatable emulator testing, prefer `tools/run_apple2ts_a2han.sh`.
- Default workflow:
  `make dsk`
  `tools/run_apple2ts_a2han.sh`
- The helper mounts `dos-3.3.dsk` on `fd1`, mounts `build/a2han.dsk` on `fd2`,
  boots, sends `CATALOG,D2`, then sends `BRUN A2HAN`.
- For focused output repros, prefer `tools/repro_apple2ts_print_span.sh`.
- For control experiments without the resident hook, use `CSWTEST` from the DOS
  disk image.
- When inspecting `apple2ts`, prefer `GET /api/machine` and its `textPage`
  field for quick screen checks before using debugger memory reads.
- `apple2ts` may report mounted floppy images back as `.woz` even when the
  source image mounted was `.dsk`. Treat that as an emulator reporting quirk
  unless behavior proves otherwise.
- Current working theory:
  line-edit/input echo, stored Applesoft program text, and ordinary program
  output are different paths and must be tested separately.
