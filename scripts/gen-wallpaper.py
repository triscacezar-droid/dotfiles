#!/usr/bin/env python3
"""Generate a subtle gruvbox-dark gradient wallpaper that complements the
conky widget's semi-opaque #1d2021 panel. 3840x2160 so it scales cleanly
to 2560x1440 and 1920x1080 displays."""

from PIL import Image
from pathlib import Path
import random
import sys

W, H = 3840, 2160
TOP    = (0x32, 0x30, 0x2f)  # gruvbox bg0_s
BOTTOM = (0x1d, 0x20, 0x21)  # gruvbox bg0_h (matches conky panel)

out = Path(sys.argv[1] if len(sys.argv) > 1
           else Path.home() / "Pictures/Wallpapers/gruvbox_dark_minimal.png")
out.parent.mkdir(parents=True, exist_ok=True)

img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    t = y / (H - 1)
    r = int(TOP[0] + (BOTTOM[0] - TOP[0]) * t)
    g = int(TOP[1] + (BOTTOM[1] - TOP[1]) * t)
    b = int(TOP[2] + (BOTTOM[2] - TOP[2]) * t)
    for x in range(W):
        px[x, y] = (r, g, b)

# Subtle noise so the gradient doesn't band on 8-bit panels.
rng = random.Random(42)
for y in range(0, H, 2):
    for x in range(0, W, 2):
        r, g, b = px[x, y]
        n = rng.randint(-2, 2)
        px[x, y] = (max(0, min(255, r + n)),
                    max(0, min(255, g + n)),
                    max(0, min(255, b + n)))

img.save(out, optimize=True)
print(out)
