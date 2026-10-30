"""What every app's tools/build.py shares: Qt's rcc, the Go backend for both
tablet CPUs, and the release archive.

    sys.path.insert(0, str(ROOT.parent / "tools"))
    import appbuild
    appbuild.build_app(ROOT, [("OFL-IBMPlex.txt", None)])

build_app writes the app's package folder, dist/<dir>/, as it should land
in /home/root/<dir> on the tablet, and packs it into dist/<dir>.tar.gz, the
file CI publishes and the Updater installs (see AGENTS.md at the
repository root).
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

TOOLS = Path(__file__).resolve().parent

# The tablets' CPUs, as install.sh names them after `uname -m`.
ARCHES = {"armv7": ("arm", "7"), "aarch64": ("arm64", "")}


def find_rcc() -> str:
    """Qt 6's rcc: $RCC, PySide6's, or the system's."""
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
    # Before a bare "rcc", which on many systems is Qt 5's.
    for name in ("/usr/lib/qt6/libexec/rcc", "/usr/lib/qt6/bin/rcc", "/usr/lib/qt6/rcc", "/usr/lib64/qt6/libexec/rcc",
                 "rcc-qt6", "rcc"):
        found = shutil.which(name) or (name if Path(name).exists() else None)
        if found:
            return found
    sys.exit("Cannot find Qt 6's rcc. Install PySide6 (pip install PySide6) or set RCC=/path/to/rcc.")


def build_rcc(qrc: Path, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([find_rcc(), "--binary", "-o", str(out), str(qrc)], check=True)


def build_backend(src: Path, out_dir: Path) -> list:
    """Builds backend/entry-<arch> for each tablet CPU; returns their names."""
    out_dir.mkdir(parents=True, exist_ok=True)
    names = []
    for arch, (goarch, goarm) in ARCHES.items():
        env = dict(os.environ, GOOS="linux", GOARCH=goarch, CGO_ENABLED="0")
        if goarm:
            env["GOARM"] = goarm
        name = f"entry-{arch}"
        subprocess.run(["go", "build", "-trimpath", "-ldflags=-s -w", "-o", str(out_dir / name), "."],
                       cwd=src, env=env, check=True)
        names.append(name)
    return names


def unix_text(path: Path) -> bytes:
    """A script or text file for the tablet, with Unix line endings."""
    return path.read_bytes().replace(b"\r\n", b"\n")


def archive(pkg: Path, executable=(), zip_too=False) -> Path:
    """Packs pkg (dist/<dir>/) into dist/<dir>.tar.gz (and with zip_too
    dist/<dir>.zip), every path under <dir>/, owned by root. Paths in
    executable (relative to pkg, and every .sh) get mode 755."""
    name = pkg.name
    out = pkg.parent / f"{name}.tar.gz"
    stamp = int(time.time())
    files = [(f.relative_to(pkg).as_posix(), f.read_bytes()) for f in sorted(p for p in pkg.rglob("*") if p.is_file())]
    mode = lambda rel: 0o755 if rel in executable or rel.endswith(".sh") else 0o644
    with tarfile.open(out, "w:gz") as t:
        for rel, data in files:
            info = tarfile.TarInfo(f"{name}/{rel}")
            info.size = len(data)
            info.mtime = stamp
            info.mode = mode(rel)
            info.uname = info.gname = "root"
            t.addfile(info, io.BytesIO(data))
    if zip_too:
        with zipfile.ZipFile(pkg.parent / f"{name}.zip", "w", zipfile.ZIP_DEFLATED) as z:
            for rel, data in files:
                info = zipfile.ZipInfo(f"{name}/{rel}", time.localtime(stamp)[:6])
                info.create_system = 3  # Unix, so unzip applies the permissions below
                info.external_attr = (0o100000 | mode(rel)) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, data)
    return out


def fonts_license(fonts: Path, licenses) -> bytes:
    """FONTS-LICENSE.txt from licenses, (file in fonts or tools/fonts, title)
    pairs: one with no title as it is, else each under a ==== title ====
    heading."""
    find = lambda name: fonts / name if (fonts / name).exists() else TOOLS / "fonts" / name
    if len(licenses) == 1 and licenses[0][1] is None:
        return unix_text(find(licenses[0][0]))
    parts = [f"==== {title} ====\n\n{find(name).read_text(encoding='utf-8').strip()}\n" for name, title in licenses]
    return "\n\n".join(parts).encode("utf-8")


def build_app(root: Path, licenses, extra=None, zip_too=False) -> int:
    """Builds root/dist/<dir>/ and its archive: package/'s scripts, app/'s
    manifest and icon, the fonts' licenses (see fonts_license), the QML as
    resources.rcc, and the backend for each CPU if app/backend has one.
    extra(pkg), if given, adds the app's own files before packing."""
    app, dist = root / "app", root / "dist"
    pkg = dist / root.name
    if dist.exists():
        shutil.rmtree(dist)
    (pkg / "app").mkdir(parents=True)
    for script in ("install.sh", "uninstall.sh", "README.txt"):
        (pkg / script).write_bytes(unix_text(root / "package" / script))
    shutil.copy(app / "manifest.json", pkg / "app")
    shutil.copy(app / "icon.png", pkg / "app")
    (pkg / "app" / "FONTS-LICENSE.txt").write_bytes(fonts_license(app / "ui" / "fonts", licenses))
    build_rcc(app / "application.qrc", pkg / "app" / "resources.rcc")
    names = build_backend(root / "backend", pkg / "app" / "backend")
    if extra:
        extra(pkg)
    archive(pkg, executable={f"app/backend/{n}" for n in names}, zip_too=zip_too)
    report(dist)
    return 0


def report(dist: Path) -> None:
    print(f"Built {dist}:")
    for f in sorted(dist.rglob("*")):
        if f.is_file():
            print(f"  {f.relative_to(dist).as_posix():48} {f.stat().st_size:>12,} bytes")
