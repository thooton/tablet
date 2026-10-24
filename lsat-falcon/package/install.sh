#!/bin/sh
# Installs LSAT Falcon into AppLoad. Runs on the reMarkable itself:
#
#     sh /home/root/lsat-falcon/install.sh
#
# Copies app/ from this folder into AppLoad's app folder, keeping the backend
# binary that matches this tablet's CPU. Running it again updates the app;
# your settings and place are kept.
set -e
PKG="$(cd "$(dirname "$0")" && pwd)"
# APPLOAD_DIR is set by the Updater; the LSAT_FALCON_ overrides exist only
# for testing off the tablet.
APPLOAD="${LSAT_FALCON_APPLOAD:-${APPLOAD_DIR:-/home/root/xovi/exthome/appload}}"
MACHINE="${LSAT_FALCON_MACHINE:-$(uname -m)}"
DIR="$APPLOAD/lsat-falcon"

if [ ! -d "$APPLOAD" ]; then
    cat <<MSG
AppLoad is not installed on this tablet ($APPLOAD is missing).

LSAT Falcon runs inside AppLoad, which runs on xovi. Install them first:
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
for f in manifest.json icon.png resources.rcc "backend/entry-$ARCH" data/meta.json data/content.dat data/content.idx; do
    if [ ! -f "$PKG/app/$f" ]; then
        echo "$PKG/app/$f is missing. Unpack the whole lsat-falcon download again."
        exit 5
    fi
done

# Build the new version next to the old one, then swap.
rm -rf "$DIR.new"
mkdir -p "$DIR.new/backend" "$DIR.new/data"
cp "$PKG/app/manifest.json" "$PKG/app/icon.png" "$PKG/app/resources.rcc" "$DIR.new/"
[ -f "$PKG/app/FONTS-LICENSE.txt" ] && cp "$PKG/app/FONTS-LICENSE.txt" "$DIR.new/"
cp "$PKG/app/data/meta.json" "$PKG/app/data/content.dat" "$PKG/app/data/content.idx" "$DIR.new/data/"
cp "$PKG/app/backend/entry-$ARCH" "$DIR.new/backend/entry"
chmod 755 "$DIR.new/backend/entry"
rm -rf "$DIR"
mv "$DIR.new" "$DIR"
chmod 755 "$PKG/install.sh" "$PKG/uninstall.sh" 2>/dev/null || true

echo "Installed LSAT Falcon ($ARCH) in $DIR."
echo "Open AppLoad and tap Reload (or restart the tablet) to see it."
