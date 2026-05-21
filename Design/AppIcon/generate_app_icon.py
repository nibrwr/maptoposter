from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
DESIGN_DIR = ROOT / "Design" / "AppIcon"
LAYER_DIR = DESIGN_DIR / "Layers"
APPICON_DIR = ROOT / "Sources" / "MapToPosterMac" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def gradient_background() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    top = (235, 246, 254)
    bottom = (92, 166, 221)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        for x in range(SIZE):
            side = x / (SIZE - 1)
            blue_lift = int(18 * side * (1 - t))
            color = tuple(int(top[i] * (1 - t) + bottom[i] * t) + (blue_lift if i == 2 else 0) for i in range(3))
            pixels[x, y] = (*color, 255)

    draw = ImageDraw.Draw(image, "RGBA")
    draw.rounded_rectangle((104, 108, 920, 920), radius=184, outline=(246, 252, 255, 188), width=8)
    draw.ellipse((420, 92, 968, 520), fill=(255, 255, 255, 38))
    draw.ellipse((-180, 524, 332, 1080), fill=(41, 140, 213, 52))
    return image


def map_tiles() -> Image.Image:
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")

    # Apple Maps homage: soft map districts, water, parks, and bright arterial roads.
    draw.polygon([(0, 0), (430, 0), (320, 350), (0, 430)], fill=(230, 246, 253, 160))
    draw.polygon([(430, 0), (1024, 0), (1024, 308), (608, 414), (320, 350)], fill=(204, 235, 250, 165))
    draw.polygon([(0, 430), (320, 350), (492, 680), (0, 868)], fill=(236, 247, 232, 172))
    draw.polygon([(608, 414), (1024, 308), (1024, 1024), (638, 1024), (492, 680)], fill=(229, 242, 251, 180))
    draw.polygon([(0, 868), (492, 680), (638, 1024), (0, 1024)], fill=(215, 239, 223, 168))

    for x in (226, 426, 654, 808):
        draw.line([(x, 128), (x - 84, 898)], fill=(255, 255, 255, 128), width=7)
    for y in (214, 338, 472, 614, 766):
        draw.line([(104, y), (900, y - 58)], fill=(255, 255, 255, 118), width=7)

    draw.line([(34, 702), (334, 606), (564, 642), (1012, 510)], fill=(255, 204, 70, 220), width=78, joint="curve")
    draw.line([(34, 702), (334, 606), (564, 642), (1012, 510)], fill=(255, 238, 139, 245), width=47, joint="curve")

    draw.line([(118, 180), (326, 300), (520, 286), (722, 380), (982, 350)], fill=(87, 164, 223, 225), width=60, joint="curve")
    draw.line([(118, 180), (326, 300), (520, 286), (722, 380), (982, 350)], fill=(190, 231, 255, 236), width=31, joint="curve")

    draw.line([(696, 0), (622, 226), (672, 474), (602, 790), (648, 1024)], fill=(252, 252, 255, 154), width=24)
    draw.line([(232, 0), (206, 214), (246, 436), (218, 744), (268, 1024)], fill=(252, 252, 255, 142), width=18)
    return layer


def poster_sheet() -> Image.Image:
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow, "RGBA")
    shadow_draw.rounded_rectangle((492, 326, 810, 720), radius=48, fill=(34, 85, 122, 78))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    layer.alpha_composite(shadow)

    draw = ImageDraw.Draw(layer, "RGBA")
    draw.rounded_rectangle((464, 300, 790, 696), radius=48, fill=(255, 255, 255, 230))
    draw.polygon([(696, 300), (790, 394), (790, 300)], fill=(223, 242, 253, 230))
    draw.rounded_rectangle((502, 446, 718, 464), radius=9, fill=(105, 157, 197, 210))
    draw.rounded_rectangle((502, 526, 718, 544), radius=9, fill=(105, 157, 197, 200))
    draw.rounded_rectangle((502, 606, 682, 624), radius=9, fill=(105, 157, 197, 190))
    return layer


def marker_and_route() -> Image.Image:
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow, "RGBA")
    shadow_draw.ellipse((214, 650, 444, 880), fill=(31, 78, 118, 82))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    layer.alpha_composite(shadow)

    draw = ImageDraw.Draw(layer, "RGBA")
    draw.line([(340, 780), (440, 774), (520, 735), (648, 738)], fill=(255, 255, 255, 245), width=32)
    draw.ellipse((224, 604, 428, 808), fill=(255, 255, 255, 255))
    draw.ellipse((272, 652, 380, 760), fill=(43, 142, 218, 255))
    draw.ellipse((316, 696, 350, 730), fill=(250, 253, 255, 255))
    draw.pieslice((272, 652, 380, 760), start=42, end=132, fill=(94, 184, 238, 255))

    # A small red pin nods to Maps while staying secondary to this app's poster mark.
    draw.ellipse((690, 228, 804, 342), fill=(255, 91, 88, 250))
    draw.polygon([(747, 392), (706, 318), (788, 318)], fill=(255, 91, 88, 250))
    draw.ellipse((728, 266, 766, 304), fill=(255, 255, 255, 248))
    return layer


def compose() -> Image.Image:
    mask = rounded_mask(SIZE, 210)
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for layer in (gradient_background(), map_tiles(), poster_sheet(), marker_and_route()):
        icon.alpha_composite(layer)
    icon.putalpha(mask)
    return icon


def save_assets(icon: Image.Image) -> None:
    LAYER_DIR.mkdir(parents=True, exist_ok=True)
    APPICON_DIR.mkdir(parents=True, exist_ok=True)

    layers = [
        ("01-background.png", gradient_background()),
        ("02-map-tiles.png", map_tiles()),
        ("03-poster-sheet.png", poster_sheet()),
        ("04-marker-route.png", marker_and_route()),
    ]
    current_layer_names = {name for name, _ in layers}
    for old_layer in LAYER_DIR.glob("*.png"):
        if old_layer.name not in current_layer_names:
            old_layer.unlink()

    for name, layer in layers:
        layer.save(LAYER_DIR / name)

    icon.save(DESIGN_DIR / "AppIcon-1024.png")
    icon.save(APPICON_DIR / "AppIcon-1024.png")
    for size in (16, 32, 64, 128, 256, 512):
        icon.resize((size, size), Image.Resampling.LANCZOS).save(APPICON_DIR / f"AppIcon-{size}.png")

    images = [
        {"idiom": "mac", "size": "16x16", "scale": "1x", "filename": "AppIcon-16.png"},
        {"idiom": "mac", "size": "16x16", "scale": "2x", "filename": "AppIcon-32.png"},
        {"idiom": "mac", "size": "32x32", "scale": "1x", "filename": "AppIcon-32.png"},
        {"idiom": "mac", "size": "32x32", "scale": "2x", "filename": "AppIcon-64.png"},
        {"idiom": "mac", "size": "128x128", "scale": "1x", "filename": "AppIcon-128.png"},
        {"idiom": "mac", "size": "128x128", "scale": "2x", "filename": "AppIcon-256.png"},
        {"idiom": "mac", "size": "256x256", "scale": "1x", "filename": "AppIcon-256.png"},
        {"idiom": "mac", "size": "256x256", "scale": "2x", "filename": "AppIcon-512.png"},
        {"idiom": "mac", "size": "512x512", "scale": "1x", "filename": "AppIcon-512.png"},
        {"idiom": "mac", "size": "512x512", "scale": "2x", "filename": "AppIcon-1024.png"},
    ]
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (APPICON_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    save_assets(compose())
