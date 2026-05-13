#!/usr/bin/env python3
"""Generate the 540x380 DMG background image.

Palette is pulled from the JPG Master app icon: deep navy background
with the brand cyan used for the arrow glow.

Output: <repo>/swift/Scripts/dmg-background.png
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

W, H = 540, 380

NAVY_CENTER = (31, 36, 52)
NAVY_EDGE = (12, 14, 22)
ARROW_CORE = (45, 215, 235)
ARROW_GLOW = (26, 169, 194)


def radial_gradient(size, center_rgb, edge_rgb):
    w, h = size
    img = Image.new("RGB", size, edge_rgb)
    cx, cy = w / 2, h / 2
    max_r = (cx ** 2 + cy ** 2) ** 0.5
    px = img.load()
    for y in range(h):
        for x in range(w):
            r = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            t = min(r / max_r, 1.0)
            t = t ** 1.4
            px[x, y] = tuple(
                int(center_rgb[i] * (1 - t) + edge_rgb[i] * t) for i in range(3)
            )
    return img


def draw_arrow(canvas, color, glow_color):
    glow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)

    cy = H // 2
    shaft_left = 215
    shaft_right = 325
    shaft_thickness = 12
    head_tip_x = 360
    head_half_h = 32
    head_back_x = shaft_right

    arrow_poly = [
        (shaft_left, cy - shaft_thickness // 2),
        (shaft_right, cy - shaft_thickness // 2),
        (shaft_right, cy - head_half_h),
        (head_tip_x, cy),
        (shaft_right, cy + head_half_h),
        (shaft_right, cy + shaft_thickness // 2),
        (shaft_left, cy + shaft_thickness // 2),
    ]

    gd.polygon(arrow_poly, fill=glow_color + (140,))
    blurred = glow_layer.filter(ImageFilter.GaussianBlur(radius=14))

    core_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    cd = ImageDraw.Draw(core_layer)
    cd.polygon(arrow_poly, fill=color + (255,))
    core_blur = core_layer.filter(ImageFilter.GaussianBlur(radius=0.7))

    canvas = canvas.convert("RGBA")
    canvas = Image.alpha_composite(canvas, blurred)
    canvas = Image.alpha_composite(canvas, core_blur)
    return canvas.convert("RGB")


def main(out_path: Path) -> None:
    bg = radial_gradient((W, H), NAVY_CENTER, NAVY_EDGE)
    bg = draw_arrow(bg, ARROW_CORE, ARROW_GLOW)
    bg.save(out_path, "PNG", optimize=True)
    print(f"Wrote {out_path} ({W}x{H})")


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("dmg-background.png")
    main(out)
