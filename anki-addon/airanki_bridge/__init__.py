"""AirAnki Bridge. Importing command logic in tests does not require Qt."""
from .commands import BRIDGE_VERSION, handle, logger


def _install():
    import aqt
    from aqt import gui_hooks
    from aqt.qt import QLocalServer, QTimer
    from .runner import CommandRunner
    import json
    import os

    path = os.path.expanduser("~/Library/Application Support/AirAnki/bridge.sock")

    class Server:
        def __init__(self):
            self.server = None
            self.clients = {}
            self.runner = None
            self.quit_connected = False
            self.overlay = None

        def flash(self, style):
            config = aqt.mw.addonManager.getConfig(__name__) or {}
            if not config.get("feedback_flash", True):
                return
            if self.overlay is None:
                from .flash import Flash
                self.overlay = Flash(aqt.mw)
            self.overlay.show_style(style)

        def start(self, *args):
            if self.server is not None or aqt.mw is None:
                return
            try:
                if not self.quit_connected:
                    aqt.mw.app.aboutToQuit.connect(self.stop)
                    self.quit_connected = True
                directory = os.path.dirname(path)
                os.makedirs(directory, mode=0o700, exist_ok=True)
                os.chmod(directory, 0o700)
                QLocalServer.removeServer(path)
                server = QLocalServer(aqt.mw)
                options = getattr(QLocalServer, "SocketOption", QLocalServer)
                server.setSocketOptions(options.UserAccessOption)
                server.newConnection.connect(self.accept)
                if not server.listen(path):
                    raise RuntimeError(server.errorString())
                self.server = server
                self.runner = CommandRunner(aqt.mw, lambda fn: QTimer.singleShot(0, fn), self.flash)
            except Exception:
                logger.exception("Bridge could not listen")

        def stop(self, *args):
            if self.runner:
                self.runner.cancel()
            for socket in list(self.clients):
                socket.abort()
                socket.deleteLater()
            self.clients.clear()
            if self.server:
                self.server.close()
                self.server.deleteLater()
                self.server = None
                QLocalServer.removeServer(path)
            self.runner = None

        def accept(self):
            try:
                while self.server and self.server.hasPendingConnections():
                    socket = self.server.nextPendingConnection()
                    if len(self.clients) >= 8:
                        socket.abort(); socket.deleteLater(); continue
                    self.clients[socket] = bytearray()
                    socket.setReadBufferSize(65536)
                    socket.readyRead.connect(lambda s=socket: self.read(s))
                    socket.disconnected.connect(lambda s=socket: self.drop(s))
                    self.read(socket)
            except Exception:
                logger.exception("Bridge accept failed")

        def drop(self, socket):
            self.clients.pop(socket, None)
            socket.deleteLater()

        def send(self, socket, reply):
            try:
                if socket in self.clients:
                    socket.write((json.dumps(reply, separators=(",", ":")) + "\n").encode("utf-8"))
                    socket.flush()
            except Exception:
                logger.exception("Bridge reply failed")

        def read(self, socket):
            try:
                buffer = self.clients.get(socket)
                if buffer is None:
                    return
                buffer.extend(bytes(socket.readAll()))
                if len(buffer) > 65536:
                    socket.abort(); return
                while b"\n" in buffer:
                    line, _, rest = buffer.partition(b"\n")
                    buffer[:] = rest
                    try:
                        request = json.loads(line)
                        if not isinstance(request, dict):
                            raise ValueError("Request must be an object")
                        self.runner.dispatch(request, lambda result, s=socket: self.send(s, result))
                        serial = self.runner.serial
                        runner = self.runner
                        # Deadline only: no polling loop or Qt timer for socket servicing.
                        QTimer.singleShot(250, lambda r=runner, n=serial: r.timeout(n))
                    except Exception as exc:
                        self.send(socket, dict(id=None, ok=False, did="none", ease=None, count=0,
                                               side="none", reviewing=False, error=str(exc), version=BRIDGE_VERSION))
            except Exception:
                logger.exception("Bridge read failed")
                socket.abort()

        def grade_done(self, *args):
            if self.runner:
                self.runner.completed("grade")

        def undo_done(self, *args):
            if self.runner:
                self.runner.completed("undo")

    server = Server()
    gui_hooks.main_window_did_init.append(server.start)
    gui_hooks.profile_did_open.append(server.start)
    gui_hooks.profile_will_close.append(server.stop)
    gui_hooks.reviewer_did_answer_card.append(server.grade_done)
    gui_hooks.state_did_undo.append(server.undo_done)
    if aqt.mw is not None:
        server.start()
    # Hook closures retain server for the lifetime of Anki.


try:
    import aqt  # noqa: F401
except ImportError:
    pass
else:
    try:
        _install()
    except Exception:
        logger.exception("Bridge initialization failed")
