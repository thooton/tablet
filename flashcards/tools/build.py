"""Builds Flashcards' download, the folder that lands in /home/root/flashcards.

    python tools/build.py

Needs Qt 6's rcc (PySide6 ships one; or set RCC=/path/to/rcc) and Go 1.21+.
Output:
    dist/flashcards/install.sh, uninstall.sh, README.txt
    dist/flashcards/app/manifest.json, icon.png, resources.rcc, FONTS-LICENSE.txt
    dist/flashcards/app/backend/entry-armv7    (reMarkable 1 / 2)
    dist/flashcards/app/backend/entry-aarch64  (reMarkable Paper Pro / Move)
    dist/flashcards.tar.gz                     (the same folder)
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "tools"))
import appbuild  # noqa: E402

if __name__ == "__main__":
    sys.exit(appbuild.build_app(ROOT, [("OFL-IBMPlex.txt", None)]))
