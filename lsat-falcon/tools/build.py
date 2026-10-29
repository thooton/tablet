"""Builds the download that gets unpacked on the tablet.

    python tools/build.py [--source deck]

Needs Qt 6's rcc (PySide6 ships one; or set RCC=/path/to/rcc) and Go 1.21+.
The deck comes from deck/ (see tools/build_data.py).
Output, all for /home/root/lsat-falcon on the tablet:
    dist/lsat-falcon/install.sh, uninstall.sh, README.txt
    dist/lsat-falcon/app/manifest.json, icon.png, resources.rcc, FONTS-LICENSE.txt
    dist/lsat-falcon/app/data/meta.json, content.dat, content.idx
    dist/lsat-falcon/app/backend/entry-armv7    (reMarkable 1 / 2)
    dist/lsat-falcon/app/backend/entry-aarch64  (reMarkable Paper Pro / Move)
    dist/lsat-falcon.zip, dist/lsat-falcon.tar.gz  (the same folder)
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "tools"))
import appbuild  # noqa: E402

APP = ROOT / "app"
DATA = ROOT / "build" / "data"
UI_SUFFIXES = {".qml", ".js", ".png", ".ttf"}


def write_qrc() -> Path:
    """application.qrc lists everything under app/ui, so it can't go stale."""
    files = sorted(p.relative_to(APP).as_posix() for p in (APP / "ui").rglob("*")
                   if p.is_file() and (p.suffix in UI_SUFFIXES or p.name == "qmldir"))
    qrc = APP / "application.qrc"
    qrc.write_text("<RCC>\n    <qresource>\n" + "".join(f"        <file>{f}</file>\n" for f in files)
                   + "    </qresource>\n</RCC>\n", encoding="utf-8")
    return qrc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", type=Path, default=ROOT / "deck",
                    help="deck/ (the default), or a web app checkout such as ../demon")
    args = ap.parse_args()

    subprocess.run([sys.executable, str(ROOT / "tools" / "build_data.py"), "--source", str(args.source),
                    "--out", str(DATA)], check=True)
    license = appbuild.fonts_license([
        (APP / "ui" / "fonts" / "OFL-Roboto.txt", "Roboto (as Falcon Roboto)"),
        (APP / "ui" / "fonts" / "OFL-NotoSansMath.txt", "Noto Sans Math (arrows, ≠ and ✓ in Falcon Roboto)")])
    appbuild.build_app(ROOT, license, qrc=write_qrc(), zip=True,
                       extra=lambda pkg: shutil.copytree(DATA, pkg / "app" / "data"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
