
#!/usr/bin/env python3
"""Generate a depth-5 bitmap from the Rubik lookup table."""

import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
header = root / "src/rubik/rubik_lookup.h"
output = root / "src/rubik/rubik_depth5_bitmap.inc"

text = header.read_text(encoding="utf-8")

offset_match = re.search(
    r"lookup_offsets\[\d+\]\s*=\s*\{([^}]*)\}", text
)
packed_match = re.search(
    r"lookup_packed\[\d+\]\s*=\s*\{([^}]*)\}", text
)

if offset_match is None or packed_match is None:
    raise ValueError("Lookup arrays not found")

offsets = [
    int(x.strip())
    for x in offset_match.group(1).split(",")
    if x.strip()
]

packed = bytes(
    int(x, 16)
    for x in re.findall(r"0x[0-9a-fA-F]+", packed_match.group(1))
)

assert offsets == [0, 1, 10, 64, 385, 2232, 12224]
assert len(packed) == offsets[-1] * 3

bitmap = bytearray(8192)

for i in range(offsets[5], offsets[6]):
    state_id = int.from_bytes(
        packed[i * 3:i * 3 + 3], "little"
    )

    index = state_id & 0xFFFF

    byte_index = index >> 3
    bit_index = index & 7

    bitmap[byte_index] |= 1 << bit_index

lines = [
    "# Generated depth-5 bitmap.",
    "    .section .rodata",
    "    .balign 4",
    "rubik_depth5_bitmap:",
]

for i in range(0, len(bitmap), 16):
    values = ", ".join(
        f"0x{x:02x}" for x in bitmap[i:i + 16]
    )
    lines.append(f"    .byte {values}")

output.write_text("\n".join(lines) + "\n", encoding="utf-8")

print(f"Generated: {output}")
print(f"Bitmap size: {len(bitmap)} bytes")
print(f"Depth-5 states: {offsets[6] - offsets[5]}")
print(f"Marked bit positions: {sum(x.bit_count() for x in bitmap)}")
