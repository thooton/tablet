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
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "tools"))
import appbuild  # noqa: E402

if __name__ == "__main__":
    sys.exit(appbuild.build_app(ROOT, [("OFL-IBMPlex.txt", None)]))
