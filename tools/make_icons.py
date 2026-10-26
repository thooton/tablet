"""Draws app/icon.png (128x128) for Biblioteca, Flashcards and Updater in
LSAT Falcon's style: one bold solid black glyph on white, no frame.

    python3 tools/make_icons.py      (needs Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
S = 8  # drawn large, then scaled down for smooth edges


def canvas():
    img = Image.new("RGB", (128 * S, 128 * S), "white")
    return img, ImageDraw.Draw(img)


def p(*pts):
    return [(x * S, y * S) for x, y in pts]


def save(img, app):
    img.resize((128, 128), Image.LANCZOS).save(ROOT / app / "app" / "icon.png")


def book():
    img, d = canvas()
    # Two solid pages, their outer edges lifting, a white gutter between.
    for side in (-1, 1):
        x = lambda v: 64 + side * v
        d.polygon(p((x(4), 34), (x(22), 26), (x(40), 24), (x(56), 28),
                    (x(56), 98), (x(40), 94), (x(22), 96), (x(4), 104)),
                  fill="black")
        # Lines of text, in white.
        for y in (44, 56, 68, 80):
            d.line(p((x(14), y + 2), (x(46), y - 2)), fill="white", width=5 * S)
            r = 2.5 * S
            for cx, cy in ((x(14), y + 2), (x(46), y - 2)):
                d.ellipse([cx * S - r, cy * S - r, cx * S + r, cy * S + r], fill="white")
    # Cover showing below the pages.
    d.polygon(p((8, 104), (64, 112), (120, 104), (120, 110), (64, 118), (8, 110)), fill="black")
    save(img, "spanish-stories")


def cards():
    img, d = canvas()
    r = 9 * S
    d.rounded_rectangle(p((36, 14), (116, 86)), radius=r, fill="black")
    # The front card, cut out from the back one by a white gap.
    d.rounded_rectangle(p((6, 36), (98, 120)), radius=r + 6 * S, fill="white")
    d.rounded_rectangle(p((12, 42), (92, 114)), radius=r, fill="black")
    # The three queue shapes, in white.
    y = 78
    d.polygon(p((22, y + 10), (32, y - 10), (42, y + 10)), fill="white")
    d.rectangle(p((47, y - 9), (64, y + 9)), fill="white")
    d.ellipse(p((69, y - 10), (89, y + 10)), fill="white")
    save(img, "flashcards")


def download():
    img, d = canvas()
    # Arrow.
    d.rectangle(p((53, 12), (75, 58)), fill="black")
    d.polygon(p((30, 54), (98, 54), (64, 90)), fill="black")
    # Tray.
    d.polygon(p((12, 74), (32, 74), (32, 98), (96, 98), (96, 74), (116, 74),
                (116, 118), (12, 118)), fill="black")
    save(img, "updater")


book()
cards()
download()
