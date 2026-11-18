
#!/usr/bin/env python3
"""Export the existing Rubik lookup table as GNU assembly data."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / "src/rubik/rubik_lookup.h"
OUTPUT = ROOT / "src/rubik/rubik_lookup.inc"

source = HEADER.read_text(encoding="utf-8")

offset_match = re.search(
    r"lookup_offsets\[7\]\s*=\s*\{([^}]*)\}", source
)
packed_match = re.search(
    r"lookup_packed\[36672\]\s*=\s*\{([^}]*)\}", source
)

if offset_match is None or packed_match is None:
    raise ValueError("Could not find the expected lookup arrays")

offsets = [
    int(value.strip(), 0)
    for value in offset_match.group(1).split(",")
    if value.strip()
]

packed = [
    int(value, 16)
    for value in re.findall(r"0x[0-9a-fA-F]+", packed_match.group(1))
]

assert offsets == [0, 1, 10, 64, 385, 2232, 12224]
assert len(packed) == 36672

lines = [
    "# Generated from rubik_lookup.h. Do not edit manually.",
    "    .section .rodata",
    "    .balign 4",
    "rubik_lookup_offsets:",
]

for i in range(0, len(offsets), 7):
    row = ", ".join(str(x) for x in offsets[i:i + 7])
    lines.append(f"    .word {row}")

lines += [
    "    .balign 4",
    "rubik_lookup_packed:",
]

for i in range(0, len(packed), 12):
    row = ", ".join(f"0x{x:02x}" for x in packed[i:i + 12])
    lines.append(f"    .byte {row}")

OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

print(f"Wrote {OUTPUT.relative_to(ROOT)}")
print(f"State count: {offsets[-1]}")
print(f"Packed data: {len(packed)} bytes")
