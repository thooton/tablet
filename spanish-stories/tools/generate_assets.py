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


INK = "#000000"


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
    """An open book in AppLoad's rounded frame, drawn in the line icons' ink."""
    img = QImage(size, size, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    s = size / 128.0
    p.setPen(QPen(QColor("black"), 6 * s))
    p.setBrush(QBrush(QColor("white")))
    p.drawRoundedRect(QRectF(5 * s, 5 * s, 118 * s, 118 * s), 20 * s, 20 * s)

    pen = QPen(QColor("black"), 6 * s, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
    p.setPen(pen)
    p.setBrush(Qt.NoBrush)
    for side in (-1, 1):
        def x(v):
            return (64 + side * v) * s
        # A page: from the spine out along a gentle curve, down, and back.
        page = QPainterPath(QPointF(x(0), 42 * s))
        page.cubicTo(QPointF(x(12), 33 * s), QPointF(x(28), 31 * s), QPointF(x(42), 34 * s))
        page.lineTo(x(42), 92 * s)
        page.cubicTo(QPointF(x(28), 89 * s), QPointF(x(12), 91 * s), QPointF(x(0), 100 * s))
        p.drawPath(page)
        # Lines of text.
        thin = QPen(QColor("black"), 4 * s, Qt.SolidLine, Qt.RoundCap)
        p.setPen(thin)
        for i, y in enumerate((50, 61, 72)):
            p.drawLine(QPointF(x(10), (y + 1) * s), QPointF(x(34 if i < 2 else 26), (y - 1) * s))
        p.setPen(pen)
    p.drawLine(QPointF(64 * s, 42 * s), QPointF(64 * s, 100 * s))
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
