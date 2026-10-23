"""Builds the download that gets unpacked on the tablet.

    python tools/build.py

Needs Qt's `rcc` (PySide6 ships one; or set RCC=/path/to/rcc) and Go 1.21+.
Output, all for /home/root/spanish-stories on the tablet:
    dist/spanish-stories/install.sh, uninstall.sh, README.txt
    dist/spanish-stories/stories/*.json
    dist/spanish-stories/app/manifest.json, icon.png, resources.rcc, FONTS-LICENSE.txt
    dist/spanish-stories/app/backend/entry-armv7    (reMarkable 1 / 2)
    dist/spanish-stories/app/backend/entry-aarch64  (reMarkable Paper Pro / Move)
    dist/spanish-stories.zip, dist/spanish-stories.tar.gz  (the same folder)
"""
import io
import os
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
DIST = ROOT / "dist"
PKG = DIST / "spanish-stories"
EXECUTABLE = {"install.sh", "uninstall.sh", "app/backend/entry-armv7", "app/backend/entry-aarch64"}


def find_rcc() -> str:
    if os.environ.get("RCC"):
        return os.environ["RCC"]
    try:
        import PySide6  # noqa: F401

        exe = "rcc.exe" if os.name == "nt" else "rcc"
        for candidate in (Path(PySide6.__file__).parent / exe, Path(PySide6.__file__).parent / "Qt" / "libexec" / exe):
            if candidate.exists():
                return str(candidate)
    except ImportError:
        pass
    for name in ("rcc", "rcc-qt6", "/usr/lib/qt6/libexec/rcc", "/usr/lib/qt6/bin/rcc", "/usr/lib64/qt6/libexec/rcc"):
        found = shutil.which(name) or (name if Path(name).exists() else None)
        if found:
            return found
    sys.exit("Cannot find Qt's rcc. Install PySide6 (pip install PySide6) or set RCC=/path/to/rcc.")


def build_rcc(out: Path) -> None:
    rcc = find_rcc()
    subprocess.run([rcc, "--binary", "-o", str(out), str(APP / "application.qrc")], check=True)


def build_backend(goarch: str, out: Path, goarm: str = "") -> None:
    env = dict(os.environ, GOOS="linux", GOARCH=goarch, CGO_ENABLED="0")
    if goarm:
        env["GOARM"] = goarm
    subprocess.run(
        ["go", "build", "-trimpath", "-ldflags=-s -w", "-o", str(out), "."],
        cwd=ROOT / "backend", env=env, check=True,
    )


def fonts_license() -> bytes:
    parts = []
    for name, title in (("OFL-NotoSerif.txt", "Noto Serif"), ("OFL-IBMPlex.txt", "IBM Plex Sans"),
                        ("OFL-Atkinson.txt", "Atkinson Hyperlegible")):
        text = (APP / "ui" / "fonts" / name).read_text(encoding="utf-8")  # universal newlines
        parts.append(f"==== {title} ====\n\n{text.strip()}\n")
    return "\n\n".join(parts).encode("utf-8")


def unix_text(path: Path) -> bytes:
    # Runs or is read on the tablet: Unix line endings.
    return path.read_bytes().replace(bytes([13, 10]), bytes([10]))


def archives() -> None:
    files = sorted(f for f in PKG.rglob("*") if f.is_file())
    stamp = time.time()
    with zipfile.ZipFile(DIST / "spanish-stories.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            rel = f.relative_to(PKG).as_posix()
            info = zipfile.ZipInfo(f"spanish-stories/{rel}", time.localtime(stamp)[:6])
            info.create_system = 3  # Unix, so unzip applies the permissions below
            info.external_attr = ((0o100755 if rel in EXECUTABLE else 0o100644) << 16)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, f.read_bytes())
    with tarfile.open(DIST / "spanish-stories.tar.gz", "w:gz") as t:
        for f in files:
            rel = f.relative_to(PKG).as_posix()
            data = f.read_bytes()
            info = tarfile.TarInfo(f"spanish-stories/{rel}")
            info.size = len(data)
            info.mtime = int(stamp)
            info.mode = 0o755 if rel in EXECUTABLE else 0o644
            info.uname = info.gname = "root"
            t.addfile(info, io.BytesIO(data))


def main() -> int:
    validate = subprocess.run([sys.executable, str(ROOT / "tools" / "validate_stories.py"), "--quiet"])
    if validate.returncode != 0:
        return validate.returncode

    if DIST.exists():
        shutil.rmtree(DIST)
    (PKG / "app" / "backend").mkdir(parents=True)
    (PKG / "stories").mkdir()

    for script in ("install.sh", "uninstall.sh", "README.txt"):
        (PKG / script).write_bytes(unix_text(ROOT / "package" / script))
    shutil.copy(APP / "manifest.json", PKG / "app")
    shutil.copy(APP / "icon.png", PKG / "app")
    (PKG / "app" / "FONTS-LICENSE.txt").write_bytes(fonts_license())
    build_rcc(PKG / "app" / "resources.rcc")
    build_backend("arm", PKG / "app" / "backend" / "entry-armv7", goarm="7")
    build_backend("arm64", PKG / "app" / "backend" / "entry-aarch64")
    for story in sorted((ROOT / "stories").glob("*.json")):
        (PKG / "stories" / story.name).write_bytes(unix_text(story))
    archives()

    print(f"Built {DIST.relative_to(ROOT)}:")
    for f in sorted(DIST.rglob("*")):
        if f.is_file():
            print(f"  {f.relative_to(DIST).as_posix():48} {f.stat().st_size:>10,} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
