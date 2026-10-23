"""Plays AppLoad's side of the backend protocol on Linux, exactly as the
tablet does it: an AF_UNIX SOCK_SEQPACKET server at /tmp/<id>.sock (here a
temp path), the backend started with the socket path as argv[1] and the app
directory as cwd, and every message sent as a header packet followed by a
body packet.

    python3 fake_appload.py APP_DIR DATA_DIR [launcher...]

`launcher` is put in front of backend/entry, e.g. a qemu-arm binary to run
the ARM build on a PC. Exits 0 when every check passes.
"""
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile


def main():
    app_dir, data_dir = sys.argv[1], sys.argv[2]
    launcher = sys.argv[3:]
    sock_path = os.path.join(tempfile.mkdtemp(), "spanish-reader.sock")

    server = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    server.bind(sock_path)
    server.listen(1)
    server.settimeout(60)

    env = dict(os.environ, SPANISH_READER_DATA=data_dir, HOME=data_dir)
    env.pop("SPANISH_READER_ROOT", None)  # must find its stories from its own location
    env.pop("SPANISH_READER_EXTRA_STORIES", None)
    proc = subprocess.Popen(launcher + [os.path.join(app_dir, "backend", "entry"), sock_path],
                            cwd=app_dir, env=env)
    conn, _ = server.accept()
    conn.settimeout(60)

    def send(msg_type, body):
        data = body.encode()
        conn.send(struct.pack("<ii", msg_type, len(data)))
        conn.send(data)

    def recv():
        header = conn.recv(8)
        msg_type, length = struct.unpack("<ii", header)
        body = conn.recv(max(length, 1)) if length else b""
        return msg_type, json.loads(body)

    passed = 0

    def check(cond, msg):
        nonlocal passed
        if not cond:
            print("FAILED:", msg)
            proc.kill()
            sys.exit(1)
        passed += 1
        print("  ok ", msg)

    send(-2, "1")  # AppLoad: a frontend is attached
    t, lib = recv()
    check(t == 101, "backend answers NEW_COORDINATOR with the library")
    check(len(lib["stories"]) >= 9 and not lib["errors"], f"{len(lib['stories'])} stories, no errors")
    first = lib["stories"][0]

    send(2, json.dumps({"id": first["id"]}))
    t, opened = recv()
    check(t == 102 and opened["story"]["tokens"], f"opens {first['title']!r} ({len(opened['story']['tokens'])} tokens)")
    big = max(lib["stories"], key=lambda s: s["tokens"])
    send(2, json.dumps({"id": big["id"]}))
    t, opened = recv()
    check(t == 102 and len(opened["story"]["tokens"]) == big["tokens"],
          f"largest story ({big['tokens']} tokens) arrives whole in one message")

    send(3, json.dumps({"id": first["id"], "token": 40, "finished": False}))
    send(1, "{}")
    t, lib = recv()
    s = next(s for s in lib["stories"] if s["id"] == first["id"])
    check(t == 101 and s["started"] and s["progress"] > 0, "reading progress is recorded")
    check(lib["stories"][0]["id"] == first["id"] and lib["stories"][1]["id"] == big["id"],
          "library lists the most recently read stories first")

    send(5, json.dumps({"textSize": 5, "dots": False}))
    t, settings = recv()
    check(t == 105 and settings["textSize"] == 5 and settings["dots"] is False and settings["font"] == "serif",
          "settings are stored")

    send(-1, "close")  # AppLoad's TERMINATE
    code = proc.wait(timeout=30)
    check(code == 0, "backend exits cleanly on TERMINATE")
    state = json.load(open(os.path.join(data_dir, "state.json")))
    check(state["stories"][first["id"]]["token"] == 40, "state.json saved")
    print(f"All {passed} backend checks passed.")


if __name__ == "__main__":
    main()
