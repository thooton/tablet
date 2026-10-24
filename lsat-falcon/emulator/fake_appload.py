"""Plays AppLoad's side of the backend protocol on Linux, as the tablet does:
an AF_UNIX SOCK_SEQPACKET server, the backend started with the socket path as
argv[1] and the app directory as cwd, and every message sent as a header
packet followed by a body packet.

    python3 fake_appload.py APP_DIR DATA_DIR [launcher...]

`launcher` goes in front of backend/entry, e.g. qemu-arm to run the ARM build
on a PC. Exits 0 when every check passes.
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
    sock_path = os.path.join(tempfile.mkdtemp(), "lsat-falcon.sock")

    server = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    server.bind(sock_path)
    server.listen(1)
    server.settimeout(60)

    env = dict(os.environ, LSAT_FALCON_DATA=data_dir, HOME=data_dir)
    env.pop("LSAT_FALCON_ROOT", None)  # must find its data from its own location
    proc = subprocess.Popen(launcher + [os.path.join(app_dir, "backend", "entry"), sock_path], cwd=app_dir, env=env)
    conn, _ = server.accept()
    conn.settimeout(60)

    def send(msg_type, body):
        data = body.encode()
        conn.send(struct.pack("<ii", msg_type, len(data)))
        conn.send(data)

    def recv_raw():
        msg_type, length = struct.unpack("<ii", conn.recv(8))
        body = conn.recv(max(length, 1)) if length else b""
        assert len(body) == length, f"short body: {len(body)} of {length}"
        return msg_type, body

    # As main.qml does: join msgChunk (190) pieces back into one message.
    def recv():
        msg_type, body = recv_raw()
        if msg_type != 190:
            return msg_type, json.loads(body), 1
        pieces, n = [], None
        while True:
            head, piece = body.split(b"\n", 1)
            real, seq, n = map(int, head.split())
            assert seq == len(pieces), "chunks out of order"
            pieces.append(piece)
            if len(pieces) == n:
                return real, json.loads(b"".join(pieces)), n
            msg_type, body = recv_raw()
            assert msg_type == 190

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
    send(1, "{}")
    t, state, _ = recv()
    check(t == 100 and state["position"] == "", "hello: state first")
    t, meta, n = recv()
    check(t == 101 and len(meta["q"]) == 7626, f"hello: the index, {len(meta['q'])} questions in {n} chunks")

    send(2, json.dumps({"i": 300}))
    t, q, _ = recv()
    check(t == 102 and q["i"] == 300 and set(q["a"]) == set("ABCDE") and q["passage"], "a question with its passage")

    send(3, json.dumps({"shuffle": False}))
    send(4, json.dumps({"position": "PT1-S4-Q23"}))
    send(2, json.dumps({"i": 99999}))
    t, err, _ = recv()
    check(t == 199, "an unknown question is an error, not a crash")

    send(-1, "close")  # AppLoad's TERMINATE
    check(proc.wait(timeout=30) == 0, "backend exits cleanly on TERMINATE")
    state = json.load(open(os.path.join(data_dir, "state.json")))
    check(state["position"] == "PT1-S4-Q23" and state["settings"]["shuffle"] is False, "state.json saved")
    print(f"All {passed} backend checks passed.")


if __name__ == "__main__":
    main()
