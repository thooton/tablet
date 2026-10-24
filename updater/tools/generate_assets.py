"""Draws the Updater's AppLoad icon, in the frame Biblioteca's has.

Run with the emulator's Python (it needs PySide6):
    python tools/generate_assets.py
"""
import sys
from pathlib import Path

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QBrush, QColor, QGuiApplication, QImage, QPainter, QPainterPath, QPen

ROOT = Path(__file__).resolve().parent.parent


def icon(path: Path, size: int) -> None:
    img = QImage(size, size, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    s = size / 128.0
    p.setPen(QPen(QColor("black"), 6 * s))
    p.setBrush(QBrush(QColor("white")))
    p.drawRoundedRect(QRectF(5 * s, 5 * s, 118 * s, 118 * s), 20 * s, 20 * s)

    # An arrow down into a tray.
    pen = QPen(QColor("black"), 9 * s, Qt.SolidLine, Qt.SquareCap, Qt.MiterJoin)
    p.setPen(pen)
    p.setBrush(Qt.NoBrush)
    p.drawLine(QPointF(64 * s, 28 * s), QPointF(64 * s, 74 * s))
    arrow = QPainterPath(QPointF(44 * s, 56 * s))
    arrow.lineTo(64 * s, 76 * s)
    arrow.lineTo(84 * s, 56 * s)
    p.drawPath(arrow)
    tray = QPainterPath(QPointF(32 * s, 80 * s))
    tray.lineTo(32 * s, 98 * s)
    tray.lineTo(96 * s, 98 * s)
    tray.lineTo(96 * s, 80 * s)
    p.drawPath(tray)
    p.end()
    img.save(str(path))


def main() -> int:
    app = QGuiApplication(sys.argv[:1] + ["-platform", "offscreen"])
    icon(ROOT / "app" / "icon.png", 128)
    print("assets written")
    del app
    return 0


if __name__ == "__main__":
    sys.exit(main())
