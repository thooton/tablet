"""Automated end-to-end test of the app in the emulator.

    python emulator/test_app.py [--show] [--shots DIR]

Drives the real QML + backend with simulated finger taps and swipes, checks
what happens, and saves greyscale screenshots of every screen (default:
build/emulator/test-shots/). Exit code 0 means every check passed.
"""
import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PySide6.QtCore import QObject, QPoint, QPointF, Qt  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QJSValue  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SCREEN_W, SCREEN_H = 1404, 1872
TEXT_SIZES = [28, 32, 36, 40, 46, 54, 64]  # app/ui/js/theme.js


class Failed(Exception):
    pass


class Driver:
    def __init__(self, emu, shots: Path):
        self.emu = emu
        self.view = emu.view
        self.shots = shots
        self.n = 0
        self.passed = 0
        self._app = None

    # -- helpers ---------------------------------------------------------------
    @property
    def app(self):
        # Keep one wrapper for the app's root item for the whole run.
        if self._app is None:
            self._app = self.emu.app
        return self._app

    def lookup(self, name):
        obj = self.app.findChild(QObject, name)
        if obj is not None:
            return obj
        # Repeater delegates are only reachable through the visual tree.
        todo = [self.app]
        while todo:
            item = todo.pop()
            if item.objectName() == name:
                return item
            todo.extend(item.childItems())
        return None

    @staticmethod
    def descendants(item, name):
        found, todo = [], list(item.childItems())
        while todo:
            it = todo.pop(0)
            if it.objectName() == name:
                found.append(it)
            todo.extend(it.childItems())
        return found

    def find(self, name):
        obj = self.lookup(name)
        if obj is None:
            raise Failed(f"no item named {name!r}")
        return obj

    def prop(self, obj, name):
        v = obj.property(name)
        if isinstance(v, QJSValue):
            v = v.toVariant()
        return v

    def visible(self, name):
        obj = self.lookup(name)
        return obj is not None and obj.isVisible()

    def wait(self, ms=150):
        QTest.qWait(ms)

    def wait_until(self, what, predicate, timeout=8.0):
        end = time.time() + timeout
        while time.time() < end:
            QTest.qWait(30)
            try:
                if predicate():
                    return
            except Exception:
                pass
        raise Failed(f"timed out waiting for {what}")

    def check(self, cond, message):
        if not cond:
            raise Failed(message)
        self.passed += 1
        print(f"  ok  {message}")

    def scene_point(self, item, x, y):
        p = item.mapToScene(QPointF(x, y))
        return QPoint(round(p.x()), round(p.y()))

    def tap_at(self, x, y):
        QTest.mouseClick(self.view, Qt.LeftButton, Qt.NoModifier, QPoint(round(x), round(y)))
        self.wait()

    def tap(self, name_or_item):
        item = self.find(name_or_item) if isinstance(name_or_item, str) else name_or_item
        if not item.isVisible():
            raise Failed(f"{name_or_item} is not visible")
        p = self.scene_point(item, item.property("width") / 2, item.property("height") / 2)
        self.tap_at(p.x(), p.y())

    def drag(self, x0, y0, x1, y1, steps=6):
        start, end = QPoint(round(x0), round(y0)), QPoint(round(x1), round(y1))
        QTest.mousePress(self.view, Qt.LeftButton, Qt.NoModifier, start)
        for i in range(1, steps + 1):
            QTest.mouseMove(self.view, start + (end - start) * (i / steps))
            QTest.qWait(10)
        QTest.mouseRelease(self.view, Qt.LeftButton, Qt.NoModifier, end)
        self.wait()

    def swipe(self, dx, y=1000):
        self.drag(SCREEN_W / 2 - dx / 2, y, SCREEN_W / 2 + dx / 2, y)

    def shot(self, name):
        self.n += 1
        path = self.emu.screenshot(self.shots / f"{self.n:02d}-{name}.png")
        print(f"      screenshot {path.name}")

    def state(self):
        return json.loads((self.emu_data / "state.json").read_text(encoding="utf-8"))

    # -- library helpers -------------------------------------------------------
    def library(self):
        return self.find("library")

    def tap_story(self, story_id):
        # Swipe to the library page that holds the story, as a reader would.
        view = self.library()
        ids = [s["id"] for s in self.prop(view, "shown")]
        target = ids.index(story_id) // 8
        while self.prop(view, "currentPage") != target:
            self.swipe(-500 if self.prop(view, "currentPage") < target else 500)
        self.tap(f"row_{story_id}")
        self.wait_until("the story to open", lambda: self.prop(self.app, "view") == "reader"
                        and self.prop(self.app, "story")["id"] == story_id and self.pages())

    # -- reader helpers --------------------------------------------------------
    def reader(self):
        return self.find("reader")

    def pages(self):
        return self.prop(self.reader(), "pages") or []

    def page(self):
        return self.prop(self.reader(), "page")

    def page_index(self):
        return self.prop(self.reader(), "pageIndex")

    def tokens(self):
        return self.prop(self.app, "story")["tokens"]

    def tap_seg(self, seg):
        area = self.find("textArea")
        line_h = self.prop(self.reader(), "lineHeight")
        p = self.scene_point(area, seg["x"] + seg["w"] / 2, seg["y"] + line_h / 2)
        self.tap_at(p.x(), p.y())

    def translations(self):
        pop = self.find("popover")
        if not pop.isVisible():
            return []
        return [t.property("text") for t in self.descendants(pop, "translation") if t.isVisible()]

    def open_toolbar(self):
        if not self.prop(self.reader(), "toolbarOpen"):
            self.tap_at(SCREEN_W / 2, 20)  # above the first line of text
        self.wait_until("the toolbar", lambda: self.visible("toolbar"))


def check_glyphs(d: Driver):
    """Every character in the UI's strings and the stories must exist in the
    bundled fonts, or the tablet may draw empty boxes."""
    from PySide6.QtGui import QRawFont

    fonts = {name: QRawFont(str(ROOT / "app" / "ui" / "fonts" / f"{name}.ttf"), 40)
             for name in ("NotoSerif-Regular", "IBMPlexSans-Regular", "AtkinsonHyperlegible-Regular")}
    missing = {}

    def need(ch, where, font_names):
        if ord(ch) > 127 and not (0x300 <= ord(ch) <= 0x36F):
            lacking = [n for n in font_names if not fonts[n].supportsCharacter(ord(ch))]
            if lacking:
                missing.setdefault(f"U+{ord(ch):04X}", set()).add(where)

    for f in (ROOT / "app" / "ui").rglob("*.qml"):
        # Only string literals are drawn (comments are not).
        for s in re.findall(r'"((?:[^"\\\n]|\\.)*)"', f.read_text(encoding="utf-8")):
            for ch in set(s):
                need(ch, f.name, ("NotoSerif-Regular", "IBMPlexSans-Regular"))
    for f in (ROOT / "stories").glob("*.json"):
        story = json.loads(f.read_text(encoding="utf-8-sig"))
        reading = "".join(p[0] for p in story["content"]) + story.get("title", "")
        ui = "".join(" ".join(p[1]) if isinstance(p[1], list) else (p[1] or "") for p in story["content"])
        ui += story.get("title", "") + story.get("description", "")
        for ch in set(reading):  # any of the three reading fonts
            need(ch, f.name, fonts.keys())
        for ch in set(ui):       # translations, titles and summaries use Plex
            need(ch, f.name, ("IBMPlexSans-Regular",))
    d.check(not missing, "all characters exist in the bundled fonts" + (f": missing {missing}" if missing else ""))


def check_pages(d: Driver, label):
    """Every word sits inside the text area, nothing overlaps, lines are
    justified, the title has its own space on page one, and every
    translatable token is tappable on some page."""
    reader = d.reader()
    pages = d.pages()
    area = d.find("textArea")
    aw, ah = area.property("width"), area.property("height")
    line_h = d.prop(reader, "lineHeight")
    ragged = []
    for i, p in enumerate(pages):
        for it in p["pieces"]:
            if it["x"] < -0.5 or it["x"] + it["w"] > aw + 0.5 or it["y"] + line_h > ah + 0.5:
                raise Failed(f"{label}, page {i + 1}: {it['text']!r} is outside the text area")
        rows = {}
        for it in p["pieces"]:
            rows.setdefault(it["y"], []).append(it)
        for row in rows.values():
            row.sort(key=lambda it: it["x"])
            for a, b in zip(row, row[1:]):
                if a["x"] + a["w"] > b["x"] + 0.5:
                    raise Failed(f"{label}, page {i + 1}: {a['text']!r} overlaps {b['text']!r}")
        # A line followed by an unindented line is mid-paragraph: it must be
        # justified to the right margin.
        ys = sorted(rows)
        for y, next_y in zip(ys, ys[1:]):
            if min(it["x"] for it in rows[next_y]) < 1:
                end = max(it["x"] + it["w"] for it in rows[y])
                if abs(end - aw) > 1 and len(rows[y]) > 1:
                    ragged.append(" ".join(it["text"] for it in rows[y]))
        for s in p["segs"]:
            if not any(abs(s["y"] - y) < 0.5 for y in rows):
                raise Failed(f"{label}, page {i + 1}: a dotted segment has no text")
    title_bottom = d.find("titleBlock").property("height")
    if pages and pages[0]["pieces"] and min(it["y"] for it in pages[0]["pieces"]) < title_bottom:
        raise Failed(f"{label}: text starts under the title")
    if ragged:
        raise Failed(f"{label}: lines not justified: {ragged[:3]}")
    tokens = d.tokens()
    seen = sorted({s["tok"] for p in pages for s in p["segs"]})
    wanted = [i for i, t in enumerate(tokens) if t[1]]
    if seen != wanted:
        raise Failed(f"{label}: {len(set(wanted) - set(seen))} translatable tokens are not tappable")
    d.check(True, f"{label}: {len(pages)} pages, {len(wanted)} tappable phrases, justified, inside the page")


def set_setting(d: Driver, key, value):
    from PySide6.QtCore import QMetaObject, Q_ARG
    QMetaObject.invokeMethod(d.app, "setSetting", Q_ARG("QVariant", key), Q_ARG("QVariant", value))
    d.wait(50)


def check_all_stories(d: Driver):
    """Lay out every story at the smallest and largest text size and in
    every font."""
    from PySide6.QtCore import QMetaObject, Q_ARG
    app, reader = d.app, d.reader()
    for story in d.prop(app, "library")["stories"]:
        QMetaObject.invokeMethod(app, "openStory", Q_ARG("QVariant", story["id"]))
        d.wait_until(f"{story['id']} to open", lambda: d.prop(app, "view") == "reader"
                     and d.prop(app, "story")["id"] == story["id"] and d.pages())
        for font, size in (("serif", 0), ("serif", 6), ("sans", 6), ("atkinson", 0)):
            set_setting(d, "font", font)
            set_setting(d, "textSize", size)
            d.wait_until("relayout", lambda: d.prop(reader, "fontSize") == TEXT_SIZES[size])
            d.wait(250)
            check_pages(d, f"{story['title']} ({font}, {TEXT_SIZES[size]}px)")
        set_setting(d, "font", "serif")
        set_setting(d, "textSize", 3)
        d.wait_until("default size", lambda: d.prop(reader, "fontSize") == 40)
        QMetaObject.invokeMethod(app, "showLibrary")
        d.wait_until("the library", lambda: d.prop(app, "view") == "library")


def run(d: Driver):
    check_glyphs(d)
    app = d.app

    print("library")
    d.wait_until("the library", lambda: d.prop(app, "library") is not None)
    lib = d.prop(app, "library")
    stories = lib["stories"]
    d.check(len(stories) >= 9, f"library lists {len(stories)} stories")
    d.check(not lib["errors"], "no broken story files")
    view = d.library()
    npages = (len(stories) + 7) // 8
    d.check(d.prop(view, "pageCount") == npages and d.find("libraryPage").property("text") == f"1 de {npages}",
            f"eight stories per page, \"1 de {npages}\" in the corner")
    d.wait(300)
    d.shot("library")
    d.swipe(-500)
    d.check(d.prop(view, "currentPage") == 1 and d.find("libraryPage").property("text") == f"2 de {npages}",
            "swipe left shows the next page")
    d.shot("library-page2")
    d.swipe(500)
    d.check(d.prop(view, "currentPage") == 0, "swipe right goes back")

    d.tap("tab_A1")
    shown = d.prop(view, "shown")
    d.check(shown and all(s["level"] == "A1" for s in shown), f"A1 tab shows only the {len(shown)} A1 stories")
    d.shot("library-a1")
    d.tap("tab_C1")
    d.check(not d.prop(view, "shown") and "C1" in d.find("listMessage").property("text"),
            "an empty level says there are no stories")
    d.tap("tab_TODOS")
    d.check(len(d.prop(view, "shown")) == len(stories), "TODOS shows every story again")

    d.tap("libraryMenuButton")
    d.check(d.visible("libraryMenu"), "the library menu opens")
    d.tap("menu_reload")
    d.check(not d.visible("libraryMenu"), "Recargar cuentos closes the menu")

    big = max(stories, key=lambda s: s["tokens"])
    print(f"read {big['title']!r}")
    d.tap_story(big["id"])
    reader = d.reader()
    pages = d.pages()
    d.check(len(pages) >= 2, f"laid out on {len(pages)} pages at 40 px")
    d.check(d.page_index() == 0 and d.find("titleBlock").isVisible(), "starts on page 1 with the title")
    d.check(not d.visible("toolbar") and not d.visible("footerPage"), "only the text is on screen")
    d.wait(200)
    d.shot("reader")
    check_pages(d, "page layout")
    tokens = d.tokens()

    print("translations")
    segs = d.page()["segs"]
    phrase = next(s for s in segs if " " in tokens[s["tok"]][0])
    d.tap_seg(phrase)
    d.check(d.prop(reader, "selectedTok") == phrase["tok"], f"tapping {tokens[phrase['tok']][0]!r} selects it")
    d.check(d.translations() == tokens[phrase["tok"]][1], f"the popover shows {tokens[phrase['tok']][1]}")
    pop = d.find("popover")
    px, py, pw, ph = (pop.property(k) for k in ("x", "y", "width", "height"))
    d.check(px >= 58 and px + pw <= SCREEN_W - 58 and py >= 0 and py + ph <= SCREEN_H,
            "the popover stays on screen")
    d.shot("reader-translation")
    multi = next((s for s in segs if len(tokens[s["tok"]][1]) > 1 and s["tok"] != phrase["tok"]), None)
    if multi:
        d.tap_seg(multi)
        d.check(d.translations() == tokens[multi["tok"]][1],
                f"tapping another phrase shows its {len(tokens[multi['tok']][1])} translations")
        d.shot("reader-translation-alternatives")
    low = max(segs, key=lambda s: s["y"])
    d.tap_seg(low)
    d.check(d.prop(pop, "below") is False, "near the bottom the popover opens above the phrase")
    last = d.page()["pieces"][-1]
    area = d.find("textArea")
    blank = d.scene_point(area, area.property("width") - 20, last["y"] + d.prop(reader, "lineHeight") * 1.5)
    if blank.y() < SCREEN_H - 146:
        d.tap_at(blank.x(), blank.y())
    else:
        d.tap_seg(low)
    d.check(d.prop(reader, "selectedTok") == -1 and not pop.isVisible(), "tapping elsewhere closes the popover")
    d.check(d.page_index() == 0, "closing the popover does not turn the page")

    print("turn pages")
    d.tap_at(SCREEN_W - 40, 900)
    d.check(d.page_index() == 1, "tapping the right margin goes to page 2")
    d.check(not d.find("titleBlock").isVisible(), "no title after page 1")
    d.shot("reader-page2")
    top = min(d.page()["segs"], key=lambda s: (s["y"], s["x"]))
    d.tap_seg(top)
    d.check(d.prop(reader, "selectedTok") == top["tok"] and not d.visible("toolbar"),
            "on page 2 a word in the top line shows its translation, not the toolbar")
    d.tap_seg(top)
    d.check(d.prop(reader, "selectedTok") == -1, "tapping it again closes it")
    d.tap_at(40, 900)
    d.check(d.page_index() == 0, "tapping the left margin goes back")
    d.swipe(-500)
    d.check(d.page_index() == 1, "swipe left turns forward")
    d.swipe(500)
    d.check(d.page_index() == 0, "swipe right turns back")
    d.swipe(-500)
    d.wait_until("progress to be saved", lambda: d.state()["stories"][big["id"]]["token"] > 0)
    d.check(True, "reading position saved by the backend")

    print("page number")
    d.tap_at(SCREEN_W / 2, SCREEN_H - 60)
    d.check(d.visible("footerPage") and d.find("footerPage").property("text") == f"Pág. 2 de {len(d.pages())}",
            "tapping the bottom shows \"Pág. 2 de N\"")
    d.wait_until("the footer setting to be saved", lambda: d.state()["settings"]["footer"] is True)
    d.check(True, "the page number setting is remembered")
    d.shot("reader-page-number")
    d.tap_at(SCREEN_W / 2, SCREEN_H - 60)
    d.check(not d.visible("footerPage"), "tapping the bottom again hides it")

    print("toolbar")
    d.open_toolbar()
    d.check(d.find("toolbarTitle").property("text") == big["title"], "the toolbar shows the story title")
    d.check(d.find("toolbarPage").property("text") == f"Página 2 de {len(d.pages())}", "and the page number")
    d.check(" min restante" in d.find("toolbarTime").property("text"), "and the time left")
    d.shot("reader-toolbar")
    slider = d.find("slider")
    a = d.scene_point(slider, slider.property("width") * 0.5, 30)
    b = d.scene_point(slider, 0, 30)
    d.drag(a.x(), a.y(), b.x(), b.y())
    d.check(d.page_index() == 0, "dragging the slider to the start goes to page 1")
    d.open_toolbar()
    d.tap("toolbarGrab")
    d.check(not d.visible("toolbar"), "the handle hides the toolbar")
    d.open_toolbar()
    d.tap_at(SCREEN_W / 2, 900)
    d.check(not d.visible("toolbar"), "tapping the page hides the toolbar")

    print("text settings")
    d.open_toolbar()
    d.tap("textSettingsButton")
    d.check(d.visible("textSheet") and not d.visible("toolbar"), "Aa opens the Texto box in place of the toolbar")
    d.shot("reader-text-settings")
    d.tap_at(SCREEN_W - 40, 900)  # outside the box: closes it, does not turn
    d.check(not d.visible("textSheet") and d.page_index() == 0, "tapping outside closes the box")
    d.tap_at(SCREEN_W - 40, 900)
    token = d.page()["firstToken"]
    n_before = len(d.pages())
    d.open_toolbar()
    d.tap("textSettingsButton")
    d.tap("size_6")
    d.wait_until("bigger text", lambda: d.prop(reader, "fontSize") == 64)
    d.wait(300)
    d.check(len(d.pages()) > n_before, f"the largest size needs more pages ({n_before} -> {len(d.pages())})")
    cur = d.page()
    d.check(cur["firstToken"] <= token <= max(cur["lastToken"], cur["firstToken"]),
            "the page you were reading stays on screen")
    d.tap("font_sans")
    d.wait_until("the sans font", lambda: "Plex" in d.prop(reader, "family"))
    d.tap("dotsOff")
    d.check(d.prop(reader, "showDots") is False, "dots can be hidden")
    d.shot("reader-text-settings-changed")
    d.tap("sheetClose")
    d.check(not d.visible("textSheet"), "× closes the box")
    d.shot("reader-large-sans-no-dots")
    s = d.state()["settings"]
    d.check(s["textSize"] == 6 and s["font"] == "sans" and s["dots"] is False, "text settings are saved")
    d.open_toolbar()
    d.tap("textSettingsButton")
    d.tap("size_3")
    d.tap("font_serif")
    d.tap("dotsOn")
    d.tap("sheetClose")
    d.wait_until("40 px Noto Serif", lambda: d.prop(reader, "fontSize") == 40 and "Serif" in d.prop(reader, "family"))
    d.check(d.prop(reader, "showDots"), "back to the defaults")

    print("story menu")
    d.open_toolbar()
    d.tap("readerMenuButton")
    d.check(d.visible("readerMenu"), "⋮ opens the story menu")
    d.shot("reader-menu")
    d.tap("menu_read")
    d.wait_until("finished flag", lambda: d.state()["stories"][big["id"]]["finished"])
    d.check(not d.visible("toolbar"), "Marcar como leído marks the story read and closes the menu")
    d.open_toolbar()
    d.tap("readerMenuButton")
    d.tap("menu_reset")
    d.wait_until("progress reset", lambda: big["id"] not in d.state()["stories"])
    d.check(d.page_index() == 0, "Reiniciar progreso forgets the story and goes to page 1")
    d.tap_at(SCREEN_W - 40, 900)
    d.open_toolbar()
    d.tap("readerMenuButton")
    d.tap("menu_start")
    d.check(d.page_index() == 0, "Ir al principio goes to page 1")

    print("finish the story")
    for _ in range(len(d.pages())):
        d.tap_at(SCREEN_W - 40, 900)
    d.check(d.page_index() == len(d.pages()) - 1, "reached the last page")
    d.wait_until("finished flag", lambda: d.state()["stories"][big["id"]]["finished"])
    d.check(True, "reaching the last page marks the story read")

    print("back to the library")
    d.open_toolbar()
    d.tap("readerBack")
    d.wait_until("the library", lambda: d.prop(app, "view") == "library")
    d.wait_until("refreshed library", lambda: d.prop(app, "library")["stories"][0]["id"] == big["id"])
    d.check(True, "the story just read is now first")
    while d.prop(d.library(), "currentPage") > 0:
        d.swipe(500)
    row = d.find(f"row_{big['id']}")
    status = d.descendants(row, "rowStatus")[0]
    d.check(status.property("text") == "100%", "and shows 100%")
    dots = d.descendants(row, "rowDots")[0]
    d.check(all(c.childItems()[0].property("width") == 10 for c in dots.childItems() if c.property("width") == 15),
            "with every progress dot filled")
    d.wait(200)
    d.shot("library-after")

    print("every story, smallest and largest text, every font")
    check_all_stories(d)

    print("close")
    d.tap("libraryBack")
    d.wait_until("the app to close", lambda: d.emu.closed)
    d.check(True, "← closes the app")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", action="store_true", help="show the window while testing")
    ap.add_argument("--shots", type=Path, default=None)
    args = ap.parse_args()

    qt_args = sys.argv[:1] + ([] if args.show else ["-platform", "offscreen"])
    qapp = QGuiApplication(qt_args)
    import emulator as E

    shots = args.shots or (E.BUILD / "test-shots")
    for old in shots.glob("*.png") if shots.exists() else []:
        old.unlink()
    data = E.BUILD / "test-data"
    # Late backend start: the app must cope with AppLoad dropping early messages.
    emu = E.Emulator(data, fresh=True, scale=1.0, backend_delay=700)
    emu.view.show()
    d = Driver(emu, shots)
    d.emu_data = data
    try:
        run(d)
    except Failed as e:
        print(f"FAILED: {e}")
        d.shot("failure")
        emu.shutdown()
        return 1
    emu.shutdown()
    print(f"All {d.passed} checks passed. Screenshots in {shots}")
    del qapp
    return 0


if __name__ == "__main__":
    sys.exit(main())
