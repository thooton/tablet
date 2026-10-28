"""Draws the app's bitmap assets (dotted-underline tile, icons); the launcher
icon comes from the repository's tools/make_icons.py.

Run with the emulator's Python (it needs PySide6):
    python tools/generate_assets.py
"""
import sys
from pathlib import Path

from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QBrush, QColor, QFont, QFontDatabase, QGuiApplication, QImage, QPainter, QPainterPath, QPen

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "app" / "ui"


INK = "#000000"


def dots_tile(path: Path) -> None:
    # The dotted underline: a black dot 4 px across in a 10 x 8 tile, repeated
    # along each phrase. Solid black, no soft edge: greys wash out on e-ink.
    img = QImage(10, 8, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    for y in range(8):
        for x in range(10):
            # Inked where most of the pixel is inside the dot.
            cover = 0
            for sy in range(4):
                for sx in range(4):
                    d = ((x + (sx + 0.5) / 4 - 5) ** 2 + (y + (sy + 0.5) / 4 - 4) ** 2) ** 0.5
                    cover += d <= 2.4
            img.setPixelColor(x, y, QColor(INK) if cover >= 8 else QColor(Qt.transparent))
    img.save(str(path))


def stroke_icon(path: Path, w: int, h: int, lines, width=3.2, dots=(), color=INK) -> None:
    """Icons from the mockup's SVGs: square caps, mitred joins, ink colour."""
    img = QImage(w, h, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    pen = QPen(QColor(color), width)
    pen.setCapStyle(Qt.SquareCap)
    pen.setJoinStyle(Qt.MiterJoin)
    p.setPen(pen)
    for pts in lines:
        path_ = QPainterPath(QPointF(*pts[0]))
        for pt in pts[1:]:
            path_.lineTo(QPointF(*pt))
        p.drawPath(path_)
    p.setBrush(QBrush(QColor(color)))
    for cx, cy, r in dots:
        p.drawEllipse(QPointF(cx, cy), r, r)
    p.end()
    img.save(str(path))


def icons(folder: Path) -> None:
    # Each icon also in white ("-white"), drawn on black while it is pressed.
    for suffix, color in (("", INK), ("-white", "#ffffff")):
        stroke_icon(folder / f"back{suffix}.png", 56, 56, [[(44, 28), (12, 28)], [(24, 15), (11, 28), (24, 41)]], color=color)
        stroke_icon(folder / f"menu{suffix}.png", 56, 56, [], dots=[(28, 13, 3.2), (28, 28, 3.2), (28, 43, 3.2)], color=color)
        stroke_icon(folder / f"close{suffix}.png", 56, 56, [[(16, 16), (40, 40)], [(40, 16), (16, 40)]], color=color)
        stroke_icon(folder / f"grab{suffix}.png", 96, 22, [[(4, 4), (48, 18), (92, 4)]], width=4, color=color)


def main() -> int:
    app = QGuiApplication(sys.argv[:1] + ["-platform", "offscreen"])
    (UI / "images").mkdir(parents=True, exist_ok=True)
    dots_tile(UI / "images" / "dots.png")
    icons(UI / "images")
    print("assets written")
    del app
    return 0


if __name__ == "__main__":
    sys.exit(main())
