#!/usr/bin/env python3
import binascii
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
raw = bytearray()

for y in range(SIZE):
    raw.append(0)
    for x in range(SIZE):
        t = (x + y) / (2 * (SIZE - 1))
        r = int(17 + 5 * t)
        g = int(86 + 108 * t)
        b = int(210 + 35 * t)

        # A clean cockpit dial with five account marks.
        dx, dy = x - 512, y - 500
        radius = math.hypot(dx, dy)
        if 250 < radius < 330 and y < 700:
            r, g, b = 240, 249, 255
        for angle in (-120, -60, 0, 60, 120):
            a = math.radians(angle - 90)
            cx = 512 + math.cos(a) * 225
            cy = 500 + math.sin(a) * 225
            if (x - cx) ** 2 + (y - cy) ** 2 < 25 ** 2:
                r, g, b = 255, 255, 255
        if abs(dx) < 20 and 485 < y < 745:
            r, g, b = 255, 255, 255
        if (x - 512) ** 2 + (y - 755) ** 2 < 58 ** 2:
            r, g, b = 255, 255, 255
        raw.extend((r, g, b, 255))

def chunk(kind: bytes, data: bytes) -> bytes:
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
png += chunk(b"IEND", b"")

target = Path(__file__).parents[1] / "CodexCockpit/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
target.write_bytes(png)
print(target)
