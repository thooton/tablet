"""What every app's tools/build.py shares: Qt's rcc, the Go backend for both
tablet CPUs, and the release archive.

    sys.path.insert(0, str(ROOT.parent / "tools"))
    import appbuild

An app's build writes its package folder, dist/<dir>/, as it should land in
/home/root/<dir> on the tablet, then calls appbuild.archive() to make
dist/<dir>.tar.gz, the file CI publishes and the Updater installs (see
AGENTS.md at the repository root).
"""
import io
import os
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

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


def archive(pkg: Path, executable=()) -> Path:
    """Packs pkg (dist/<dir>/) into dist/<dir>.tar.gz, every path under
    <dir>/, owned by root. Paths in executable (relative to pkg, and every
    .sh) get mode 755."""
    name = pkg.name
    out = pkg.parent / f"{name}.tar.gz"
    stamp = int(time.time())
    with tarfile.open(out, "w:gz") as t:
        for f in sorted(p for p in pkg.rglob("*") if p.is_file()):
            rel = f.relative_to(pkg).as_posix()
            data = f.read_bytes()
            info = tarfile.TarInfo(f"{name}/{rel}")
            info.size = len(data)
            info.mtime = stamp
            info.mode = 0o755 if rel in executable or rel.endswith(".sh") else 0o644
            info.uname = info.gname = "root"
            t.addfile(info, io.BytesIO(data))
    return out


def report(dist: Path) -> None:
    print(f"Built {dist}:")
    for f in sorted(dist.rglob("*")):
        if f.is_file():
            print(f"  {f.relative_to(dist).as_posix():48} {f.stat().st_size:>10,} bytes")
