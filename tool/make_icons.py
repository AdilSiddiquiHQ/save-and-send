#!/usr/bin/env python3
"""Generate the Save & Send launcher icons.

Run from the project root:  python3 tool/make_icons.py
Requires Pillow.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"

GREEN_TOP = (37, 211, 102)      # WhatsApp-ish green
GREEN_BOTTOM = (13, 122, 74)    # deep green
CREAM = (247, 245, 239)
WHITE = (255, 255, 255)

S = 4096  # supersampled master


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def glyph(draw, size, scale=1.0):
    """Draw the white download glyph centred in a size x size canvas."""
    c = size / 2
    u = size / 1024 * scale

    # Soft translucent disc behind the glyph.
    disc_r = 360 * u
    draw.ellipse(
        [c - disc_r, c - disc_r, c + disc_r, c + disc_r],
        fill=(255, 255, 255, 28),
    )

    # Arrow shaft.
    shaft_w = 118 * u
    draw.rounded_rectangle(
        [c - shaft_w / 2, c - 300 * u, c + shaft_w / 2, c + 35 * u],
        radius=shaft_w / 2,
        fill=WHITE,
    )

    # Arrow head.
    draw.polygon(
        [
            (c - 205 * u, c - 20 * u),
            (c + 205 * u, c - 20 * u),
            (c, c + 205 * u),
        ],
        fill=WHITE,
    )

    # Download tray (a rounded U).
    tray_w = 440 * u
    tray_top = c + 245 * u
    tray_bottom = c + 355 * u
    line_w = int(62 * u)
    draw.line(
        [(c - tray_w / 2, tray_top), (c - tray_w / 2, tray_bottom)],
        fill=WHITE,
        width=line_w,
    )
    draw.line(
        [(c + tray_w / 2, tray_top), (c + tray_w / 2, tray_bottom)],
        fill=WHITE,
        width=line_w,
    )
    draw.line(
        [(c - tray_w / 2, tray_bottom), (c + tray_w / 2, tray_bottom)],
        fill=WHITE,
        width=line_w,
    )
    # Round the three tray ends.
    r = line_w / 2
    for x, y in [
        (c - tray_w / 2, tray_top),
        (c + tray_w / 2, tray_top),
        (c - tray_w / 2, tray_bottom),
        (c + tray_w / 2, tray_bottom),
    ]:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)


def legacy_icon(size, round_icon=False, safe=1.0):
    big = S
    bg = gradient(big, GREEN_TOP, GREEN_BOTTOM).convert("RGBA")
    mask = Image.new("L", (big, big), 0)
    md = ImageDraw.Draw(mask)
    if round_icon:
        md.ellipse([0, 0, big - 1, big - 1], fill=255)
    else:
        md.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.22), fill=255)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(out)
    glyph(d, big, scale=safe)
    return out.resize((size, size), Image.LANCZOS)


def foreground(size=1024):
    big = S
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    glyph(d, big, scale=0.62)
    return out.resize((size, size), Image.LANCZOS)


def main():
    for name, size in [
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ]:
        d = RES / name
        d.mkdir(parents=True, exist_ok=True)
        legacy_icon(size).save(d / "ic_launcher.png")
        legacy_icon(size, round_icon=True, safe=0.92).save(d / "ic_launcher_round.png")

    drawable = RES / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    foreground(1024).save(drawable / "ic_launcher_foreground.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
    (anydpi / "ic_launcher.xml").write_text(xml)
    (anydpi / "ic_launcher_round.xml").write_text(xml)

    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0D7A4A</color>
</resources>
"""
    )

    # A clean cream launch background (visible for a fraction of a second).
    for path in [RES / "drawable/launch_background.xml", RES / "drawable-v21/launch_background.xml"]:
        if path.exists():
            path.write_text(
                """<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/launch_background" />
</layer-list>
"""
            )

    (values / "colors.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="launch_background">#F7F5EF</color>
</resources>
"""
    )

    print("Icons written to", RES)


if __name__ == "__main__":
    main()
