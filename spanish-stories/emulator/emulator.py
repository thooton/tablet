"""Desktop emulator for the Spanish Reader reMarkable app.

Runs the real app (the QML compiled into resources.rcc plus the Go backend)
the way AppLoad runs it inside xochitl on the tablet:

  * resources.rcc is registered under a random qrc prefix and
    qrc:/<prefix>/ui/main.qml is loaded into a 1404x1872 window (rM2 screen);
  * a stand-in for AppLoad's `net.asivery.AppLoad` QML module carries messages
    between the QML and the backend, which runs as a separate process speaking
    the same header+body protocol (over TCP instead of a unix socket, which
    Windows lacks);
  * the root item's close() signal and unloading() function are honoured.

Usage:
    python emulator/emulator.py              # interactive, mouse = finger
    python emulator/emulator.py --fresh      # forget saved progress first
    python emulator/emulator.py --scale 0.6  # window size (default fits screen)

Mouse clicks act as taps; drag left/right to swipe. Press S to save a
screenshot (build/emulator/screenshot-N.png), Esc to quit.
"""
import argparse
import os
import random
import shutil
import string
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "emulator"
SCREEN_W, SCREEN_H = 1404, 1872
APP_ID = "spanish-reader"

MSG_TERMINATE = -1
MSG_NEW_COORDINATOR = -2
MSG_LOST_COORDINATOR = -3


def log(*args):
    print("[emulator]", *args, flush=True)


# --------------------------------------------------------------------------
# Building the pieces


def build_rcc(out: Path) -> Path:
    sys.path.insert(0, str(ROOT / "tools"))
    from build import find_rcc  # noqa: E402

    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([find_rcc(), "--binary", "-o", str(out), str(ROOT / "app" / "application.qrc")], check=True)
    return out


def build_backend(out: Path) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    if not shutil.which("go"):
        sys.exit("The emulator needs Go (https://go.dev/dl/) to build the backend for this computer.")
    env = dict(os.environ, CGO_ENABLED="0")
    env.pop("GOOS", None)
    env.pop("GOARCH", None)
    subprocess.run(["go", "build", "-o", str(out), "."], cwd=ROOT / "backend", env=env, check=True)
    return out


# --------------------------------------------------------------------------
# The emulated AppLoad runtime (needs Qt, imported lazily so the build helpers
# above work without a display)

from PySide6.QtCore import (QByteArray, QMetaObject, QObject, QPoint, QProcess, QProcessEnvironment,  # noqa: E402
                            Property, QResource, Qt, QTimer, QUrl, Signal, Slot)
from PySide6.QtGui import QGuiApplication, QImage, QKeySequence, QShortcut  # noqa: E402
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

    @property
    def address(self):
        return f"tcp:127.0.0.1:{self.server.serverPort()}"

    def start_backend(self, exe: Path, env: dict, delay_ms: int = 0):
        def start():
            self.process = QProcess(self)
            penv = QProcessEnvironment.systemEnvironment()
            for k, v in env.items():
                penv.insert(k, v)
            self.process.setProcessEnvironment(penv)
            self.process.setProcessChannelMode(QProcess.ForwardedChannels)
            self.process.finished.connect(lambda code, status: log(f"backend exited with code {code}"))
            self.process.start(str(exe), [self.address])
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
            log(f"no active socket, dropping message type {msg_type}")
            return
        self.sent.append((msg_type, body))
        self._write(msg_type, body)

    def _write(self, msg_type, body):
        data = body.encode("utf-8")
        if self.verbose:
            log(f"-> backend {msg_type}: {body[:120]}")
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
                log(f"<- backend {msg_type}: {body[:120]}")
            for e in list(self._live_endpoints()):
                e.messageReceived.emit(msg_type, body)

    def terminate(self):
        if self.socket is not None:
            self._write(MSG_TERMINATE, "close")
            self.socket.flush()
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
    def __init__(self, data_dir: Path, fresh=False, scale=1.0, verbose=False, backend_delay=0,
                 stories_root: Path = ROOT, rcc: Path = None, backend: Path = None):
        global BRIDGE
        if fresh and data_dir.exists():
            shutil.rmtree(data_dir)
        rcc = rcc or build_rcc(BUILD / "resources.rcc")
        backend = backend or build_backend(BUILD / ("entry.exe" if os.name == "nt" else "entry"))

        BRIDGE = Bridge(verbose=verbose)
        self.bridge = BRIDGE
        qmlRegisterType(AppLoadEndpoint, "net.asivery.AppLoad", 1, 0, "AppLoad")

        # AppLoad starts the backend first, then loads the frontend.
        self.bridge.start_backend(backend, {
            "SPANISH_READER_ROOT": str(stories_root),
            "SPANISH_READER_DATA": str(data_dir),
            "SPANISH_READER_EXTRA_STORIES": str(data_dir / "extra-stories"),
        }, delay_ms=backend_delay)

        prefix = "".join(random.choice(string.ascii_uppercase) for _ in range(10))
        if not QResource.registerResource(str(rcc), "/" + prefix):
            raise RuntimeError(f"cannot register {rcc}")

        self.closed = False
        self.view = QQuickView()
        self.view.setTitle("Spanish Reader - reMarkable 2 emulator")
        self.view.setResizeMode(QQuickView.SizeRootObjectToView)
        self.view.setColor(Qt.white)
        self.view.setInitialProperties({"appUrl": QUrl(f"qrc:/{prefix}/ui/main.qml"), "deviceScale": scale})
        self.view.setSource(QUrl.fromLocalFile(str(ROOT / "emulator" / "host.qml")))
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

    def shutdown(self):
        self.bridge.terminate()


def main() -> int:
    ap = argparse.ArgumentParser(description="reMarkable 2 emulator for Spanish Reader")
    ap.add_argument("--fresh", action="store_true", help="start with no saved progress")
    ap.add_argument("--scale", type=float, default=0.0, help="window scale (default: fit the screen)")
    ap.add_argument("--verbose", action="store_true", help="log every backend message")
    ap.add_argument("--backend-delay", type=int, default=0, help="start the backend late (ms)")
    ap.add_argument("--data", type=Path, default=BUILD / "data", help="where progress is saved")
    args = ap.parse_args()

    app = QGuiApplication(sys.argv[:1])
    scale = args.scale
    if not scale:
        avail = app.primaryScreen().availableGeometry()
        scale = min(1.0, (avail.height() - 60) / SCREEN_H, (avail.width() - 40) / SCREEN_W)
    emu = Emulator(args.data, fresh=args.fresh, scale=scale, verbose=args.verbose, backend_delay=args.backend_delay)

    shots = [0]

    def save_shot():
        shots[0] += 1
        log("saved", emu.screenshot(BUILD / f"screenshot-{shots[0]}.png"))

    QShortcut(QKeySequence("S"), emu.view, activated=save_shot)
    QShortcut(QKeySequence("Escape"), emu.view, activated=app.quit)
    emu.host.appClosed.connect(lambda: QTimer.singleShot(800, app.quit))
    emu.view.show()
    code = app.exec()
    emu.shutdown()
    return code


if __name__ == "__main__":
    sys.exit(main())
