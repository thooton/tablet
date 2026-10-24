"""Opens the app in the emulator, runs a few named steps and saves a
screenshot after each one. For looking at screens while working on them:

    python emulator/snap.py OUTDIR step [step ...]

Steps: wait, tap:X,Y, swipe-up, swipe-down, key:name (objectName to tap),
eval:JS (run on the app's root item).
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PySide6.QtCore import QObject, QPoint, QPointF, Qt  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QJSValue  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

import emulator  # noqa: E402


def main():
    out = Path(sys.argv[1])
    steps = sys.argv[2:]
    app = QGuiApplication(sys.argv[:1])
    emu = emulator.Emulator(emulator.BUILD / "snap-state", fresh="--keep" not in steps, scale=1.0)
    steps = [s for s in steps if s != "--keep"]
    emu.view.show()
    end = time.time() + 20
    while time.time() < end:
        QTest.qWait(50)
        if emu.app and emu.app.property("view") == "drill":
            break
    QTest.qWait(600)
    root = emu.app
    for n, step in enumerate(["start"] + steps):
        if step.startswith("tap:"):
            x, y = map(float, step[4:].split(","))
            QTest.mouseClick(emu.view, Qt.LeftButton, Qt.NoModifier, QPoint(round(x), round(y)))
        elif step in ("swipe-up", "swipe-down"):
            y0, y1 = (1400, 600) if step == "swipe-up" else (600, 1400)
            QTest.mousePress(emu.view, Qt.LeftButton, Qt.NoModifier, QPoint(700, y0))
            for i in range(1, 7):
                QTest.mouseMove(emu.view, QPoint(700, round(y0 + (y1 - y0) * i / 6)))
                QTest.qWait(10)
            QTest.mouseRelease(emu.view, Qt.LeftButton, Qt.NoModifier, QPoint(700, y1))
        elif step.startswith("eval:"):
            from PySide6.QtQml import QQmlExpression
            expr = QQmlExpression(emu.view.engine().contextForObject(root), root, step[5:])
            v = expr.evaluate()
            if isinstance(v, tuple):
                v = v[0]
            if isinstance(v, QJSValue):
                v = v.toVariant()
            print("eval:", step[5:], "->", v)
        elif step != "start" and step != "wait":
            print("unknown step", step)
        QTest.qWait(700)
        path = emu.screenshot(out / f"{n:02d}.png")
        print("saved", path)
    emu.shutdown()


if __name__ == "__main__":
    main()
