#!/usr/bin/env bash
# Runs the app in the desktop emulator (creates a Python venv with PySide6 on
# first use). Extra arguments go to emulator.py, e.g. --fresh or --test.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="${LSAT_FALCON_VENV:-$HOME/.cache/lsat-falcon-venv}"

if [ ! -x "$VENV/bin/python" ] && [ ! -x "$VENV/Scripts/python.exe" ]; then
    echo "Creating Python environment in $VENV (one time) ..."
    python3 -m venv "$VENV"
    PY="$VENV/bin/python"; [ -x "$PY" ] || PY="$VENV/Scripts/python.exe"
    "$PY" -m pip install --quiet "PySide6>=6.5" fonttools brotli
fi
PY="$VENV/bin/python"; [ -x "$PY" ] || PY="$VENV/Scripts/python.exe"

if [ "${1:-}" = "--test" ]; then
    shift
    exec "$PY" "$HERE/test_app.py" "$@"
fi
exec "$PY" "$HERE/emulator.py" "$@"
