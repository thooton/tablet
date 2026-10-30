"""Runs any app in this repository on a computer, as a 1404x1872
reMarkable 2 screen, the way AppLoad runs it inside xochitl: the app's QML
compiled into resources.rcc and registered under a random qrc prefix, and
its Go backend started as a separate process speaking AppLoad's
header+body protocol (over TCP here).

    python tools/emulator.py <app dir> [options]

    --env NAME=VALUE    set for the backend (repeatable), e.g. a data folder
    --shot FILE         save a screenshot after --after ms, then quit
    --after MS          (default 4000)
    --tap X,Y           tap at screen pixels before the screenshot (repeatable;
                        one every second, starting at --after / 2)
    --verbose           log every message
    --offscreen         no window (QT_QPA_PLATFORM=offscreen), for --shot
    --control PORT      take commands on 127.0.0.1:PORT, a line each, so an
                        agent can drive the app step by step (tools/drive.py
                        sends them): tap X Y, swipe X1 Y1 X2 Y2 [MS],
                        type TEXT, key NAME (Return, Backspace, ...),
                        shot FILE, quit. Each is answered "ok" or "error ...".

Needs PySide6 (pip install PySide6) and Go. Mouse clicks act as taps; S
saves a screenshot to build/emulator/, Esc quits.

Biblioteca's and LSAT Falcon's UI tests (<app dir>/emulator/test_app.py)
import this file and drive an Emulator, after making the QGuiApplication.
"""
import argparse
import json
import os
import random
import shutil
import string
import struct
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import appbuild  # noqa: E402

SCREEN_W, SCREEN_H = 1404, 1872
MSG_TERMINATE, MSG_NEW_COORDINATOR = -1, -2


def log(*args):
    print("[emulator]", *args, flush=True)


from PySide6.QtCore import (QByteArray, QEvent, QMetaObject, QObject, QPointF, QProcess,  # noqa: E402
                            QProcessEnvironment, Property, QResource, Qt, QTimer, QUrl, Signal, Slot)
from PySide6.QtGui import QGuiApplication, QImage, QKeyEvent, QKeySequence, QMouseEvent, QShortcut  # noqa: E402
from PySide6.QtNetwork import QHostAddress, QTcpServer  # noqa: E402
from PySide6.QtQml import qmlRegisterType  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402
import shiboken6  # noqa: E402


class Bridge(QObject):
    """Plays AppLoad's part: owns the backend process and its socket."""

    def __init__(self, verbose=False):
        super().__init__()
        self.verbose = verbose
        self.endpoints = []
        self.socket = None
        self.buffer = b""
        self.process = None
        self.sent = []       # (type, body) frontend -> backend, for tests
        self.received = []   # (type, body) backend -> frontend
        self.server = QTcpServer(self)
        self.server.newConnection.connect(self._on_connection)
        if not self.server.listen(QHostAddress.LocalHost, 0):
            raise RuntimeError("cannot listen on localhost")

    def start_backend(self, exe: Path, cwd: Path, env: dict, delay_ms: int = 0):
        def start():
            self.process = QProcess(self)
            penv = QProcessEnvironment.systemEnvironment()
            for k, v in env.items():
                penv.insert(k, v)
            self.process.setProcessEnvironment(penv)
            self.process.setWorkingDirectory(str(cwd))
            self.process.setProcessChannelMode(QProcess.ForwardedChannels)
            self.process.finished.connect(lambda code, status: log(f"backend exited with code {code}"))
            self.process.start(str(exe), [f"tcp:127.0.0.1:{self.server.serverPort()}"])
            if not self.process.waitForStarted(5000):
                log("backend failed to start:", self.process.errorString())

        if delay_ms:
            QTimer.singleShot(delay_ms, start)
        else:
            start()

    def _on_connection(self):
        self.socket = self.server.nextPendingConnection()
        self.socket.readyRead.connect(self._on_ready_read)
        log("backend connected")
        live = self._live_endpoints()
        if live:
            self._write(MSG_NEW_COORDINATOR, str(len(live)))

    def _live_endpoints(self):
        self.endpoints = [e for e in self.endpoints if shiboken6.isValid(e)]
        return self.endpoints

    def register(self, endpoint):
        self.endpoints.append(endpoint)
        self.send(MSG_NEW_COORDINATOR, str(len(self._live_endpoints())))

    def send(self, msg_type: int, body: str):
        if self.socket is None:
            # Same as AppLoad: messages sent before the backend connects are lost.
            log(f"no backend yet, dropping message {msg_type}")
            return
        self.sent.append((msg_type, body))
        self._write(msg_type, body)

    def _write(self, msg_type, body):
        data = body.encode("utf-8")
        if self.verbose:
            log(f"-> {msg_type}: {body[:160]}")
        self.socket.write(QByteArray(struct.pack("<ii", msg_type, len(data)) + data))
        self.socket.flush()

    def _on_ready_read(self):
        self.buffer += bytes(self.socket.readAll().data())
        while len(self.buffer) >= 8:
            msg_type, length = struct.unpack("<ii", self.buffer[:8])
            if len(self.buffer) < 8 + length:
                break
            body = self.buffer[8:8 + length].decode("utf-8")
            self.buffer = self.buffer[8 + length:]
            self.received.append((msg_type, body))
            if self.verbose:
                log(f"<- {msg_type}: {body[:160]}")
            for e in list(self._live_endpoints()):
                e.messageReceived.emit(msg_type, body)

    def terminate(self):
        if self.socket is not None:
            self._write(MSG_TERMINATE, "close")
        if self.process is not None and self.process.state() != QProcess.NotRunning:
            if not self.process.waitForFinished(1500):
                self.process.kill()
                self.process.waitForFinished(1000)
        self.socket = None


BRIDGE = None


class AppLoadEndpoint(QObject):
    """Stand-in for the `AppLoad` QML type from net.asivery.AppLoad 1.0."""

    messageReceived = Signal(int, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._app_id = ""

    def _get_id(self):
        return self._app_id

    def _set_id(self, value):
        self._app_id = value
        BRIDGE.register(self)

    applicationID = Property(str, _get_id, _set_id)

    @Slot(int, str)
    def sendMessage(self, msg_type, contents):
        BRIDGE.send(msg_type, contents)

    @Slot()
    def terminate(self):
        BRIDGE.terminate()


class Emulator:
    """The app in <app dir>, built into <app dir>/build/emulator/ and loaded
    into a QQuickView. env goes to the backend; with fresh, data (a folder)
    is emptied first. backend_delay starts the backend late (ms), as a slow
    tablet might."""

    def __init__(self, app_dir: Path, env: dict = None, data: Path = None, fresh=False, scale=1.0,
                 verbose=False, backend_delay=0):
        global BRIDGE
        app_dir = Path(app_dir).resolve()
        self.build = app_dir / "build" / "emulator"
        self.build.mkdir(parents=True, exist_ok=True)
        if fresh and data and data.exists():
            shutil.rmtree(data)
        manifest = json.loads((app_dir / "app" / "manifest.json").read_text())
        rcc = self.build / "resources.rcc"
        appbuild.build_rcc(app_dir / "app" / "application.qrc", rcc)

        BRIDGE = Bridge(verbose=verbose)
        self.bridge = BRIDGE
        qmlRegisterType(AppLoadEndpoint, "net.asivery.AppLoad", 1, 0, "AppLoad")
        # AppLoad starts the backend first, then loads the frontend.
        if manifest.get("loadsBackend"):
            if not shutil.which("go"):
                sys.exit("The emulator needs Go (https://go.dev/dl/) to build the backend for this computer.")
            entry = self.build / ("entry.exe" if os.name == "nt" else "entry")
            goenv = dict(os.environ, CGO_ENABLED="0")
            goenv.pop("GOOS", None)
            goenv.pop("GOARCH", None)
            subprocess.run(["go", "build", "-o", str(entry), "."], cwd=app_dir / "backend", env=goenv, check=True)
            self.bridge.start_backend(entry, app_dir, env or {}, delay_ms=backend_delay)

        prefix = "".join(random.choice(string.ascii_uppercase) for _ in range(10))
        if not QResource.registerResource(str(rcc), "/" + prefix):
            raise RuntimeError(f"cannot register {rcc}")

        self.scale = scale
        self.closed = False
        self.view = QQuickView()
        self.view.setTitle(f"{manifest['name']} - reMarkable 2 emulator")
        self.view.setResizeMode(QQuickView.SizeRootObjectToView)
        self.view.setColor(Qt.white)
        self.view.setInitialProperties({"appUrl": QUrl(f"qrc:/{prefix}{manifest['entry']}"), "deviceScale": scale})
        self.view.setSource(QUrl.fromLocalFile(str(TOOLS / "emulator_host.qml")))
        for err in self.view.errors():
            log("QML error:", err.toString())
        self.view.resize(round(SCREEN_W * scale), round(SCREEN_H * scale))
        self.host = self.view.rootObject()
        self.host.appClosed.connect(self._on_close)

    @property
    def app(self):
        loader = self.host.findChild(QObject, "appLoader")
        return loader.property("item") if loader else None

    def _on_close(self):
        # AppLoad calls unloading() and then destroys the frontend.
        QMetaObject.invokeMethod(self.app, "unloading")
        self.closed = True
        self.host.setProperty("closed", True)
        self.host.findChild(QObject, "appLoader").setProperty("active", False)
        log("app closed")

    def screenshot(self, path: Path, grayscale=True) -> Path:
        img = self.view.grabWindow()
        if grayscale:
            img = img.convertToFormat(QImage.Format_Grayscale8)
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(str(path))
        return path

    def _mouse(self, kind, x, y, buttons):
        pos = QPointF(x * self.scale, y * self.scale)
        button = Qt.LeftButton if kind != QEvent.MouseMove else Qt.NoButton
        QGuiApplication.sendEvent(self.view, QMouseEvent(kind, pos, pos, button, buttons, Qt.NoModifier))

    def tap(self, x, y):
        """A tap at screen pixels."""
        self._mouse(QEvent.MouseButtonPress, x, y, Qt.LeftButton)
        self._mouse(QEvent.MouseButtonRelease, x, y, Qt.NoButton)
        log(f"tap {x},{y}")

    def swipe(self, x1, y1, x2, y2, ms, done):
        """A drag from (x1, y1) to (x2, y2) over ms, then calls done."""
        steps = max(5, ms // 16)
        self._mouse(QEvent.MouseButtonPress, x1, y1, Qt.LeftButton)

        def step(i):
            if i <= steps:
                self._mouse(QEvent.MouseMove, x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, Qt.LeftButton)
                QTimer.singleShot(max(1, ms // steps), lambda: step(i + 1))
            else:
                self._mouse(QEvent.MouseButtonRelease, x2, y2, Qt.NoButton)
                log(f"swipe {x1},{y1} to {x2},{y2}")
                done()

        step(1)

    def key(self, code, text=""):
        for kind in (QEvent.KeyPress, QEvent.KeyRelease):
            QGuiApplication.sendEvent(self.view, QKeyEvent(kind, code, Qt.NoModifier, text))

    def shutdown(self):
        self.bridge.terminate()


def main() -> int:
    ap = argparse.ArgumentParser(description="reMarkable 2 emulator for AppLoad apps")
    ap.add_argument("app", type=Path)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--shot", type=Path)
    ap.add_argument("--after", type=int, default=4000)
    ap.add_argument("--tap", action="append", default=[])
    ap.add_argument("--scale", type=float, default=0.0)
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--offscreen", action="store_true")
    ap.add_argument("--control", type=int, default=0)
    args = ap.parse_args()
    if args.offscreen:
        os.environ["QT_QPA_PLATFORM"] = "offscreen"

    qapp = QGuiApplication(sys.argv[:1])
    scale = args.scale or (1.0 if args.offscreen else
                           min(1.0, (qapp.primaryScreen().availableGeometry().height() - 60) / SCREEN_H))
    emu = Emulator(args.app, env=dict(kv.split("=", 1) for kv in args.env), scale=scale, verbose=args.verbose)
    emu.host.appClosed.connect(lambda: QTimer.singleShot(800, qapp.quit))

    def command(line, reply):
        """Runs one --control command and calls reply with its answer."""
        word, _, rest = line.strip().partition(" ")
        nums = lambda: [int(float(v)) for v in rest.split()]
        later = lambda: QTimer.singleShot(400, lambda: reply("ok"))
        try:
            if word == "tap":
                x, y = nums()
                emu.tap(x, y)
                later()
            elif word == "swipe":
                v = nums()
                emu.swipe(v[0], v[1], v[2], v[3], v[4] if len(v) > 4 else 300, later)
            elif word == "type":
                for ch in rest:
                    emu.key(Qt.Key_unknown, ch)
                later()
            elif word == "key":
                code = getattr(Qt, "Key_" + rest.strip(), None)
                if code is None:
                    reply(f"error no key called {rest.strip()!r} (Qt's names: Return, Backspace, Tab, Up, ...)")
                    return
                emu.key(code)
                later()
            elif word == "shot":
                if not rest.strip():
                    reply("error give a file name")
                    return
                path = Path(rest.strip()).resolve()
                log("saved", emu.screenshot(path))
                reply(f"ok {path}")
            elif word == "quit":
                reply("ok")
                QTimer.singleShot(200, qapp.quit)
            else:
                reply(f"error unknown command {word!r} (tap, swipe, type, key, shot, quit)")
        except (ValueError, IndexError):
            reply(f"error can't read {line.strip()!r}")

    if args.control:
        control = QTcpServer()

        def accepted():
            conn = control.nextPendingConnection()
            buf = [b""]

            def readable():
                buf[0] += bytes(conn.readAll().data())
                while b"\n" in buf[0]:
                    line, buf[0] = buf[0].split(b"\n", 1)
                    command(line.decode(), lambda answer: (conn.write(QByteArray((answer + "\n").encode())), conn.flush()))

            conn.readyRead.connect(readable)

        control.newConnection.connect(accepted)
        if not control.listen(QHostAddress.LocalHost, args.control):
            log(f"can't listen on port {args.control}")
            return 1
        log(f"taking commands on 127.0.0.1:{args.control}")

    for i, t in enumerate(args.tap):
        x, y = (int(v) for v in t.split(","))
        QTimer.singleShot(args.after // 2 + i * 1000, lambda x=x, y=y: emu.tap(x, y))
    if args.shot:
        delay = max(args.after, args.after // 2 + len(args.tap) * 1000 + 1500)
        QTimer.singleShot(delay, lambda: (log("saved", emu.screenshot(args.shot)), qapp.quit()))
    shots = [0]

    def save():
        shots[0] += 1
        log("saved", emu.screenshot(emu.build / f"screenshot-{shots[0]}.png"))

    QShortcut(QKeySequence("S"), emu.view, activated=save)
    QShortcut(QKeySequence("Escape"), emu.view, activated=qapp.quit)
    emu.view.show()
    code = qapp.exec()
    emu.shutdown()
    return code


if __name__ == "__main__":
    sys.exit(main())
