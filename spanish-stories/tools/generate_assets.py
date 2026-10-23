"""Draws the app's bitmap assets (dotted-underline tile, icons, launcher icon).

Run with the emulator's Python (it needs PySide6):
    python tools/generate_assets.py
"""
import sys
from pathlib import Path

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QBrush, QColor, QFont, QFontDatabase, QGuiApplication, QImage, QPainter, QPainterPath, QPen

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "app" / "ui"


INK = "#111111"


def dots_tile(path: Path) -> None:
    # The mockup's dotted underline: radial-gradient(circle, #6a6a6a 2.3px,
    # transparent 2.9px) in a 10 x 8 tile, repeated along each phrase.
    img = QImage(10, 8, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    for y in range(8):
        for x in range(10):
            # Average 4x4 subsamples for a smooth edge.
            cover = 0.0
            for sy in range(4):
                for sx in range(4):
                    d = ((x + (sx + 0.5) / 4 - 5) ** 2 + (y + (sy + 0.5) / 4 - 4) ** 2) ** 0.5
                    cover += 1.0 if d <= 2.3 else max(0.0, (2.9 - d) / 0.6)
            c = QColor("#6a6a6a")
            c.setAlphaF(min(1.0, cover / 16))
            img.setPixelColor(x, y, c)
    img.save(str(path))


def stroke_icon(path: Path, w: int, h: int, lines, width=3.2, dots=()) -> None:
    """Icons from the mockup's SVGs: square caps, mitred joins, ink colour."""
    img = QImage(w, h, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    pen = QPen(QColor(INK), width)
    pen.setCapStyle(Qt.SquareCap)
    pen.setJoinStyle(Qt.MiterJoin)
    p.setPen(pen)
    for pts in lines:
        path_ = QPainterPath(QPointF(*pts[0]))
        for pt in pts[1:]:
            path_.lineTo(QPointF(*pt))
        p.drawPath(path_)
    p.setBrush(QBrush(QColor(INK)))
    for cx, cy, r in dots:
        p.drawEllipse(QPointF(cx, cy), r, r)
    p.end()
    img.save(str(path))


def icons(folder: Path) -> None:
    stroke_icon(folder / "back.png", 56, 56, [[(44, 28), (12, 28)], [(24, 15), (11, 28), (24, 41)]])
    stroke_icon(folder / "menu.png", 56, 56, [], dots=[(28, 13, 3.2), (28, 28, 3.2), (28, 43, 3.2)])
    stroke_icon(folder / "close.png", 56, 56, [[(16, 16), (40, 40)], [(40, 16), (16, 40)]])
    stroke_icon(folder / "grab.png", 96, 22, [[(4, 4), (48, 18), (92, 4)]], width=4)


def icon(path: Path, size: int) -> None:
    img = QImage(size, size, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    s = size / 128.0
    p.setPen(QPen(QColor("black"), 6 * s))
    p.setBrush(QBrush(QColor("white")))
    p.drawRoundedRect(QRectF(5 * s, 5 * s, 118 * s, 118 * s), 20 * s, 20 * s)

    fid = QFontDatabase.addApplicationFont(str(UI / "fonts" / "NotoSerif-Regular.ttf"))
    family = QFontDatabase.applicationFontFamilies(fid)[0]
    font = QFont(family)
    font.setPixelSize(int(76 * s))
    font.setBold(True)
    p.setFont(font)
    p.setPen(QColor("black"))
    p.drawText(QRectF(0, 4 * s, size, 92 * s), Qt.AlignCenter, "Ñ")

    p.setPen(Qt.NoPen)
    p.setBrush(QBrush(QColor("black")))
    for i in range(6):
        p.drawEllipse(QPointF((34 + i * 12) * s, 102 * s), 3.2 * s, 3.2 * s)
    p.end()
    img.save(str(path))


def main() -> int:
    app = QGuiApplication(sys.argv[:1] + ["-platform", "offscreen"])
    (UI / "images").mkdir(parents=True, exist_ok=True)
    dots_tile(UI / "images" / "dots.png")
    icons(UI / "images")
    icon(ROOT / "app" / "icon.png", 128)
    print("assets written")
    del app
    return 0


if __name__ == "__main__":
    sys.exit(main())
