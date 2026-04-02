#!/bin/sh

set -eu

APPLE2TS_URL="${APPLE2TS_URL:-http://127.0.0.1:6502}"
BOOT_DISK="${1:-dos-3.3.dsk}"
TEST_DISK="${2:-build/a2han.dsk}"

if [ ! -f "$BOOT_DISK" ]; then
    echo "missing boot disk: $BOOT_DISK" >&2
    exit 1
fi

if [ ! -f "$TEST_DISK" ]; then
    echo "missing test disk: $TEST_DISK" >&2
    exit 1
fi

tmpdir="$(mktemp -d /tmp/apple2ts-a2han.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

check_ok() {
    body_file="$1"
    if ! grep -q '"ok":true' "$body_file"; then
        echo "apple2ts request failed:" >&2
        cat "$body_file" >&2
        exit 1
    fi
}

mount_disk() {
    drive_id="$1"
    disk_path="$2"
    json_path="$tmpdir/$drive_id.json"
    base64_path="$tmpdir/$drive_id.b64"

    base64 -w0 "$disk_path" > "$base64_path"
    printf '{"sourceType":"base64","filename":"%s","dataBase64":"' "$(basename "$disk_path")" > "$json_path"
    cat "$base64_path" >> "$json_path"
    printf '"}\n' >> "$json_path"

    curl -s -X POST "$APPLE2TS_URL/api/drives/$drive_id/mount" \
        -H 'Content-Type: application/json' \
        --data-binary @- < "$json_path" > "$tmpdir/$drive_id.mount.out"
    check_ok "$tmpdir/$drive_id.mount.out"
}

post_json() {
    endpoint="$1"
    payload="$2"
    output_path="$3"

    curl -s -X POST "$APPLE2TS_URL$endpoint" \
        -H 'Content-Type: application/json' \
        -d "$payload" > "$output_path"
    check_ok "$output_path"
}

get_json() {
    endpoint="$1"
    output_path="$2"

    curl -s "$APPLE2TS_URL$endpoint" > "$output_path"
    check_ok "$output_path"
}

mount_disk fd1 "$BOOT_DISK"
mount_disk fd2 "$TEST_DISK"

post_json /api/machine/boot '{}' "$tmpdir/boot.out"
sleep 2

post_json /api/input/keys '{"type":"text","text":"CATALOG,D2\r"}' "$tmpdir/catalog.out"
sleep 2

post_json /api/input/keys '{"type":"text","text":"BRUN A2HAN\r"}' "$tmpdir/brun.out"
sleep 2

get_json /api/machine "$tmpdir/machine.out"

python3 - "$tmpdir/machine.out" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)

data = payload["data"]
print(f"runMode={data['runMode']}")
for drive in data["drives"]:
    if drive["mounted"]:
        print(f"{drive['driveId']}={drive['filename']}")

text_page = data.get("textPage", "")
rows = [text_page[i : i + 40].rstrip() for i in range(0, min(len(text_page), 24 * 40), 40)]
non_empty = [row for row in rows if row.strip()]
for index, row in enumerate(non_empty[:4], start=1):
    print(f"line{index}={row}")
PY
