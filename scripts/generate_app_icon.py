#!/usr/bin/env python3
"""
Generate macOS app icons from the dock artwork source image.

The source artwork includes a light outer background intended for presentation.
For the app icon we remove that background, trim the image to its real bounds,
and scale it to fill the available rounded-rect space without the white border.
"""
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip install Pillow")
    raise

SOURCE_IMAGE_NAME = "a_digital_vector_app_icon_features_a_sleek_modern.png"
BACKGROUND_THRESHOLD = 225


def is_light_background(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, a = pixel
    if a < 8:
        return False
    return r >= BACKGROUND_THRESHOLD and g >= BACKGROUND_THRESHOLD and b >= BACKGROUND_THRESHOLD


def remove_edge_background(img: Image.Image) -> Image.Image:
    """Flood-fill light edge pixels to transparent, preserving inner white details."""
    img = img.convert("RGBA")
    pixels = img.load()
    width, height = img.size
    queue: deque[tuple[int, int]] = deque()
    seen: set[tuple[int, int]] = set()

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or x < 0 or x >= width or y < 0 or y >= height:
            continue
        seen.add((x, y))
        if not is_light_background(pixels[x, y]):
            continue

        pixels[x, y] = (255, 255, 255, 0)
        queue.append((x + 1, y))
        queue.append((x - 1, y))
        queue.append((x, y + 1))
        queue.append((x, y - 1))

    return img


def trim_to_visible_bounds(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    if bbox is None:
        raise RuntimeError("Source image became fully transparent after background removal.")
    return img.crop(bbox)


def fit_to_square(img: Image.Image, size: int) -> Image.Image:
    """Scale the processed icon to fill the target square with no extra padding."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    scale = min(size / img.width, size / img.height)
    scaled_size = (
        max(1, int(round(img.width * scale))),
        max(1, int(round(img.height * scale))),
    )
    scaled = img.resize(scaled_size, Image.Resampling.LANCZOS)
    offset = ((size - scaled.width) // 2, (size - scaled.height) // 2)
    canvas.alpha_composite(scaled, dest=offset)
    return canvas


def build_master_icon(source_path: Path) -> Image.Image:
    source = Image.open(source_path).convert("RGBA")
    without_bg = remove_edge_background(source)
    trimmed = trim_to_visible_bounds(without_bg)
    return fit_to_square(trimmed, 1024)

def main():
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    appiconset = project_root / "Assets.xcassets" / "AppIcon.appiconset"
    appiconset.mkdir(parents=True, exist_ok=True)
    source_path = project_root / SOURCE_IMAGE_NAME
    if not source_path.exists():
        raise FileNotFoundError(f"Missing source artwork: {source_path}")

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

    # Render once at 1024, then downsample for best quality.
    master = build_master_icon(source_path)
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

    # Also export a regular asset copy for places that want the same artwork directly.
    appicon_imageset = project_root / "Assets.xcassets" / "AppIconImage.imageset"
    appicon_imageset.mkdir(parents=True, exist_ok=True)
    app_icon_path = appicon_imageset / "app_icon.png"
    master.resize((512, 512), Image.Resampling.LANCZOS).save(app_icon_path, "PNG")
    print("Wrote", app_icon_path, "(AppIconImage for title bar)")

if __name__ == "__main__":
    main()
