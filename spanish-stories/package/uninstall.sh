#!/bin/sh
# Removes Spanish Reader from AppLoad. Runs on the reMarkable itself:
#
#     sh /home/root/spanish-stories/uninstall.sh          # keep reading progress
#     sh /home/root/spanish-stories/uninstall.sh --purge  # forget it too
#
# This folder (the stories and these scripts) stays; delete it yourself with
#     rm -r /home/root/spanish-stories
# if you want everything gone.
PKG="$(cd "$(dirname "$0")" && pwd)"
# The overrides exist only for emulator/device_test.sh.
APPLOAD="${SPANISH_READER_APPLOAD:-/home/root/xovi/exthome/appload}"
DATA="${SPANISH_READER_HOME:-$HOME}/.local/share/spanish-reader"
DIR="$APPLOAD/spanish-reader"

if [ -e "$DIR" ] || [ -L "$DIR" ]; then
    rm -rf "$DIR" "$DIR.new"
    echo "Removed the app from AppLoad. Tap Reload in AppLoad (or restart the tablet)."
else
    echo "Spanish Reader is not installed in $APPLOAD."
fi
rm -f /tmp/spanish-reader.sock

if [ "$1" = "--purge" ]; then
    rm -rf "$DATA"
    echo "Removed reading progress and settings ($DATA)."
elif [ -d "$DATA" ]; then
    echo "Reading progress kept in $DATA (run with --purge to remove it)."
fi
echo "Your stories are still in $PKG/stories."
