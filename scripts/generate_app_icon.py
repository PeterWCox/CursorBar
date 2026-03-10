#!/usr/bin/env python3
"""
Generate Cursor Bar app icon: Cursor-style mark + plus, teal accent.
Outputs PNGs for macOS AppIcon.appiconset (all required sizes).
"""
from pathlib import Path
import math

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Install Pillow: pip install Pillow")
    raise

# CursorTheme-aligned colors (RGB 0–1)
CURSOR_TEAL = (0, 212/255, 181/255)      # cursorPlusTeal
BRAND_BLUE = (0.40, 0.61, 1.00)
CHROME = (0.055, 0.059, 0.075)
SURFACE = (0.118, 0.122, 0.145)

def rgba(rgb, a=1.0):
    return tuple(int(round(c * 255)) for c in rgb) + (int(round(a * 255)),)

def draw_icon(size: int) -> Image.Image:
    """Draw icon at given size (square)."""
    pad = max(1, size // 32)
    cell = size - 2 * pad
    cx, cy = size / 2, size / 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded rect background (dark with teal tint)
    r = cell * 0.22
    rect = [pad, pad, size - pad, size - pad]
    draw.rounded_rectangle(rect, radius=int(r), fill=rgba(CHROME))

    # Teal gradient border (simulate with overlay rounded rect stroke)
    stroke_w = max(1, size // 64)
    inner = [pad + stroke_w, pad + stroke_w, size - pad - stroke_w, size - pad - stroke_w]
    draw.rounded_rectangle(rect, outline=rgba(CURSOR_TEAL, 0.9), width=stroke_w)
    draw.rounded_rectangle(inner, outline=rgba(BRAND_BLUE, 0.3), width=max(1, stroke_w // 2))

    # Scale for drawing the Cursor mark (relative to cell)
    def px(x): return pad + x * cell
    def py(y): return pad + y * cell

    # Cursor mark: ring
    ring_cx, ring_cy = 0.5, 0.52
    ring_r = 0.24
    ring_w = max(1, size // 56)
    ring_bbox = [px(ring_cx - ring_r), py(ring_cy - ring_r), px(ring_cx + ring_r), py(ring_cy + ring_r)]
    draw.ellipse(ring_bbox, outline=rgba((1, 1, 1), 0.92), width=ring_w)

    # Center dot
    dot_r = 0.055
    dot_bbox = [px(ring_cx - dot_r), py(ring_cy - dot_r), px(ring_cx + dot_r), py(ring_cy + dot_r)]
    draw.ellipse(dot_bbox, fill=rgba((1, 1, 1), 0.92))

    # Orbit curve (small arc)
    ox1, oy1 = 0.22, 0.48
    ox2, oy2 = 0.52, 0.78
    steps = max(8, size // 32)
    for i in range(steps):
        t = i / steps
        t2 = (i + 1) / steps
        # Quadratic bezier: P0=(ox1,oy1), P2=(ox2,oy2), control toward top-left
        cpx, cpy = 0.12, 0.22
        x1 = (1-t)**2 * ox1 + 2*(1-t)*t * cpx + t**2 * ox2
        y1 = (1-t)**2 * oy1 + 2*(1-t)*t * cpy + t**2 * oy2
        x2 = (1-t2)**2 * ox1 + 2*(1-t2)*t2 * cpx + t2**2 * ox2
        y2 = (1-t2)**2 * oy1 + 2*(1-t2)*t2 * cpy + t2**2 * oy2
        draw.line([px(x1), py(y1), px(x2), py(y2)], fill=rgba((1, 1, 1), 0.75), width=max(1, size // 80), joint="curve")

    # Spark (X) top-right of ring
    spark_cx, spark_cy = 0.72, 0.32
    d = 0.06
    lw = max(1, size // 72)
    draw.line([px(spark_cx - d), py(spark_cy - d), px(spark_cx + d), py(spark_cy + d)], fill=rgba((1, 1, 1), 0.9), width=lw)
    draw.line([px(spark_cx - d), py(spark_cy + d), px(spark_cx + d), py(spark_cy - d)], fill=rgba((1, 1, 1), 0.9), width=lw)

    # Bold "+" in teal (bottom-right quadrant, so it reads "Cursor +")
    plus_cx, plus_cy = 0.78, 0.78
    plus_hw = 0.12   # half width of bar
    plus_thick = max(2, size // 32)
    # Horizontal bar
    draw.rounded_rectangle([
        px(plus_cx - plus_hw), py(plus_cy) - plus_thick // 2,
        px(plus_cx + plus_hw), py(plus_cy) + plus_thick // 2
    ], radius=plus_thick // 2, fill=rgba(CURSOR_TEAL))
    # Vertical bar
    draw.rounded_rectangle([
        px(plus_cx) - plus_thick // 2, py(plus_cy - plus_hw),
        px(plus_cx) + plus_thick // 2, py(plus_cy + plus_hw)
    ], radius=plus_thick // 2, fill=rgba(CURSOR_TEAL))

    return img

def main():
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    appiconset = project_root / "CursorMenuBar" / "Assets.xcassets" / "AppIcon.appiconset"
    appiconset.mkdir(parents=True, exist_ok=True)

    # macOS AppIcon sizes: (size, scale) -> pixel dimension
    slots = [
        ("16x16", 1, 16),
        ("16x16", 2, 32),
        ("32x32", 1, 32),
        ("32x32", 2, 64),
        ("128x128", 1, 128),
        ("128x128", 2, 256),
        ("256x256", 1, 256),
        ("256x256", 2, 512),
    ]

    # Render at 1024 then downsample for quality
    master = draw_icon(1024)
    filenames = []

    for size_name, scale, pixels in slots:
        if scale == 1:
            filename = f"icon_{size_name}.png"
        else:
            filename = f"icon_{size_name}@2x.png"
        out_path = appiconset / filename
        if pixels >= 1024:
            icon = master
        else:
            icon = master.resize((pixels, pixels), Image.Resampling.LANCZOS)
        icon.save(out_path, "PNG")
        filenames.append((size_name, scale, filename))
        print("Wrote", out_path)

    # Update Contents.json
    contents = {
        "images": [
            {
                "filename": fn,
                "idiom": "mac",
                "scale": f"{s}x",
                "size": size_name
            }
            for size_name, s, fn in filenames
        ],
        "info": {"author": "xcode", "version": 1}
    }

    import json
    json_path = appiconset / "Contents.json"
    with open(json_path, "w") as f:
        json.dump(contents, f, indent=2)
    print("Updated", json_path)

if __name__ == "__main__":
    main()
