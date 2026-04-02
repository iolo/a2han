#!/bin/sh

set -eu

APPLE2TS_URL="${APPLE2TS_URL:-http://127.0.0.1:6502}"
PAYLOAD="${1:-RK}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/run_apple2ts_a2han.sh" > /tmp/apple2ts-a2han-run.out

json_escape_text() {
    python3 - "$1" <<'PY'
import json
import sys

payload = sys.argv[1]
print(json.dumps(payload))
PY
}

PRINT_TEXT="$(printf 'PRINT "\013%s\001"\r' "$PAYLOAD")"
PRINT_JSON="$(json_escape_text "$PRINT_TEXT")"

curl -s -X POST "$APPLE2TS_URL/api/input/keys" \
    -H 'Content-Type: application/json' \
    -d "{\"type\":\"text\",\"text\":$PRINT_JSON}" > /tmp/apple2ts-print-span-input.out

sleep 2

curl -s -X POST "$APPLE2TS_URL/api/machine/pause" > /tmp/apple2ts-print-span-pause.out
sleep 1
curl -s "$APPLE2TS_URL/api/machine" > /tmp/apple2ts-print-span-machine.json
curl -s "$APPLE2TS_URL/api/debug/memory?start=1024&length=1024&format=bytes" > /tmp/apple2ts-print-span-memory.json

python3 - <<'PY'
import json
from pathlib import Path

machine = json.loads(Path("/tmp/apple2ts-print-span-machine.json").read_text(encoding="utf-8"))
memory = json.loads(Path("/tmp/apple2ts-print-span-memory.json").read_text(encoding="utf-8"))

if not machine.get("ok"):
    raise SystemExit(f"machine request failed: {machine}")
if not memory.get("ok"):
    raise SystemExit(f"memory request failed: {memory}")

text_page = machine["data"]["textPage"]
mem = memory["data"]["data"]

row_offsets = [
    0x000, 0x080, 0x100, 0x180,
    0x028, 0x0A8, 0x128, 0x1A8,
    0x050, 0x0D0, 0x150, 0x1D0,
    0x078, 0x0F8, 0x178, 0x1F8,
    0x0A0, 0x120, 0x1A0, 0x220,
    0x0C8, 0x148, 0x1C8, 0x248,
]

print(f"runMode={machine['data']['runMode']}")
for drive in machine["data"]["drives"]:
    if drive["mounted"]:
        print(f"{drive['driveId']}={drive['filename']}")

rows = [text_page[i:i + 40] for i in range(0, min(len(text_page), 24 * 40), 40)]
for index, row in enumerate(rows, start=1):
    if row.strip():
        print(f"text_line_{index}={row.rstrip()}")

for index, offset in enumerate(row_offsets, start=1):
    row = mem[offset:offset + 40]
    if not row:
        continue
    if any(value != 0xA0 for value in row):
        hex_row = " ".join(f"{value:02X}" for value in row)
        print(f"mem_line_{index}={hex_row}")
PY
