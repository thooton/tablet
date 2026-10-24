#!/bin/sh
# Removes LSAT Falcon from AppLoad. Runs on the reMarkable itself:
#
#     sh /home/root/lsat-falcon/uninstall.sh          # keep settings and place
#     sh /home/root/lsat-falcon/uninstall.sh --purge  # forget them too
#
# This folder stays; delete it yourself with  rm -r /home/root/lsat-falcon
APPLOAD="${LSAT_FALCON_APPLOAD:-${APPLOAD_DIR:-/home/root/xovi/exthome/appload}}"
DATA="${LSAT_FALCON_HOME:-$HOME}/.local/share/lsat-falcon"
DIR="$APPLOAD/lsat-falcon"

if [ -e "$DIR" ] || [ -L "$DIR" ]; then
    rm -rf "$DIR" "$DIR.new"
    echo "Removed the app from AppLoad. Tap Reload in AppLoad (or restart the tablet)."
else
    echo "LSAT Falcon is not installed in $APPLOAD."
fi
rm -f /tmp/lsat-falcon.sock

if [ "$1" = "--purge" ]; then
    rm -rf "$DATA"
    echo "Removed settings and position ($DATA)."
elif [ -d "$DATA" ]; then
    echo "Settings and position kept in $DATA (run with --purge to remove them)."
fi
