"""Qt-free command semantics. The runtime sequences asynchronous Anki operations."""
import logging

BRIDGE_VERSION = "1.0.0"

logger = logging.getLogger("airanki_bridge")
logger.addHandler(logging.NullHandler())
logger.propagate = False


def state(mw):
    reviewer = getattr(mw, "reviewer", None)
    reviewing = getattr(mw, "state", None) == "review" and getattr(reviewer, "card", None) is not None
    side = getattr(reviewer, "state", "none") if reviewing else "none"
    return {"reviewing": reviewing, "side": side if side in ("question", "answer") else "none"}


def method(obj, *names):
    for name in names:
        candidate = getattr(obj, name, None)
        if callable(candidate):
            return candidate
    raise RuntimeError("Unsupported Anki API: " + "/".join(names))


def undo_available(mw):
    col = getattr(mw, "col", None)
    status = getattr(col, "undo_status", None)
    if callable(status):
        return bool(getattr(status(), "undo", None))
    # Older compatibility alias; never undo blindly when neither API exists.
    legacy = getattr(col, "undoName", None)
    return bool(legacy()) if callable(legacy) else False


def handle(cmd, mw):
    """Handle one request without importing Anki or Qt; catches all command errors.

    mw.undo() and _answerCard() are asynchronous in real Anki. `did` here records
    initiation; the socket runtime waits for completion hooks before acknowledging.
    It calls this function with count=1 for each real undo, checking the stack again
    after completion. A synchronous fake may exercise the whole count directly.
    """
    reply = {"id": cmd.get("id") if isinstance(cmd, dict) else None, "ok": True,
             "did": "none", "ease": None, "count": 0, "side": "none",
             "reviewing": False, "error": None, "version": BRIDGE_VERSION}
    try:
        if not isinstance(cmd, dict):
            raise ValueError("Request must be an object")
        if type(cmd.get("id")) is not int:
            raise ValueError("id must be an integer")
        name = cmd.get("cmd")
        if name not in ("right", "left", "reveal", "undo", "state", "ping"):
            raise ValueError("Unknown command")
        reply.update(state(mw))
        if name in ("state", "ping") or not reply["reviewing"]:
            return reply
        reviewer = mw.reviewer
        if name in ("right", "left", "reveal"):
            if reply["side"] == "question":
                method(reviewer, "_showAnswer", "show_answer")()
                reply["did"] = "showAnswer"
            elif reply["side"] == "answer" and name != "reveal":
                ease = 1 if name == "left" else cmd.get("ease", 4)
                if type(ease) is not int:
                    raise ValueError("ease must be an integer")
                buttons = method(mw.col.sched, "answerButtons", "answer_buttons")(reviewer.card)
                if not 1 <= buttons <= 4:
                    raise RuntimeError("Invalid scheduler answer-button count")
                ease = max(1, min(ease, buttons))
                method(reviewer, "_answerCard", "answer_card")(ease)
                # A hook may veto the answer. Don't falsely report a grade.
                if getattr(reviewer, "state", None) == "answer":
                    raise RuntimeError("Anki declined the grade")
                reply.update(did="graded", ease=ease)
        elif name == "undo":
            count = cmd.get("count", 1)
            if type(count) is not int:
                raise ValueError("count must be an integer")
            for _ in range(max(1, min(3, count))):
                if not undo_available(mw):
                    break
                method(mw, "undo", "onUndo")()
                reply["count"] += 1
            if reply["count"]:
                reply["did"] = "undone"
        reply.update(state(mw))
    except Exception as exc:
        logger.exception("Bridge command failed")
        reply.update(ok=False, error=str(exc))
    return reply


def flash_style(result):
    """Map a bridge reply to the reviewer flash style, or None when nothing happened."""
    if not result or not result.get("ok"):
        return None
    did = result.get("did")
    if did == "showAnswer":
        return "reveal"
    if did == "undone":
        return "undo"
    if did == "graded":
        return {1: "again", 2: "hard", 3: "good", 4: "easy"}.get(result.get("ease"))
    return None
