#!/bin/sh
# Installs the Updater into AppLoad. Runs on the reMarkable itself:
#
#     sh /home/root/updater/install.sh
#
# Copies app/ from this folder into AppLoad's app folder, keeping the backend
# binary that matches this tablet's CPU. Running it again updates the app;
# the Updater runs it itself when it updates itself.
set -e
PKG="$(cd "$(dirname "$0")" && pwd)"
APPLOAD="${APPLOAD_DIR:-/home/root/xovi/exthome/appload}"
MACHINE="${UPDATER_MACHINE:-$(uname -m)}"
DIR="$APPLOAD/updater"

if [ ! -d "$APPLOAD" ]; then
    cat <<MSG
AppLoad is not installed on this tablet ($APPLOAD is missing).

The Updater runs inside AppLoad, which runs on xovi. Install them first:
  1. xovi:    https://github.com/asivery/xovi  (guide: https://xovi.bearblog.dev/appload/)
  2. AppLoad: https://github.com/asivery/rm-appload
Then run this script again.
MSG
    exit 3
fi

case "$MACHINE" in
    armv7*) ARCH=armv7 ;;     # reMarkable 1 and 2
    aarch64) ARCH=aarch64 ;;  # reMarkable Paper Pro and Paper Pro Move
    *) echo "Unsupported CPU: $MACHINE"; exit 4 ;;
esac
for f in manifest.json icon.png resources.rcc "backend/entry-$ARCH"; do
    if [ ! -f "$PKG/app/$f" ]; then
        echo "$PKG/app/$f is missing. Unpack the whole updater download again."
        exit 5
    fi
done

# Build the new version next to the old one, then swap. A running backend
# keeps its old binary until it exits.
rm -rf "$DIR.new"
mkdir -p "$DIR.new/backend"
cp "$PKG/app/manifest.json" "$PKG/app/icon.png" "$PKG/app/resources.rcc" "$DIR.new/"
[ -f "$PKG/app/FONTS-LICENSE.txt" ] && cp "$PKG/app/FONTS-LICENSE.txt" "$DIR.new/"
cp "$PKG/app/backend/entry-$ARCH" "$DIR.new/backend/entry"
chmod 755 "$DIR.new/backend/entry"
rm -rf "$DIR"
mv "$DIR.new" "$DIR"
chmod 755 "$PKG/install.sh" "$PKG/uninstall.sh" 2>/dev/null || true

echo "Installed the Updater ($ARCH)."
echo "Open AppLoad and tap Reload (or restart the tablet) to see it."
