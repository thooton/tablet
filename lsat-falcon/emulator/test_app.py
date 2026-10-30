"""Automated end-to-end test of LSAT Falcon in the emulator.

    python emulator/test_app.py [--shots DIR] [--sample N]

Drives the real QML and backend with simulated taps and swipes, checks what
happens, fails on any QML warning, and saves greyscale screenshots of each
screen (default build/emulator/test-shots/). Exit code 0 means every check
passed.
"""
import argparse
import json
import random
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "emulator"
sys.path.insert(0, str(ROOT.parent / "tools"))
sys.path.insert(0, str(ROOT / "tools"))

from PySide6.QtCore import QPoint, QPointF, Qt, qInstallMessageHandler  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QJSValue, QQmlExpression  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

import build  # noqa: E402
import emulator  # noqa: E402


def open_app(state: Path, fresh=True):
    """The app in the emulator, keeping its settings and position in state,
    with the deck compiled once from deck/ (tools/build_data.py)."""
    build.write_qrc()
    data = ROOT / "build" / "data"
    if not (data / "meta.json").exists():
        subprocess.run([sys.executable, str(ROOT / "tools" / "build_data.py"), "--out", str(data)], check=True)
    return emulator.Emulator(ROOT, env={"LSAT_FALCON_ROOT": str(data.parent), "LSAT_FALCON_DATA": str(state)},
                             data=state, fresh=fresh, scale=1.0)

WARNINGS = []


def on_message(mode, context, message):
    if "locale" in message or "UTF-8" in message:
        return
    WARNINGS.append(message)
    print("  QML:", message)


class Failed(Exception):
    pass


class Driver:
    def __init__(self, emu, shots: Path):
        self.emu = emu
        self.view = emu.view
        self.shots = shots
        self.n = 0
        self.passed = 0

    @property
    def app(self):
        return self.emu.app

    def js(self, expr):
        e = QQmlExpression(self.view.engine().contextForObject(self.app), self.app, expr)
        v = e.evaluate()
        if isinstance(v, tuple):
            v = v[0]
        if e.hasError():
            raise Failed(f"{expr}: {e.error().toString()}")
        return v.toVariant() if isinstance(v, QJSValue) else v

    def find(self, name):
        todo = [self.app]
        while todo:
            item = todo.pop()
            if item.objectName() == name and item.isVisible():
                return item
            todo.extend(item.childItems())
        raise Failed(f"no visible item named {name!r}")

    def wait(self, ms=200):
        QTest.qWait(ms)

    def wait_until(self, what, predicate, timeout=10.0):
        end = time.time() + timeout
        while time.time() < end:
            QTest.qWait(30)
            try:
                if predicate():
                    return
            except Failed:
                pass
        raise Failed(f"timed out waiting for {what}")

    def check(self, cond, message):
        if not cond:
            raise Failed(message)
        self.passed += 1
        print(f"  ok  {message}")

    def tap(self, name):
        item = self.find(name)
        p = item.mapToScene(QPointF(item.property("width") / 2, item.property("height") / 2))
        QTest.mouseClick(self.view, Qt.LeftButton, Qt.NoModifier, QPoint(round(p.x()), round(p.y())))
        self.wait(300)

    def swipe_up(self):
        QTest.mousePress(self.view, Qt.LeftButton, Qt.NoModifier, QPoint(700, 1400))
        for i in range(1, 7):
            QTest.mouseMove(self.view, QPoint(700, 1400 - i * 130))
            QTest.qWait(10)
        QTest.mouseRelease(self.view, Qt.LeftButton, Qt.NoModifier, QPoint(700, 620))
        self.wait(300)

    def shot(self, name):
        self.n += 1
        path = self.emu.screenshot(self.shots / f"{self.n:02d}-{name}.png")
        print(f"      screenshot {path.name}")


def run(d: Driver, sample: int):
    print("loading")
    d.wait_until("the deck", lambda: d.js("root.view") == "drill")
    d.wait_until("the first question", lambda: d.js("drill.question !== null"))
    d.wait(400)
    d.check(d.js("drill.deck.length") == 6363, "drills 6363 questions (held-out tests left out)")
    d.check(d.js("drill.settings.shuffle") is True, "shuffle is on by default")
    d.shot("drill")

    print("drilling")
    d.js("drill.update({ sections: ['LR'] })")
    d.wait_until("an LR question", lambda: d.js("drill.question !== null && !drill.question.isRC"))
    d.wait(300)
    qi = d.js("drill.qi")
    correct = d.js("drill.question.correct")
    wrong = "A" if correct != "A" else "B"
    d.tap("choice_" + wrong)
    d.check(d.js("drill.answers[drill.qi]") == wrong, f"tapping choice {wrong} answers it")
    d.check(d.js("drill.revealed") is True, "the answer is revealed")
    d.shot("answered")
    d.swipe_up()
    d.shot("explanation")
    d.tap("mainButton")
    d.wait_until("the next question", lambda: d.js("drill.qi") != qi)
    d.check(d.js("Object.keys(drill.answers).length") == 0, "Continue moves on and forgets the answer")

    print("settings")
    d.tap("settingsButton")
    d.check(d.js("drill.menuOpen") is True, "the gear opens Settings")
    d.tap("section_RC")
    d.check(d.js("drill.settings.sections.join()") == "LR,RC", "a section chip toggles")
    d.shot("settings")
    d.js("drill.update({ sections: ['RC'] })")
    d.js("drill.menuOpen = false")
    d.wait_until("a passage", lambda: d.js("drill.readingPassage"))
    d.check(d.js("drill.siblings.length") > 1, "a passage opens on its P tab with its questions")
    d.shot("passage")
    d.tap("mainButton")
    d.check(d.js("!drill.readingPassage && drill.qi === drill.siblings[0]"), "Continue goes to the first question")
    d.shot("rc-question")

    print("state is saved")
    d.wait(400)
    state = json.loads((d.emu_state / "state.json").read_text())
    d.check(state["settings"]["sections"] == ["RC"], "settings are saved")
    d.check(state["position"] == d.js("drill.positionKey"), f"position is saved ({state['position']})")
    d.js("drill.update({ sections: [] })")

    print(f"rendering {sample} random questions")
    random.seed(1)
    n = d.js("drill.deck.length")
    picks = random.sample(range(n), sample)
    before = len(WARNINGS)
    for i in picks:
        d.js(f"drill.update({{ heldOut: true }}), drill.openQuestion({i}), drill.openQuestion({i})")
        d.wait_until(f"question {i}", lambda: d.js(f"drill.question !== null && drill.question.i === {i}"), 5)
        d.js("drill.select(drill.question.correct)")
        d.wait(40)
    d.check(len(WARNINGS) == before, f"{sample} questions render with their explanations, no QML warnings")
    d.js("drill.update({ heldOut: false })")

    print("practice test")
    d.tap("practiceButton")
    d.check(d.js("root.view") == "practice", "the stopwatch opens a practice test")
    d.shot("exam-setup")
    d.tap("startButton")
    d.tap("beginButton")
    d.wait(400)
    d.check(d.js("practiceLoader.item.phase") == "section", "Start, Begin section")
    d.tap("choice_C")
    d.check(len(d.js("Object.keys(practiceLoader.item.answers)")) == 1, "an answer is recorded, not revealed")
    d.shot("exam-section")
    d.tap("nextButton")
    d.check(d.js("practiceLoader.item.phase") == "section", "Next stays in the section")
    sections = d.js("practiceLoader.item.sections.length")
    for _ in range(sections):
        d.js("practiceLoader.item.phase = 'section'")
        d.js("practiceLoader.item.finishSection()")
    d.check(d.js("practiceLoader.item.phase") == "results", "finishing every section shows the score")
    d.shot("exam-results")
    d.check(120 <= d.js("Deck.scaledScore(practiceLoader.item.exam.test, 1, 100).score") <= 180, "scores are on the 120–180 scale")
    d.js("practiceLoader.item.phase = 'review'")
    d.wait(400)
    d.shot("exam-review")
    d.js("practiceLoader.item.exit()")
    d.check(d.js("root.view") == "drill", "leaving the test returns to drilling")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--shots", type=Path, default=BUILD / "test-shots")
    ap.add_argument("--sample", type=int, default=150)
    args = ap.parse_args()

    app = QGuiApplication(sys.argv[:1])
    qInstallMessageHandler(on_message)
    state_dir = BUILD / "test-state"
    emu = open_app(state_dir)
    emu.view.show()
    d = Driver(emu, args.shots)
    d.emu_state = state_dir
    try:
        run(d, args.sample)
    except Failed as e:
        print("FAILED:", e)
        emu.shutdown()
        return 1
    emu.shutdown()
    if WARNINGS:
        print(f"FAILED: {len(WARNINGS)} QML warnings")
        return 1
    print(f"All {d.passed} checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
