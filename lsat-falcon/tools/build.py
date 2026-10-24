"""Builds the download that gets unpacked on the tablet.

    python tools/build.py [--source deck]

Needs Qt's `rcc` (PySide6 ships one; or set RCC=/path/to/rcc) and Go 1.21+.
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
PKG = DIST / "lsat-falcon"
DATA = ROOT / "build" / "data"
EXECUTABLE = {"install.sh", "uninstall.sh", "app/backend/entry-armv7", "app/backend/entry-aarch64"}
UI_SUFFIXES = {".qml", ".js", ".png", ".ttf"}


def write_qrc() -> Path:
    """application.qrc lists everything under app/ui, so it can't go stale."""
    files = sorted(p.relative_to(APP).as_posix() for p in (APP / "ui").rglob("*")
                   if p.is_file() and (p.suffix in UI_SUFFIXES or p.name == "qmldir"))
    qrc = APP / "application.qrc"
    qrc.write_text("<RCC>\n    <qresource>\n" + "".join(f"        <file>{f}</file>\n" for f in files)
                   + "    </qresource>\n</RCC>\n", encoding="utf-8")
    return qrc


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
    for name in ("/usr/lib/qt6/libexec/rcc", "/usr/lib/qt6/bin/rcc", "/usr/lib/qt6/rcc", "/usr/lib64/qt6/libexec/rcc",
                 "rcc-qt6", "rcc"):
        found = shutil.which(name) or (name if Path(name).exists() else None)
        if found:
            return found
    sys.exit("Cannot find Qt's rcc. Install PySide6 (pip install PySide6) or set RCC=/path/to/rcc.")


def build_rcc(out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([find_rcc(), "--binary", "-o", str(out), str(write_qrc())], check=True)


def build_data(source: Path) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "build_data.py"), "--source", str(source),
                    "--out", str(DATA)], check=True)


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
    for name, title in (("OFL-Roboto.txt", "Roboto (as Falcon Roboto)"),
                        ("OFL-NotoSansMath.txt", "Noto Sans Math (arrows, ≠ and ✓ in Falcon Roboto)")):
        path = APP / "ui" / "fonts" / name
        if path.exists():
            parts.append(f"==== {title} ====\n\n{path.read_text(encoding='utf-8').strip()}\n")
    return "\n\n".join(parts).encode("utf-8")


def unix_text(path: Path) -> bytes:
    # Runs or is read on the tablet: Unix line endings.
    return path.read_bytes().replace(bytes([13, 10]), bytes([10]))


def archives() -> None:
    files = sorted(f for f in PKG.rglob("*") if f.is_file())
    stamp = time.time()
    with zipfile.ZipFile(DIST / "lsat-falcon.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            rel = f.relative_to(PKG).as_posix()
            info = zipfile.ZipInfo(f"lsat-falcon/{rel}", time.localtime(stamp)[:6])
            info.create_system = 3  # Unix, so unzip applies the permissions below
            info.external_attr = ((0o100755 if rel in EXECUTABLE else 0o100644) << 16)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, f.read_bytes())
    with tarfile.open(DIST / "lsat-falcon.tar.gz", "w:gz") as t:
        for f in files:
            rel = f.relative_to(PKG).as_posix()
            data = f.read_bytes()
            info = tarfile.TarInfo(f"lsat-falcon/{rel}")
            info.size = len(data)
            info.mtime = int(stamp)
            info.mode = 0o755 if rel in EXECUTABLE else 0o644
            info.uname = info.gname = "root"
            t.addfile(info, io.BytesIO(data))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", type=Path, default=ROOT / "deck",
                    help="deck/ (the default), or a web app checkout such as ../demon")
    args = ap.parse_args()

    build_data(args.source)
    if DIST.exists():
        shutil.rmtree(DIST)
    (PKG / "app" / "backend").mkdir(parents=True)

    for script in ("install.sh", "uninstall.sh", "README.txt"):
        (PKG / script).write_bytes(unix_text(ROOT / "package" / script))
    shutil.copy(APP / "manifest.json", PKG / "app")
    shutil.copy(APP / "icon.png", PKG / "app")
    (PKG / "app" / "FONTS-LICENSE.txt").write_bytes(fonts_license())
    shutil.copytree(DATA, PKG / "app" / "data")
    build_rcc(PKG / "app" / "resources.rcc")
    build_backend("arm", PKG / "app" / "backend" / "entry-armv7", goarm="7")
    build_backend("arm64", PKG / "app" / "backend" / "entry-aarch64")
    archives()

    print(f"Built {DIST.relative_to(ROOT)}:")
    for f in sorted(DIST.rglob("*")):
        if f.is_file():
            print(f"  {f.relative_to(DIST).as_posix():48} {f.stat().st_size:>12,} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
