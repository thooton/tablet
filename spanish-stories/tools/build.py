"""Builds the download that gets unpacked on the tablet.

    python tools/build.py

Needs Qt 6's rcc (PySide6 ships one; or set RCC=/path/to/rcc) and Go 1.21+.
Output, all for /home/root/spanish-stories on the tablet:
    dist/spanish-stories/install.sh, uninstall.sh, README.txt
    dist/spanish-stories/stories/*.json
    dist/spanish-stories/app/manifest.json, icon.png, resources.rcc, FONTS-LICENSE.txt
    dist/spanish-stories/app/backend/entry-armv7    (reMarkable 1 / 2)
    dist/spanish-stories/app/backend/entry-aarch64  (reMarkable Paper Pro / Move)
    dist/spanish-stories.zip, dist/spanish-stories.tar.gz  (the same folder)
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "tools"))
import appbuild  # noqa: E402


def stories(pkg: Path) -> None:
    (pkg / "stories").mkdir()
    for story in sorted((ROOT / "stories").glob("*.json")):
        (pkg / "stories" / story.name).write_bytes(appbuild.unix_text(story))


def main() -> int:
    validate = subprocess.run([sys.executable, str(ROOT / "tools" / "validate_stories.py"), "--quiet"])
    if validate.returncode != 0:
        return validate.returncode
    fonts = ROOT / "app" / "ui" / "fonts"
    license = appbuild.fonts_license([
        (fonts / "OFL-NotoSerif.txt", "Noto Serif"), (appbuild.FONTS / "OFL-IBMPlex.txt", "IBM Plex Sans"),
        (fonts / "OFL-Atkinson.txt", "Atkinson Hyperlegible")])
    appbuild.build_app(ROOT, license, extra=stories, zip=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
