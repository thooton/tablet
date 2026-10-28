"""Drives an app running in tools/emulator.py --control PORT, one command
at a time, and prints the emulator's answer.

    python3 tools/emulator.py <app dir> --offscreen --control 47011 > /tmp/emulator.log 2>&1 &
    python3 tools/drive.py tap 700 400
    python3 tools/drive.py swipe 700 1500 700 400 [ms]
    python3 tools/drive.py type "hola"
    python3 tools/drive.py key Return
    python3 tools/drive.py shot shot.png
    python3 tools/drive.py quit

--port picks another port (default 47011, or $EMULATOR_PORT). Exits 1 if
the emulator answers with an error or isn't running.
"""
import os
import socket
import sys
import time


def main(argv) -> int:
    port = int(os.environ.get("EMULATOR_PORT", "47011"))
    if len(argv) >= 2 and argv[0] == "--port":
        port, argv = int(argv[1]), argv[2:]
    if not argv:
        print(__doc__.strip())
        return 2
    line = argv[0] + (" " + " ".join(argv[1:]) if len(argv) > 1 else "")
    if argv[0] == "shot" and len(argv) > 1:
        line = "shot " + os.path.abspath(argv[1])
    # The emulator takes a few seconds to start: wait for it.
    deadline = time.time() + 60
    while True:
        try:
            conn = socket.create_connection(("127.0.0.1", port), timeout=5)
            break
        except OSError:
            if time.time() > deadline:
                print(f"error nothing is listening on port {port}: start tools/emulator.py with --control {port}")
                return 1
            time.sleep(1)
    with conn:
        conn.settimeout(60)
        conn.sendall((line.replace("\n", " ") + "\n").encode())
        answer = b""
        while not answer.endswith(b"\n"):
            chunk = conn.recv(4096)
            if not chunk:
                break
            answer += chunk
    answer = answer.decode().strip()
    print(answer)
    return 0 if answer.startswith("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
