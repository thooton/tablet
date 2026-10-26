#!/bin/sh
# Removes Flashcards from AppLoad. Runs on the reMarkable itself:
#
#     sh /home/root/flashcards/uninstall.sh [--purge]
#
# The cards stay in /home/root/.local/share/flashcards (and on the command
# center) unless --purge is given. This folder stays too; delete it yourself
# with
#     rm -r /home/root/flashcards
APPLOAD="${APPLOAD_DIR:-/home/root/xovi/exthome/appload}"
DIR="$APPLOAD/flashcards"

if [ -e "$DIR" ] || [ -L "$DIR" ]; then
    rm -rf "$DIR" "$DIR.new"
    echo "Removed Flashcards from AppLoad. Tap Reload in AppLoad (or restart the tablet)."
else
    echo "Flashcards is not installed in $APPLOAD."
fi
if [ "$1" = "--purge" ]; then
    rm -rf /home/root/.local/share/flashcards
    echo "Removed its cards and its pairing."
fi
