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

Needs PySide6 (pip install PySide6) and Go. Mouse clicks act as taps; S
saves a screenshot to build/emulator/, Esc quits. Biblioteca has its
own, older emulator with UI tests in spanish-stories/emulator/.
"""
import argparse
import os
import random
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
    args = ap.parse_args()
    if args.offscreen:
        os.environ["QT_QPA_PLATFORM"] = "offscreen"

    from PySide6.QtCore import (QByteArray, QEvent, QMetaObject, QObject, QPointF, QProcess,
                                QProcessEnvironment, Property, QResource, Qt, QTimer, QUrl, Signal, Slot)
    from PySide6.QtGui import QGuiApplication, QImage, QKeySequence, QMouseEvent, QShortcut
    from PySide6.QtNetwork import QHostAddress, QTcpServer
    from PySide6.QtQml import qmlRegisterType
    from PySide6.QtQuick import QQuickView

    app_dir = args.app.resolve()
    build = app_dir / "build" / "emulator"
    build.mkdir(parents=True, exist_ok=True)
    manifest = __import__("json").loads((app_dir / "app" / "manifest.json").read_text())
    rcc = build / "resources.rcc"
    appbuild.build_rcc(app_dir / "app" / "application.qrc", rcc)
    entry = None
    if manifest.get("loadsBackend"):
        entry = build / "entry"
        env = dict(os.environ, CGO_ENABLED="0")
        env.pop("GOOS", None)
        env.pop("GOARCH", None)
        subprocess.run(["go", "build", "-o", str(entry), "."], cwd=app_dir / "backend", env=env, check=True)

    qapp = QGuiApplication(sys.argv[:1])

    class Bridge(QObject):
        def __init__(self):
            super().__init__()
            self.endpoints, self.socket, self.buffer, self.process = [], None, b"", None
            self.server = QTcpServer(self)
            self.server.newConnection.connect(self.connected)
            self.server.listen(QHostAddress.LocalHost, 0)

        def start(self, exe, env):
            self.process = QProcess(self)
            penv = QProcessEnvironment.systemEnvironment()
            for k, v in env.items():
                penv.insert(k, v)
            self.process.setProcessEnvironment(penv)
            self.process.setWorkingDirectory(str(app_dir))
            self.process.setProcessChannelMode(QProcess.ForwardedChannels)
            self.process.start(str(exe), [f"tcp:127.0.0.1:{self.server.serverPort()}"])

        def connected(self):
            self.socket = self.server.nextPendingConnection()
            self.socket.readyRead.connect(self.ready)
            if self.endpoints:
                self.write(MSG_NEW_COORDINATOR, str(len(self.endpoints)))

        def register(self, e):
            self.endpoints.append(e)
            self.send(MSG_NEW_COORDINATOR, str(len(self.endpoints)))

        def send(self, t, body):
            if self.socket is None:
                log(f"no backend yet, dropping message {t}")
                return
            self.write(t, body)

        def write(self, t, body):
            data = body.encode()
            if args.verbose:
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
                if args.verbose:
                    log(f"<- {t}: {body[:160]}")
                for e in self.endpoints:
                    e.messageReceived.emit(t, body)

        def terminate(self):
            if self.socket is not None:
                self.write(MSG_TERMINATE, "close")
            if self.process is not None and not self.process.waitForFinished(3000):
                self.process.kill()

    bridge = Bridge()

    class AppLoadEndpoint(QObject):
        messageReceived = Signal(int, str)

        def __init__(self, parent=None):
            super().__init__(parent)
            self._id = ""

        def _get(self):
            return self._id

        def _set(self, v):
            self._id = v
            bridge.register(self)

        applicationID = Property(str, _get, _set)

        @Slot(int, str)
        def sendMessage(self, t, contents):
            bridge.send(t, contents)

        @Slot()
        def terminate(self):
            bridge.terminate()

    qmlRegisterType(AppLoadEndpoint, "net.asivery.AppLoad", 1, 0, "AppLoad")
    if entry:
        bridge.start(entry, dict(kv.split("=", 1) for kv in args.env))

    prefix = "".join(random.choice(string.ascii_uppercase) for _ in range(10))
    QResource.registerResource(str(rcc), "/" + prefix)
    scale = args.scale or (1.0 if args.offscreen else
                           min(1.0, (qapp.primaryScreen().availableGeometry().height() - 60) / SCREEN_H))
    view = QQuickView()
    view.setTitle(f"{manifest['name']} - reMarkable 2 emulator")
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.setInitialProperties({"appUrl": QUrl(f"qrc:/{prefix}{manifest['entry']}"), "deviceScale": scale})
    view.setSource(QUrl.fromLocalFile(str(TOOLS / "emulator_host.qml")))
    for err in view.errors():
        log("QML error:", err.toString())
    view.resize(round(SCREEN_W * scale), round(SCREEN_H * scale))
    host = view.rootObject()

    def closed():
        loader = host.findChild(QObject, "appLoader")
        QMetaObject.invokeMethod(loader.property("item"), "unloading")
        host.setProperty("closed", True)
        loader.setProperty("active", False)
        log("app closed")
        QTimer.singleShot(800, qapp.quit)

    host.appClosed.connect(closed)

    def shoot(path):
        img = view.grabWindow().convertToFormat(QImage.Format_Grayscale8)
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(str(path))
        log("saved", path)

    def tap(x, y):
        pos = QPointF(x * scale, y * scale)
        for kind in (QEvent.MouseButtonPress, QEvent.MouseButtonRelease):
            ev = QMouseEvent(kind, pos, pos, Qt.LeftButton,
                             Qt.LeftButton if kind == QEvent.MouseButtonPress else Qt.NoButton, Qt.NoModifier)
            QGuiApplication.sendEvent(view, ev)
        log(f"tap {x},{y}")

    for i, t in enumerate(args.tap):
        x, y = (int(v) for v in t.split(","))
        QTimer.singleShot(args.after // 2 + i * 1000, lambda x=x, y=y: tap(x, y))
    if args.shot:
        delay = max(args.after, args.after // 2 + len(args.tap) * 1000 + 1500)
        QTimer.singleShot(delay, lambda: (shoot(args.shot), qapp.quit()))
    shots = [0]

    def save():
        shots[0] += 1
        shoot(build / f"screenshot-{shots[0]}.png")

    QShortcut(QKeySequence("S"), view, activated=save)
    QShortcut(QKeySequence("Escape"), view, activated=qapp.quit)
    view.show()
    code = qapp.exec()
    bridge.terminate()
    return code


if __name__ == "__main__":
    sys.exit(main())
