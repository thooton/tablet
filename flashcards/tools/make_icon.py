"""Draws app/icon.png (128x128): two cards, the front one marked with the
three queue shapes, black on white for the tablet.

    python tools/make_icon.py      (needs Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

S = 4  # drawn large, then scaled down for smooth edges
img = Image.new("RGBA", (128 * S, 128 * S), (255, 255, 255, 0))
d = ImageDraw.Draw(img)


def box(x0, y0, x1, y1, **kw):
    d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=8 * S, **kw)


box(26, 14, 112, 92, fill="white", outline="black", width=5 * S)
box(14, 34, 100, 114, fill="white", outline="black", width=5 * S)
y = 74
d.polygon([(30 * S, (y + 11) * S), (42 * S, (y - 11) * S), (54 * S, (y + 11) * S)], fill="black")
d.rectangle([47 * S + 12 * S, (y - 10) * S, 47 * S + 32 * S, (y + 10) * S], fill="black")
d.ellipse([84 * S - 10 * S - 2 * S, (y - 11) * S, 84 * S + 10 * S, (y + 11) * S], fill="black")
img.resize((128, 128), Image.LANCZOS).save(Path(__file__).resolve().parent.parent / "app" / "icon.png")
