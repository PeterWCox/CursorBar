#!/usr/bin/env python3
"""Make white/light background of app icon transparent (flood-fill from edges).
Uses a generous threshold to catch anti-aliased borders that cause white outlines."""
from PIL import Image
import sys

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "Assets.xcassets/AppIconImage.imageset/app_icon.png"
    img = Image.open(path).convert("RGBA")
    data = img.load()
    w, h = img.size

    # Generous threshold: near-white/light gray (anti-aliased borders often 230-250 RGB)
    def is_background(px):
        r, g, b, a = px
        return a > 180 and r > 220 and g > 220 and b > 220

    # Flood-fill from edges so we only remove outer background, not inner white (arrow, +)
    stack = []
    for x in range(w):
        stack.append((x, 0))
        stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y))
        stack.append((w - 1, y))

    seen = set()
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or x < 0 or x >= w or y < 0 or y >= h:
            continue
        px = data[x, y]
        if not is_background(px):
            continue
        seen.add((x, y))
        data[x, y] = (255, 255, 255, 0)
        stack.append((x + 1, y))
        stack.append((x - 1, y))
        stack.append((x, y + 1))
        stack.append((x, y - 1))

    img.save(path, "PNG")
    print(f"Saved {path} with transparent background")

if __name__ == "__main__":
    main()
