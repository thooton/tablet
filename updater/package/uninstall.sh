#!/bin/sh
# Removes the Updater from AppLoad. Runs on the reMarkable itself:
#
#     sh /home/root/updater/uninstall.sh
#
# The apps it installed stay. This folder stays too; delete it yourself with
#     rm -r /home/root/updater
APPLOAD="${APPLOAD_DIR:-/home/root/xovi/exthome/appload}"
DIR="$APPLOAD/updater"

if [ -e "$DIR" ] || [ -L "$DIR" ]; then
    rm -rf "$DIR" "$DIR.new"
    echo "Removed the Updater from AppLoad. Tap Reload in AppLoad (or restart the tablet)."
else
    echo "The Updater is not installed in $APPLOAD."
fi
rm -f /tmp/updater.sock
rm -rf /home/root/.cache/updater
