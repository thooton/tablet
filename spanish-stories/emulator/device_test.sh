#!/usr/bin/env bash
# Rehearses installing on a tablet, on a Linux PC (or WSL):
#   * dist/spanish-stories.zip and .tar.gz are unpacked into a fake
#     /home/root, and the install.sh / uninstall.sh inside them run as they
#     would on the tablet, told they run on a reMarkable 2 (armv7l) or a
#     Paper Pro (aarch64);
#   * the installed ARM backend is started by fake_appload.py under qemu
#     user-mode emulation, speaking AppLoad's SEQPACKET protocol.
#
#   python tools/build.py && emulator/device_test.sh [path/to/qemu-bin-dir]
#
# Needs python3, unzip and qemu-arm / qemu-aarch64 (package qemu-user or
# qemu-user-static). Set BUSYBOX=/path/to/busybox to unzip and run the
# scripts with busybox's unzip and sh, as on the tablet.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
QEMU_DIR="${1:-}"
qemu() { if [ -n "$QEMU_DIR" ]; then echo "$QEMU_DIR/$1"; else command -v "$1" || command -v "$1-static"; fi; }
BUSYBOX="${BUSYBOX:-}"
run_sh() { ${BUSYBOX:+$BUSYBOX} sh "$@"; }
unzip_() { ${BUSYBOX:+$BUSYBOX} unzip "$@"; }
ZIP="$ROOT/dist/spanish-stories.zip"
TGZ="$ROOT/dist/spanish-stories.tar.gz"
[ -f "$ZIP" ] && [ -f "$TGZ" ] || { echo "Run python tools/build.py first."; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAKE_HOME="$T/home/root"
PKG="$FAKE_HOME/spanish-stories"
mkdir -p "$FAKE_HOME/xovi/exthome/appload"
export SPANISH_READER_APPLOAD="$FAKE_HOME/xovi/exthome/appload"
export SPANISH_READER_HOME="$FAKE_HOME"
APP="$SPANISH_READER_APPLOAD/spanish-reader"
DATA="$FAKE_HOME/.local/share/spanish-reader"


pass() { echo "  ok  $*"; }
fail() { echo "FAILED: $*"; exit 1; }

for MACHINE in armv7l aarch64; do
    export SPANISH_READER_MACHINE=$MACHINE  # what `uname -m` says on the tablet
    echo "== $MACHINE =="
    if [ $MACHINE = armv7l ]; then
        (cd "$FAKE_HOME" && unzip_ -oq "$ZIP")
        pass "spanish-stories.zip unpacks to /home/root/spanish-stories"
    else
        (cd "$FAKE_HOME" && tar -xzf "$TGZ")
        pass "spanish-stories.tar.gz unpacks to /home/root/spanish-stories"
    fi
    for f in install.sh uninstall.sh README.txt app/resources.rcc stories; do
        [ -e "$PKG/$f" ] || fail "package is missing $f"
    done
    if grep -q "$(printf '\r')" "$PKG/install.sh" "$PKG/uninstall.sh"; then fail "scripts have CRLF line endings"; fi
    [ -x "$PKG/install.sh" ] && [ -x "$PKG/uninstall.sh" ] || fail "install.sh / uninstall.sh lost their exec bit"
    pass "install.sh and uninstall.sh are executable after unpacking"

    out="$(run_sh "$PKG/install.sh")" || fail "install.sh: $out"
    echo "$out" | grep -q "Installed Spanish Reader" || fail "install.sh said: $out"
    pass "install.sh: $(echo "$out" | head -1)"
    for f in manifest.json icon.png resources.rcc FONTS-LICENSE.txt backend/entry stories; do
        [ -e "$APP/$f" ] || fail "missing $f"
    done
    [ "$(ls "$APP/backend")" = "entry" ] || fail "leftover files in backend/: $(ls "$APP/backend")"
    [ -x "$APP/backend/entry" ] || fail "backend/entry is not executable"
    [ "$(readlink "$APP/stories")" = "$PKG/stories" ] || fail "stories is not a link to $PKG/stories"
    pass "app files in place, one backend binary, stories linked to the package folder"
    case $MACHINE in armv7l) Q=qemu-arm; want="ARM,";; aarch64) Q=qemu-aarch64; want="aarch64";; esac
    if command -v file >/dev/null; then
        file -L "$APP/backend/entry" | grep -q "$want" && pass "backend is the ${want%,} build" || fail "wrong backend: $(file -L "$APP/backend/entry")"
    fi
    python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m['id']=='spanish-reader' and m['loadsBackend']" "$APP/manifest.json" \
        && pass "manifest.json valid"

    echo "-- backend under $(basename "$(qemu $Q)") with fake AppLoad"
    python3 "$HERE/fake_appload.py" "$APP" "$DATA" "$(qemu $Q)" || fail "backend checks"

    # A story the user drops into the package folder shows up in the app.
    cp "$PKG/stories/01-el-gato-de-luna.json" "$PKG/stories/99-mine.json"
    [ -e "$APP/stories/99-mine.json" ] && pass "stories added to /home/root/spanish-stories/stories reach the app"
    rm "$PKG/stories/99-mine.json"

    out="$(run_sh "$PKG/install.sh")" || fail "reinstall: $out"
    [ -f "$DATA/state.json" ] && pass "running install.sh again keeps reading progress"

    out="$(run_sh "$PKG/uninstall.sh")" || fail "uninstall: $out"
    [ ! -e "$APP" ] && [ -f "$DATA/state.json" ] && pass "uninstall.sh removes the app, keeps progress"
    [ -d "$PKG/stories" ] && [ -f "$PKG/install.sh" ] && pass "package folder and stories kept"
    run_sh "$PKG/install.sh" >/dev/null
    out="$(run_sh "$PKG/uninstall.sh" --purge)" || fail "uninstall --purge: $out"
    [ ! -e "$APP" ] && [ ! -e "$DATA" ] && pass "uninstall.sh --purge also removes progress"
    rm -rf "$PKG"
done

echo "== tablet without AppLoad =="
(cd "$FAKE_HOME" && unzip_ -oq "$ZIP")
rm -rf "$SPANISH_READER_APPLOAD"
set +e
out="$(run_sh "$PKG/install.sh" 2>&1)"
code=$?
set -e
[ $code = 3 ] && echo "$out" | grep -q "xovi.bearblog.dev" && pass "explains how to install xovi + AppLoad (exit 3)" || fail "no-AppLoad case: $out"
echo "All device checks passed."
