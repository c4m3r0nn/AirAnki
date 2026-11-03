import sys
import json
import unittest
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import airanki_bridge
from airanki_bridge.commands import BRIDGE_VERSION, handle
from airanki_bridge.runner import CommandRunner


class FakeMW:
    def __init__(self, side="question", buttons=4, entries=3, asynchronous=False):
        self.state = "review"
        self.calls = []
        self.entries = entries
        self.asynchronous = asynchronous
        self.reviewer = NS(state=side, card=object(), _showAnswer=self.show, _answerCard=self.answer)
        self.col = NS(sched=NS(answerButtons=lambda card: buttons), undo_status=lambda: NS(undo="Review" if self.entries else ""))

    def show(self):
        self.calls.append("show")
        self.reviewer.state = "answer"

    def answer(self, ease):
        self.calls.append(("grade", ease))
        self.reviewer.state = "transition" if self.asynchronous else "question"

    def undo(self):
        self.calls.append("undo")
        if not self.asynchronous:
            self.entries -= 1


class BridgeTests(unittest.TestCase):
    def test_version_in_command_replies_and_manifest(self):
        manifest = Path(__file__).resolve().parents[1] / "airanki_bridge" / "manifest.json"
        self.assertEqual(json.loads(manifest.read_text())["human_version"], BRIDGE_VERSION)
        for cmd in ("right", "left", "reveal", "undo", "state", "ping", "invalid"):
            self.assertEqual(self.call(FakeMW(), cmd)["version"], BRIDGE_VERSION)
        for request in (None, [], {}, dict(id=1, cmd="undo", count="invalid")):
            self.assertEqual(handle(request, FakeMW())["version"], BRIDGE_VERSION)

    def test_version_in_busy_and_timeout_replies(self):
        replies = []
        runner = CommandRunner(FakeMW("answer", asynchronous=True), lambda fn: fn())
        runner.dispatch(dict(id=1, cmd="right"), replies.append)
        runner.dispatch(dict(id=2, cmd="state"), replies.append)
        runner.timeout(runner.serial)
        self.assertEqual(len(replies), 2)
        for reply in replies:
            self.assertFalse(reply["ok"])
            self.assertEqual(reply["version"], BRIDGE_VERSION)

    def test_version_in_socket_parse_errors(self):
        hooks = NS(**{name: [] for name in ("main_window_did_init", "profile_did_open",
                   "profile_will_close", "reviewer_did_answer_card", "state_did_undo")})
        qt = NS(QLocalServer=object, QTimer=object)
        with patch.dict(sys.modules, {"aqt": NS(mw=None, gui_hooks=hooks), "aqt.qt": qt}):
            airanki_bridge._install()
            server = hooks.main_window_did_init[0].__self__
            for line in (b"{broken\n", b"[]\n"):
                class Socket:
                    def readAll(self): return line
                    def write(self, data): self.reply = json.loads(data)
                    def flush(self): pass
                socket = Socket()
                server.clients[socket] = bytearray()
                server.read(socket)
                self.assertFalse(socket.reply["ok"])
                self.assertEqual(socket.reply["version"], BRIDGE_VERSION)

    def call(self, mw, cmd, **kwargs):
        return handle(dict(id=7, cmd=cmd, **kwargs), mw)

    def test_question_reveals_only(self):
        for cmd in ("right", "left", "reveal"):
            mw = FakeMW()
            r = self.call(mw, cmd)
            self.assertEqual(mw.calls, ["show"])
            self.assertEqual((r["did"], r["side"], r["id"]), ("showAnswer", "answer", 7))

    def test_reveal_on_answer_is_noop(self):
        mw = FakeMW("answer")
        r = self.call(mw, "reveal")
        self.assertEqual(mw.calls, [])
        self.assertEqual((r["did"], r["side"], r["ok"]), ("none", "answer", True))

    def test_answer_defaults_left_and_clamps(self):
        for cmd, ease, buttons, expected in (("right", 4, 4, 4), ("right", 4, 3, 3), ("right", -1, 4, 1), ("left", 4, 4, 1)):
            mw = FakeMW("answer", buttons=buttons)
            r = self.call(mw, cmd, ease=ease)
            self.assertEqual(mw.calls, [("grade", expected)])
            self.assertEqual(r["ease"], expected)
        self.assertEqual(self.call(FakeMW("answer"), "right")["ease"], 4)

    def test_outside_review_and_missing_card(self):
        for missing in (False, True):
            mw = FakeMW()
            if missing: mw.reviewer.card = None
            else: mw.state = "deckBrowser"
            for cmd in ("right", "left", "reveal", "undo", "state", "ping"):
                r = self.call(mw, cmd)
                self.assertEqual((r["did"], r["reviewing"], r["side"]), ("none", False, "none"))
            self.assertEqual(mw.calls, [])

    def test_undo_count_empty_stack_and_cap(self):
        for count, entries, done in ((2, 3, 2), (3, 1, 1), (9, 8, 3), (1, 0, 0)):
            mw = FakeMW(entries=entries)
            r = self.call(mw, "undo", count=count)
            self.assertEqual(r["count"], done)
            self.assertEqual(len(mw.calls), done)

    def test_state_ping_transition_and_invalid(self):
        mw = FakeMW("transition")
        for cmd in ("state", "ping", "right"):
            self.assertEqual(self.call(mw, cmd)["did"], "none")
        for request in (None, [], {}, dict(id=1, cmd="bad"), dict(id=True, cmd="right")):
            self.assertFalse(handle(request, mw)["ok"])
        self.assertEqual(mw.calls, [])

    def test_errors_and_veto_are_replies(self):
        mw = FakeMW("answer")
        mw.reviewer._answerCard = lambda ease: None
        self.assertFalse(self.call(mw, "right")["ok"])
        mw.reviewer._answerCard = None
        self.assertFalse(self.call(mw, "right")["ok"])
        self.assertFalse(self.call(mw, "undo", count="2")["ok"])

    def test_guarded_aliases(self):
        mw = FakeMW("answer")
        mw.col.sched.answer_buttons = mw.col.sched.answerButtons
        del mw.col.sched.answerButtons
        mw.reviewer.answer_card = mw.reviewer._answerCard
        del mw.reviewer._answerCard
        self.assertTrue(self.call(mw, "right")["ok"])
        mw.col.undoName = lambda: "Review"
        del mw.col.undo_status
        mw.onUndo = mw.undo
        mw.undo = None
        self.assertEqual(self.call(mw, "undo")["count"], 1)

    def test_async_undo_is_sequential_and_checks_stack_again(self):
        mw = FakeMW(entries=2, asynchronous=True)
        deferred, replies = [], []
        runner = CommandRunner(mw, deferred.append)
        runner.dispatch(dict(id=1, cmd="undo", count=3), replies.append)
        self.assertEqual(mw.calls, ["undo"])
        self.assertEqual(replies, [])
        for _ in range(2):
            mw.entries -= 1
            runner.completed("undo")
            deferred.pop(0)()
        self.assertEqual(mw.calls, ["undo", "undo"])
        self.assertEqual(replies[0]["count"], 2)

    def test_timeout_never_replays_or_continues_undo(self):
        mw = FakeMW(asynchronous=True)
        deferred, replies = [], []
        runner = CommandRunner(mw, deferred.append)
        runner.dispatch(dict(id=1, cmd="undo", count=2), replies.append)
        runner.timeout(1)
        runner.dispatch(dict(id=2, cmd="right"), replies.append)
        self.assertEqual(len(replies), 2)
        self.assertTrue(all(not r["ok"] for r in replies))
        runner.completed("undo"); deferred.pop(0)()
        self.assertEqual(mw.calls, ["undo"])
        self.assertIsNone(runner.pending)

    def test_grade_reply_waits_for_commit(self):
        mw = FakeMW("answer", asynchronous=True)
        deferred, replies = [], []
        runner = CommandRunner(mw, deferred.append)
        runner.dispatch(dict(id=1, cmd="right"), replies.append)
        self.assertEqual(replies, [])
        mw.reviewer.state = "question"
        runner.completed("grade"); deferred.pop(0)()
        self.assertEqual((replies[0]["did"], replies[0]["side"]), ("graded", "question"))



class FlashTests(unittest.TestCase):
    def test_flash_once_per_action_with_grade_colour(self):
        seen = []
        mw = FakeMW(side="question")
        runner = CommandRunner(mw, lambda fn: fn(), seen.append)
        runner.dispatch(dict(id=1, cmd="left"), lambda r: None)
        runner.dispatch(dict(id=2, cmd="left"), lambda r: None)
        runner.completed("grade")
        runner.dispatch(dict(id=3, cmd="undo", count=2), lambda r: None)
        runner.completed("undo"); runner.completed("undo")
        runner.dispatch(dict(id=4, cmd="state"), lambda r: None)
        self.assertEqual(seen, ["reveal", "again", "undo"])

    def test_right_flash_follows_requested_ease(self):
        seen = []
        runner = CommandRunner(FakeMW(side="answer"), lambda fn: fn(), seen.append)
        runner.dispatch(dict(id=1, cmd="right", ease=3), lambda r: None)
        self.assertEqual(seen, ["good"])

if __name__ == "__main__":
    unittest.main()
