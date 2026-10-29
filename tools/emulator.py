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

UI tests import it and drive an Emulator themselves (see
spanish-stories/emulator/test_app.py).
"""
import argparse
import json
import os
import random
import string
import struct
import subprocess
import sys
from pathlib import Path

from PySide6.QtCore import (QByteArray, QEvent, QMetaObject, QObject, QPointF, QProcess, QProcessEnvironment,
                            Property, QResource, Qt, QTimer, QUrl, Signal, Slot)
from PySide6.QtGui import QGuiApplication, QImage, QKeyEvent, QKeySequence, QMouseEvent, QShortcut
from PySide6.QtNetwork import QHostAddress, QTcpServer
from PySide6.QtQml import qmlRegisterType
from PySide6.QtQuick import QQuickView
import shiboken6

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import appbuild  # noqa: E402

SCREEN_W, SCREEN_H = 1404, 1872
MSG_TERMINATE, MSG_NEW_COORDINATOR = -1, -2


def log(*args):
    print("[emulator]", *args, flush=True)


class Bridge(QObject):
    """Plays AppLoad's part: owns the backend process and its socket."""

    def __init__(self, verbose=False):
        super().__init__()
        self.verbose = verbose
        self.endpoints, self.socket, self.buffer, self.process = [], None, b"", None
        self.server = QTcpServer(self)
        self.server.newConnection.connect(self.connected)
        if not self.server.listen(QHostAddress.LocalHost, 0):
            raise RuntimeError("cannot listen on localhost")

    def start(self, exe: Path, cwd: Path, env: dict, delay_ms=0):
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

    def live(self):
        self.endpoints = [e for e in self.endpoints if shiboken6.isValid(e)]
        return self.endpoints

    def connected(self):
        self.socket = self.server.nextPendingConnection()
        self.socket.readyRead.connect(self.ready)
        if self.live():
            self.write(MSG_NEW_COORDINATOR, str(len(self.endpoints)))

    def register(self, e):
        self.endpoints.append(e)
        self.send(MSG_NEW_COORDINATOR, str(len(self.live())))

    def send(self, t, body):
        if self.socket is None:
            # Same as AppLoad: messages sent before the backend connects are lost.
            log(f"no backend yet, dropping message {t}")
            return
        self.write(t, body)

    def write(self, t, body):
        data = body.encode()
        if self.verbose:
            log(f"-> {t}: {body[:160]}")
        self.socket.write(QByteArray(struct.pack("<ii", t, len(data)) + data))
        self.socket.flush()

    def ready(self):
        self.buffer += bytes(self.socket.readAll().data())
        while len(self.buffer) >= 8:
            t, n = struct.unpack("<ii", self.buffer[:8])
            if len(self.buffer) < 8 + n:
                break
            body = self.buffer[8:8 + n].decode()
            self.buffer = self.buffer[8 + n:]
            if self.verbose:
                log(f"<- {t}: {body[:160]}")
            for e in list(self.live()):
                e.messageReceived.emit(t, body)

    def terminate(self):
        if self.socket is not None:
            self.write(MSG_TERMINATE, "close")
        if self.process is not None and self.process.state() != QProcess.NotRunning:
            if not self.process.waitForFinished(3000):
                self.process.kill()
                self.process.waitForFinished(1000)
        self.socket = None


BRIDGE = None


class AppLoadEndpoint(QObject):
    """Stand-in for the `AppLoad` QML type from net.asivery.AppLoad 1.0."""

    messageReceived = Signal(int, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._id = ""

    def _get(self):
        return self._id

    def _set(self, v):
        self._id = v
        BRIDGE.register(self)

    applicationID = Property(str, _get, _set)

    @Slot(int, str)
    def sendMessage(self, t, contents):
        BRIDGE.send(t, contents)

    @Slot()
    def terminate(self):
        BRIDGE.terminate()


class Emulator:
    """The app in app_dir, its QML in a window (view) and its backend built
    for this computer and started with env, backend_delay ms late if given.
    Needs a QGuiApplication."""

    def __init__(self, app_dir: Path, env=None, scale=1.0, verbose=False, backend_delay=0):
        global BRIDGE
        app_dir = Path(app_dir).resolve()
        self.build = app_dir / "build" / "emulator"
        self.build.mkdir(parents=True, exist_ok=True)
        manifest = json.loads((app_dir / "app" / "manifest.json").read_text())
        rcc = self.build / "resources.rcc"
        appbuild.build_rcc(app_dir / "app" / "application.qrc", rcc)

        BRIDGE = self.bridge = Bridge(verbose)
        qmlRegisterType(AppLoadEndpoint, "net.asivery.AppLoad", 1, 0, "AppLoad")
        # AppLoad starts the backend first, then loads the frontend.
        if manifest.get("loadsBackend"):
            entry = self.build / "entry"
            go_env = dict(os.environ, CGO_ENABLED="0")
            go_env.pop("GOOS", None)
            go_env.pop("GOARCH", None)
            subprocess.run(["go", "build", "-o", str(entry), "."], cwd=app_dir / "backend", env=go_env, check=True)
            self.bridge.start(entry, app_dir, env or {}, backend_delay)

        prefix = "".join(random.choice(string.ascii_uppercase) for _ in range(10))
        if not QResource.registerResource(str(rcc), "/" + prefix):
            raise RuntimeError(f"cannot register {rcc}")
        self.closed = False
        self.view = QQuickView()
        self.view.setTitle(f"{manifest['name']} - reMarkable 2 emulator")
        self.view.setResizeMode(QQuickView.SizeRootObjectToView)
        self.view.setInitialProperties({"appUrl": QUrl(f"qrc:/{prefix}{manifest['entry']}"), "deviceScale": scale})
        self.view.setSource(QUrl.fromLocalFile(str(TOOLS / "emulator_host.qml")))
        for err in self.view.errors():
            log("QML error:", err.toString())
        self.view.resize(round(SCREEN_W * scale), round(SCREEN_H * scale))
        self.host = self.view.rootObject()
        self.host.appClosed.connect(self._closed)

    @property
    def app(self):
        loader = self.host.findChild(QObject, "appLoader")
        return loader.property("item") if loader else None

    def _closed(self):
        # AppLoad calls unloading() and then destroys the frontend.
        QMetaObject.invokeMethod(self.app, "unloading")
        self.closed = True
        self.host.setProperty("closed", True)
        self.host.findChild(QObject, "appLoader").setProperty("active", False)
        log("app closed")

    def screenshot(self, path: Path) -> Path:
        """Saves the screen, in greys as e-ink shows it."""
        img = self.view.grabWindow().convertToFormat(QImage.Format_Grayscale8)
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(str(path))
        return path

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
    emu = Emulator(args.app, dict(kv.split("=", 1) for kv in args.env), scale, args.verbose)
    view = emu.view
    emu.host.appClosed.connect(lambda: QTimer.singleShot(800, qapp.quit))

    def shoot(path):
        log("saved", emu.screenshot(path))

    def tap(x, y):
        pos = QPointF(x * scale, y * scale)
        for kind in (QEvent.MouseButtonPress, QEvent.MouseButtonRelease):
            ev = QMouseEvent(kind, pos, pos, Qt.LeftButton,
                             Qt.LeftButton if kind == QEvent.MouseButtonPress else Qt.NoButton, Qt.NoModifier)
            QGuiApplication.sendEvent(view, ev)
        log(f"tap {x},{y}")

    def mouse(kind, x, y, buttons):
        pos = QPointF(x * scale, y * scale)
        button = Qt.LeftButton if kind != QEvent.MouseMove else Qt.NoButton
        QGuiApplication.sendEvent(view, QMouseEvent(kind, pos, pos, button, buttons, Qt.NoModifier))

    def swipe(x1, y1, x2, y2, ms, done):
        steps = max(5, ms // 16)
        mouse(QEvent.MouseButtonPress, x1, y1, Qt.LeftButton)

        def step(i):
            if i <= steps:
                mouse(QEvent.MouseMove, x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, Qt.LeftButton)
                QTimer.singleShot(max(1, ms // steps), lambda: step(i + 1))
            else:
                mouse(QEvent.MouseButtonRelease, x2, y2, Qt.NoButton)
                log(f"swipe {x1},{y1} to {x2},{y2}")
                done()

        step(1)

    def key(code, text=""):
        for kind in (QEvent.KeyPress, QEvent.KeyRelease):
            QGuiApplication.sendEvent(view, QKeyEvent(kind, code, Qt.NoModifier, text))

    def command(line, reply):
        """Runs one --control command and calls reply with its answer."""
        word, _, rest = line.strip().partition(" ")
        nums = lambda: [int(float(v)) for v in rest.split()]
        later = lambda: QTimer.singleShot(400, lambda: reply("ok"))
        try:
            if word == "tap":
                x, y = nums()
                tap(x, y)
                later()
            elif word == "swipe":
                v = nums()
                swipe(v[0], v[1], v[2], v[3], v[4] if len(v) > 4 else 300, later)
            elif word == "type":
                for ch in rest:
                    key(Qt.Key_unknown, ch)
                later()
            elif word == "key":
                code = getattr(Qt, "Key_" + rest.strip(), None)
                if code is None:
                    reply(f"error no key called {rest.strip()!r} (Qt's names: Return, Backspace, Tab, Up, ...)")
                    return
                key(code)
                later()
            elif word == "shot":
                if not rest.strip():
                    reply("error give a file name")
                    return
                path = Path(rest.strip()).resolve()
                shoot(path)
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
        QTimer.singleShot(args.after // 2 + i * 1000, lambda x=x, y=y: tap(x, y))
    if args.shot:
        delay = max(args.after, args.after // 2 + len(args.tap) * 1000 + 1500)
        QTimer.singleShot(delay, lambda: (shoot(args.shot), qapp.quit()))
    shots = [0]

    def save():
        shots[0] += 1
        shoot(emu.build / f"screenshot-{shots[0]}.png")

    QShortcut(QKeySequence("S"), view, activated=save)
    QShortcut(QKeySequence("Escape"), view, activated=qapp.quit)
    view.show()
    code = qapp.exec()
    emu.shutdown()
    return code


if __name__ == "__main__":
    sys.exit(main())
