"""Makes the app's fonts and bitmaps from the web app's own assets.

Run with the emulator's Python (it needs PySide6 and fontTools):
    python tools/generate_assets.py [--source ../demon]

Fonts: the web app sets everything in Roboto, from a variable font (weights
100-900). Qt on the tablet is safest with static TrueType, so the weights the
UI uses are cut out of that same font as "Falcon Roboto" instances. Roboto has
no arrows, and the explanations use → ← ↑ ↓ ≠ ✓ (a browser falls back to a
system font for them), so those glyphs are grafted in from Noto Sans Math,
scaled to Roboto's em.

Bitmaps: the web app's stroke icons (src/components/icons.jsx: 24 px box,
1.6 px round-capped strokes) and the falcon, drawn black at the exact pixel
sizes the UI shows them at, plus the launcher icon.
"""
import argparse
import math
import sys
from pathlib import Path

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "app" / "ui"
SCALE = 2.25  # app/ui/js/theme.js: device pixels per CSS pixel


def px(css: float) -> int:
    """Theme.px(): JavaScript's Math.round, which rounds halves up."""
    return math.floor(css * SCALE + 0.5)
FAMILY = "Falcon Roboto"
SYMBOLS = "→←↑↓≠✓"
SYMBOL_FONT = Path("/usr/share/fonts/noto/NotoSansMath-Regular.ttf")

# (file stem, weight, italic)
INSTANCES = [
    ("FalconRoboto-Regular", 400, False),
    ("FalconRoboto-Medium", 500, False),
    ("FalconRoboto-SemiBold", 600, False),
    ("FalconRoboto-Bold", 700, False),
    ("FalconRoboto-Italic", 400, True),
    ("FalconRoboto-BoldItalic", 700, True),
]

STYLE_NAMES = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}


def graft_symbols(font: TTFont, donor: TTFont) -> None:
    scale = font["head"].unitsPerEm / donor["head"].unitsPerEm
    donor_glyphs = donor.getGlyphSet()
    donor_cmap = donor.getBestCmap()
    for ch in SYMBOLS:
        src = donor_cmap.get(ord(ch))
        if src is None:
            sys.exit(f"{SYMBOL_FONT.name} has no glyph for {ch!r}")
        name = f"falcon.{src}"
        rec = DecomposingRecordingPen(donor_glyphs)
        donor_glyphs[src].draw(rec)
        pen = TTGlyphPen(None)
        rec.replay(TransformPen(pen, (scale, 0, 0, scale, 0, 0)))
        font["glyf"][name] = pen.glyph()
        advance, lsb = donor["hmtx"][src]
        font["hmtx"][name] = (round(advance * scale), round(lsb * scale))
        for table in font["cmap"].tables:
            if table.isUnicode():
                table.cmap[ord(ch)] = name
    # glyf's __setitem__ appended the new names to the shared glyph order.
    font.setGlyphOrder(font["glyf"].glyphOrder)


def set_names(font: TTFont, weight: int, italic: bool) -> None:
    style = STYLE_NAMES[weight]
    if italic:
        style = "Italic" if weight == 400 else f"{style} Italic"
    ribbi = weight in (400, 700)
    name = font["name"]
    name.names = [n for n in name.names if n.nameID > 25 or n.nameID in (0, 7, 13, 14)]
    family = FAMILY if ribbi else f"{FAMILY} {STYLE_NAMES[weight]}"
    legacy_style = ("Bold " if weight == 700 else "") + ("Italic" if italic else "")
    legacy_style = legacy_style.strip() or "Regular"
    full = f"{FAMILY} {style}"
    for nid, value in ((1, family), (2, legacy_style), (3, full), (4, full),
                       (6, full.replace(" ", "")), (16, FAMILY), (17, style)):
        name.setName(value, nid, 3, 1, 0x409)
    os2 = font["OS/2"]
    os2.usWeightClass = weight
    sel = os2.fsSelection & ~0b1100001  # clear ITALIC, BOLD, REGULAR
    if italic:
        sel |= 1
    if weight == 700:
        sel |= 1 << 5
    if not italic and weight != 700:
        sel |= 1 << 6
    os2.fsSelection = sel
    font["head"].macStyle = (1 if weight == 700 else 0) | (2 if italic else 0)
    font["post"].italicAngle = -12.0 if italic else 0.0


def fonts(source: Path) -> None:
    out = UI / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    donor = TTFont(str(SYMBOL_FONT))
    for stem, weight, italic in INSTANCES:
        var = TTFont(str(source / "src" / "assets" / "fonts" / ("Roboto-Italic-latin.woff2" if italic else "Roboto-latin.woff2")))
        font = instancer.instantiateVariableFont(var, {"wght": weight})
        font.flavor = None
        for table in ("STAT", "HVAR", "avar"):
            if table in font:
                del font[table]
        graft_symbols(font, donor)
        set_names(font, weight, italic)
        font.save(str(out / f"{stem}.ttf"))
        print(f"  fonts/{stem}.ttf")
    lic = (source / "src" / "assets" / "fonts" / "Roboto-LICENSE.txt").read_text(encoding="utf-8")
    (out / "OFL-Roboto.txt").write_text(lic, encoding="utf-8")
    noto = Path("/usr/share/licenses/noto-fonts/LICENSE")
    if noto.exists():
        (out / "OFL-NotoSansMath.txt").write_text(noto.read_text(encoding="utf-8"), encoding="utf-8")


# ---- icons, from src/components/icons.jsx

STROKE = {
    "close": '<path d="M6 6l12 12M18 6L6 18"/>',
    "clock": '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5.2l3.2 2"/>',
    "stopwatch": '<path d="M9.5 2.8h5"/><circle cx="12" cy="13.2" r="8"/><path d="M12 8.6v4.6"/>',
    "settings": '<circle cx="12" cy="12" r="3.1"/><path d="M19.4 14.4a1.5 1.5 0 00.3 1.7l.1.1a1.8 1.8 0 11-2.6 2.6l-.1-.1a1.5 1.5 0 00-1.7-.3 1.5 1.5 0 00-.9 1.4v.2a1.8 1.8 0 11-3.6 0V20a1.5 1.5 0 00-1-1.4 1.5 1.5 0 00-1.7.3l-.1.1a1.8 1.8 0 11-2.6-2.6l.1-.1a1.5 1.5 0 00.3-1.7 1.5 1.5 0 00-1.4-.9H4a1.8 1.8 0 110-3.6h.2a1.5 1.5 0 001.4-1 1.5 1.5 0 00-.3-1.7l-.1-.1a1.8 1.8 0 112.6-2.6l.1.1a1.5 1.5 0 001.7.3H9.7a1.5 1.5 0 00.9-1.4V4a1.8 1.8 0 113.6 0v.2a1.5 1.5 0 00.9 1.4 1.5 1.5 0 001.7-.3l.1-.1a1.8 1.8 0 112.6 2.6l-.1.1a1.5 1.5 0 00-.3 1.7v.1a1.5 1.5 0 001.4.9h.2a1.8 1.8 0 110 3.6H20a1.5 1.5 0 00-1.4.9z"/>',
    "check": '<path d="M5 12.5l4.2 4.2L19 7" stroke-width="2"/>',
    "chevron": '<path d="M7 10l5 5 5-5"/>',
    "arrow-left": '<path d="M19 12H5m0 0l6-6m-6 6l6 6"/>',
    "arrow-right": '<path d="M5 12h14m0 0l-6-6m6 6l-6 6"/>',
    "bookmark": '<path d="M7 4.5h10a1 1 0 011 1v14l-6-4-6 4v-14a1 1 0 011-1z"/>',
    "bookmark-filled": '<path d="M7 4.5h10a1 1 0 011 1v14l-6-4-6 4v-14a1 1 0 011-1z" fill="#000"/>',
    "strike-a": '<path d="M6.5 17.5L11.2 6h1.6l4.7 11.5"/><path d="M8.6 13.6h6.8"/><path d="M18.5 5.5L5.5 18.5"/>',
    "minus-circle": '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 12h7"/>',
    "info": '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.2"/><circle cx="12" cy="7.7" r="0.9" fill="#000" stroke="none"/>',
}

FALCON = ('<path d="M242.9 20.46c6.7 19.75 19.7 41.39 4 50.44-38.6 22.04-81.4 41.5-106.2 90.7C103.3 235.7 91.69 412 '
          '29.81 451c48.6 3.8 89.69-16.3 108.89-44.2 7.1 34.3 32.6 67 63 84.7-5.2-29-1.8-59.4 19-92.5 16.5 22.9 31.1 '
          '59.3 73.8 75.3-16.4-27.5-13.7-52.8-10.7-84.2 8.8 26.9 38.5 50 72.9 58.9-16.8-18.6-23.9-45.5-21-66 14.6 24.9 '
          '43.4 38.4 67.1 39.7-153.3-179.6-48.7-291.6 79.4-194.4-.5-49.7-31.4-66.7-67.2-95.7-.9-15.4-9.6-29.3-17.5-'
          '43.36-53.7-9.99-121.5-42.01-154.6-68.78zm81.2 74.88c26.1 10.86 46.2 22.56 56.4 35.46-16.6-3.6-39.8-3.5-70-'
          '1.1 15-9.7 16.5-21.7 13.6-34.36z"/>')

# The donation list's coin marks (filled, like the falcon).
GLYPH = {
    "bitcoin": "M23.638 14.904c-1.602 6.43-8.113 10.34-14.542 8.736C2.67 22.05-1.244 15.525.362 9.105 1.962 2.67 8.475-1.243 14.9.358c6.43 1.605 10.342 8.115 8.738 14.548v-.002zm-6.35-4.613c.24-1.59-.974-2.45-2.64-3.03l.54-2.153-1.315-.33-.525 2.107c-.345-.087-.705-.167-1.064-.25l.526-2.127-1.32-.33-.54 2.165c-.285-.067-.565-.132-.84-.2l-1.815-.45-.35 1.407s.975.225.955.236c.535.136.63.486.615.766l-1.477 5.92c-.075.166-.24.406-.614.314.015.02-.96-.24-.96-.24l-.66 1.51 1.71.426.93.242-.54 2.19 1.32.327.54-2.17c.36.1.705.19 1.05.273l-.51 2.154 1.32.33.545-2.19c2.24.427 3.93.257 4.64-1.774.57-1.637-.03-2.58-1.217-3.196.854-.193 1.5-.76 1.68-1.93h.01zm-3.01 4.22c-.404 1.64-3.157.75-4.05.53l.72-2.9c.896.23 3.757.67 3.33 2.37zm.41-4.24c-.37 1.49-2.662.735-3.405.55l.654-2.64c.744.18 3.137.524 2.75 2.084v.006z",
    "litecoin": "M12 0a12 12 0 1012 12A12 12 0 0012 0zm-.2617 3.6777h2.584a.3425.3425 0 01.33.4356l-2.0312 6.918 1.9062-.582-.4082 1.3847-1.9238.5605-1.248 4.213h6.6757a.3425.3425 0 01.3282.4374l-.582 2a.4586.4586 0 01-.4395.3301H6.7324l1.7227-5.8223-1.9063.5801.42-1.3613 1.9101-.58 2.4219-8.1798a.4557.4557 0 01.4375-.334Z",
    "ethereum": "M11.944 17.97L4.58 13.62 11.943 24l7.37-10.38-7.372 4.35h.003zM12.056 0L4.69 12.223l7.365 4.354 7.365-4.35L12.056 0z",
    "solana": "M5.1 4h15.4l-3.6 3.6H1.5L5.1 4zm0 12.4h15.4L16.9 20H1.5l3.6-3.6zm13.8-6.2H3.5l3.6 3.6h15.4l-3.6-3.6z",
    "monero": "M12 0C5.365 0 0 5.373 0 12.015c0 1.335.228 2.607.618 3.81h3.577V5.729L12 13.545l7.805-7.815v10.095h3.577c.389-1.203.618-2.475.618-3.81C24 5.375 18.635 0 12 0zm-1.788 15.307l-3.417-3.421v6.351H1.758C3.87 21.689 7.678 24 12 24s8.162-2.311 10.245-5.764h-5.04v-6.351l-3.386 3.421-1.788 1.79-1.814-1.79h-.005z",
}

# Every (icon, CSS size) the QML asks for; Icon.qml turns the size into pixels
# the same way.
SIZES = {
    "close": [15, 18, 21],
    "clock": [18],
    "stopwatch": [18, 21],
    "settings": [21],
    "info": [21],
    "check": [16, 21],
    "chevron": [16],
    "arrow-left": [20],
    "arrow-right": [20],
    "bookmark": [20],
    "bookmark-filled": [20],
    "strike-a": [20],
    "minus-circle": [21],
    "falcon": [26, 38, 84],
    **{name: [17] for name in GLYPH},
}


def svg_for(name: str) -> str:
    if name == "falcon":
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="#000">{FALCON}</svg>'
    if name in GLYPH:
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000"><path d="{GLYPH[name]}"/></svg>'
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" '
            f'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">{STROKE[name]}</svg>')


def render(svg: str, px: int, path: Path, background=None) -> None:
    from PySide6.QtCore import QByteArray, QRectF, Qt
    from PySide6.QtGui import QColor, QImage, QPainter
    from PySide6.QtSvg import QSvgRenderer

    img = QImage(px, px, QImage.Format_ARGB32)
    img.fill(QColor(background) if background else Qt.transparent)
    painter = QPainter(img)
    painter.setRenderHint(QPainter.Antialiasing)
    QSvgRenderer(QByteArray(svg.encode())).render(painter, QRectF(0, 0, px, px))
    painter.end()
    img.save(str(path))


def images() -> None:
    from PySide6.QtGui import QGuiApplication

    _app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    out = UI / "images"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    for name, sizes in SIZES.items():
        for css in sizes:
            pixels = px(css)
            render(svg_for(name), pixels, out / f"{name}-{pixels}.png")
    # Launcher icon: the falcon on white, as AppLoad shows it in its list.
    falcon = svg_for("falcon").replace('viewBox="0 0 512 512"', 'viewBox="-64 -64 640 640"')
    render(falcon, 128, ROOT / "app" / "icon.png", background="#ffffff")
    print(f"  {len(list(out.glob('*.png')))} icons, app/icon.png")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", type=Path, default=ROOT.parent / "demon")
    args = ap.parse_args()
    fonts(args.source)
    images()
    return 0


if __name__ == "__main__":
    sys.exit(main())
