#!/bin/sh
# Installs Spanish Reader into AppLoad. Runs on the reMarkable itself:
#
#     sh /home/root/spanish-stories/install.sh
#
# Copies app/ from this folder into AppLoad's app folder, keeping the backend
# binary that matches this tablet's CPU, and points the app at this folder's
# stories/ - add or remove .json files there any time. Running it again
# updates the app; reading progress is kept.
set -e
PKG="$(cd "$(dirname "$0")" && pwd)"
# The overrides exist only for emulator/device_test.sh.
APPLOAD="${SPANISH_READER_APPLOAD:-/home/root/xovi/exthome/appload}"
MACHINE="${SPANISH_READER_MACHINE:-$(uname -m)}"
DIR="$APPLOAD/spanish-reader"

if [ ! -d "$APPLOAD" ]; then
    cat <<EOF
AppLoad is not installed on this tablet ($APPLOAD is missing).

Spanish Reader runs inside AppLoad, which runs on xovi. Install them first:
  1. xovi:    https://github.com/asivery/xovi  (guide: https://xovi.bearblog.dev/appload/)
  2. AppLoad: https://github.com/asivery/rm-appload
Then run this script again.
EOF
    exit 3
fi

case "$MACHINE" in
    armv7*) ARCH=armv7 ;;     # reMarkable 1 and 2
    aarch64) ARCH=aarch64 ;;  # reMarkable Paper Pro and Paper Pro Move
    *) echo "Unsupported CPU: $MACHINE"; exit 4 ;;
esac
for f in manifest.json icon.png resources.rcc "backend/entry-$ARCH"; do
    if [ ! -f "$PKG/app/$f" ]; then
        echo "$PKG/app/$f is missing. Unpack the whole spanish-stories download again."
        exit 5
    fi
done

# Build the new version next to the old one, then swap.
rm -rf "$DIR.new"
mkdir -p "$DIR.new/backend" "$PKG/stories"
cp "$PKG/app/manifest.json" "$PKG/app/icon.png" "$PKG/app/resources.rcc" "$DIR.new/"
[ -f "$PKG/app/FONTS-LICENSE.txt" ] && cp "$PKG/app/FONTS-LICENSE.txt" "$DIR.new/"
cp "$PKG/app/backend/entry-$ARCH" "$DIR.new/backend/entry"
chmod 755 "$DIR.new/backend/entry"
ln -s "$PKG/stories" "$DIR.new/stories"
rm -rf "$DIR"
mv "$DIR.new" "$DIR"
chmod 755 "$PKG/install.sh" "$PKG/uninstall.sh" 2>/dev/null || true

COUNT=$(ls "$PKG/stories" | grep -c '\.json$' || true)
echo "Installed Spanish Reader ($ARCH, $COUNT stories in $PKG/stories)."
echo "Open AppLoad and tap Reload (or restart the tablet) to see it."
