"""Event-driven sequencing, kept Qt-free for asynchronous fake tests."""
from .commands import BRIDGE_VERSION, flash_style, handle, state


class CommandRunner:
    def __init__(self, mw, defer, on_action=None):
        self.mw, self.defer = mw, defer
        # Called once per command that changed the reviewer, with the flash style.
        self.on_action = on_action
        self.pending = None
        self.serial = 0

    def dispatch(self, request, reply):
        if self.pending:
            reply(dict(id=request.get("id"), ok=False, did="none", ease=None, version=BRIDGE_VERSION,
                       count=0, error="Bridge busy; action not sent", **state(self.mw)))
            return
        self.serial += 1
        pending = dict(request=request, reply=reply, result=None, remaining=1,
                       done=0, kind=None, acknowledged=False, serial=self.serial)
        self.pending = pending
        if request.get("cmd") == "undo" and type(request.get("count", 1)) is int:
            pending["remaining"] = max(1, min(3, request.get("count", 1)))
        self._step()

    def _step(self):
        p = self.pending
        if not p:
            return
        request = dict(p["request"])
        if request.get("cmd") == "undo":
            request["count"] = 1
        # Hooks execute after the initiating API call returns in real Anki.
        result = handle(request, self.mw)
        p["result"] = result
        style = flash_style(result)
        if style and self.on_action and not p["done"]:
            try:
                self.on_action(style)
            except Exception:
                pass
        p["kind"] = {"graded": "grade", "undone": "undo"}.get(result["did"])
        if not result["ok"] or p["kind"] is None:
            self._finish()

    def completed(self, kind):
        p = self.pending
        if p and p["kind"] == kind:
            p["kind"] = None
            if kind == "undo":
                p["done"] += 1
                p["remaining"] -= 1
            # Leave Anki's hook stack before starting another operation.
            self.defer(lambda: self._after_completion(p, kind))

    def _after_completion(self, p, kind):
        if self.pending is not p:
            return
        if kind == "undo" and p["remaining"] > 0 and not p["acknowledged"]:
            self._step()
        else:
            self._finish()

    def _finish(self):
        p = self.pending
        if not p:
            return
        self.pending = None
        result = p["result"]
        if p["request"].get("cmd") == "undo":
            result.update(count=p["done"], did="undone" if p["done"] else "none")
        result.update(state(self.mw))
        if not p["acknowledged"]:
            p["reply"](result)

    def timeout(self, serial):
        p = self.pending
        if p and p["serial"] == serial and not p["acknowledged"]:
            p["acknowledged"] = True
            p["reply"](dict(id=p["request"].get("id"), ok=False, did="none", ease=None, version=BRIDGE_VERSION,
                            count=p["done"], error="Anki operation timed out; outcome uncertain, do not retry", **state(self.mw)))
            # Retain the lock until the completion hook. Never launch remaining undos.

    def cancel(self):
        self.pending = None
