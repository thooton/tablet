"""Builds the Updater's download, the folder that lands in /home/root/updater.

    python tools/build.py

Needs Qt 6's rcc (PySide6 ships one; or set RCC=/path/to/rcc) and Go 1.21+.
Output:
    dist/updater/install.sh, uninstall.sh, README.txt
    dist/updater/app/manifest.json, icon.png, resources.rcc, FONTS-LICENSE.txt
    dist/updater/app/backend/entry-armv7    (reMarkable 1 / 2)
    dist/updater/app/backend/entry-aarch64  (reMarkable Paper Pro / Move)
    dist/updater.tar.gz                     (the same folder)
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "tools"))
import appbuild  # noqa: E402

APP = ROOT / "app"
DIST = ROOT / "dist"
PKG = DIST / "updater"


def main() -> int:
    if DIST.exists():
        shutil.rmtree(DIST)
    (PKG / "app").mkdir(parents=True)
    for script in ("install.sh", "uninstall.sh", "README.txt"):
        (PKG / script).write_bytes(appbuild.unix_text(ROOT / "package" / script))
    shutil.copy(APP / "manifest.json", PKG / "app")
    shutil.copy(APP / "icon.png", PKG / "app")
    (PKG / "app" / "FONTS-LICENSE.txt").write_bytes(appbuild.unix_text(APP / "ui" / "fonts" / "OFL-IBMPlex.txt"))
    appbuild.build_rcc(APP / "application.qrc", PKG / "app" / "resources.rcc")
    names = appbuild.build_backend(ROOT / "backend", PKG / "app" / "backend")
    appbuild.archive(PKG, executable={f"app/backend/{n}" for n in names})
    appbuild.report(DIST)
    return 0


if __name__ == "__main__":
    sys.exit(main())
