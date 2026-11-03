"""A brief coloured pop over the reviewer confirming what AirAnki just did.

Painted by a mouse-transparent Qt overlay, so it survives the reviewer reloading
its web view after a grade or undo.
"""
import math

from aqt.qt import QColor, QPainter, QPainterPath, QPen, QPointF, QRectF, Qt, QVariantAnimation, QWidget

# (fill, glyph). Again is red, Good/Easy green, Undo grey; reveal is a quiet ring.
STYLES = {
    "again": ("#E5484D", "cross"),
    "hard": ("#F5A524", "dash"),
    "good": ("#30A46C", "check"),
    "easy": ("#30A46C", "check"),
    "undo": ("#8B8D98", "undo"),
    "reveal": (None, "eye"),
}
DIAMETER = 64.0
DURATION_MS = 560


def _ease_out_back(x):
    c = 1.9
    return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2


class Flash(QWidget):
    def __init__(self, mw):
        super().__init__(mw)
        self.mw = mw
        self.style = None
        self.progress = 1.0
        side = int(DIAMETER * 2)
        self.resize(side, side)
        self.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        self.setAttribute(Qt.WidgetAttribute.WA_NoSystemBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.animation = QVariantAnimation(self)
        self.animation.setStartValue(0.0)
        self.animation.setEndValue(1.0)
        self.animation.setDuration(DURATION_MS)
        self.animation.valueChanged.connect(self._tick)
        self.animation.finished.connect(self.hide)
        self.hide()

    def show_style(self, style):
        if style not in STYLES:
            return
        self.style = style
        self._place()
        self.raise_()
        self.show()
        self.animation.stop()
        self.animation.start()

    def _place(self):
        web = getattr(self.mw, "web", None)
        if web is None or not web.isVisible():
            area = self.mw.rect()
            origin = area.topLeft()
        else:
            area = web.rect()
            origin = web.mapTo(self.mw, area.topLeft())
        x = origin.x() + area.width() / 2 - self.width() / 2
        # Low and centred: under the card text, just above the answer buttons.
        y = origin.y() + area.height() - self.height() / 2 - DIAMETER * 0.9
        self.move(int(x), int(max(origin.y(), y)))

    def _tick(self, value):
        self.progress = float(value)
        self.update()

    def paintEvent(self, event):
        if self.style is None:
            return
        fill, glyph = STYLES[self.style]
        t = self.progress
        # Pop in (0–22%), settle, hold, then fade (60–100%).
        if t < 0.22:
            scale = 0.55 + 0.45 * _ease_out_back(t / 0.22)
            alpha = min(1.0, t / 0.12)
        elif t < 0.60:
            scale, alpha = 1.0, 1.0
        else:
            k = (t - 0.60) / 0.40
            scale = 1.0 - 0.08 * k
            alpha = (1 - k) ** 2
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        c = QPointF(self.width() / 2, self.height() / 2)
        r = DIAMETER / 2 * scale
        accent = QColor(fill or "#FFFFFF")

        # Ripple ring expanding outward once.
        ripple = min(1.0, t / 0.7)
        ring = QColor(accent if fill else QColor("#7C8CFF"))
        ring.setAlphaF(0.45 * (1 - ripple) * alpha)
        p.setPen(QPen(ring, 2.0))
        p.setBrush(Qt.BrushStyle.NoBrush)
        rr = DIAMETER / 2 * (1.0 + 0.75 * math.sin(ripple * math.pi / 2))
        p.drawEllipse(c, rr, rr)

        # Soft shadow (none under the light reveal ring).
        for i, a in enumerate((0.10, 0.06, 0.03)):
            shadow = QColor(0, 0, 0)
            shadow.setAlphaF(a * alpha * (1.0 if fill else 0.4))
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(shadow)
            p.drawEllipse(QPointF(c.x(), c.y() + 3 + i), r + 1 + i * 2, r + 1 + i * 2)

        if fill:
            body = QColor(fill)
            body.setAlphaF(alpha)
            p.setBrush(body)
            p.setPen(Qt.PenStyle.NoPen)
            p.drawEllipse(c, r, r)
            ink = QColor(255, 255, 255)
        else:
            body = QColor(255, 255, 255)
            body.setAlphaF(0.92 * alpha)
            p.setBrush(body)
            edge = QColor("#7C8CFF")
            edge.setAlphaF(alpha)
            p.setPen(QPen(edge, 2.5))
            r *= 0.78
            p.drawEllipse(c, r, r)
            ink = QColor("#5B6BEA")
        ink.setAlphaF(alpha)
        self._glyph(p, glyph, c, r, ink)
        p.end()

    def _glyph(self, p, glyph, c, r, ink):
        pen = QPen(ink, max(2.0, r * 0.16))
        pen.setCapStyle(Qt.PenCapStyle.RoundCap)
        pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
        p.setPen(pen)
        p.setBrush(Qt.BrushStyle.NoBrush)
        s = r * 0.42
        path = QPainterPath()
        if glyph == "check":
            path.moveTo(c.x() - s, c.y() + s * 0.05)
            path.lineTo(c.x() - s * 0.25, c.y() + s * 0.75)
            path.lineTo(c.x() + s, c.y() - s * 0.65)
        elif glyph == "cross":
            k = s * 0.78
            path.moveTo(c.x() - k, c.y() - k); path.lineTo(c.x() + k, c.y() + k)
            path.moveTo(c.x() + k, c.y() - k); path.lineTo(c.x() - k, c.y() + k)
        elif glyph == "dash":
            path.moveTo(c.x() - s, c.y()); path.lineTo(c.x() + s, c.y())
        elif glyph == "undo":
            # Clockwise arc over the top; the arrowhead at its start points back (counter-clockwise).
            start = 165.0
            box = QRectF(c.x() - s, c.y() - s, 2 * s, 2 * s)
            path.arcMoveTo(box, start)
            path.arcTo(box, start, -255)
            a = math.radians(start)
            tip = QPointF(c.x() + s * math.cos(a), c.y() - s * math.sin(a))
            dx, dy = -math.sin(a), -math.cos(a)  # visual counter-clockwise tangent
            arm = s * 0.62
            head = QPainterPath()
            for turn in (math.radians(140), math.radians(-140)):
                ex = dx * math.cos(turn) - dy * math.sin(turn)
                ey = dx * math.sin(turn) + dy * math.cos(turn)
                head.moveTo(tip)
                head.lineTo(tip.x() + ex * arm, tip.y() + ey * arm)
            p.drawPath(head)
        elif glyph == "eye":
            w, h = s * 1.15, s * 0.62
            path.moveTo(c.x() - w, c.y())
            path.quadTo(c.x(), c.y() - h * 1.6, c.x() + w, c.y())
            path.quadTo(c.x(), c.y() + h * 1.6, c.x() - w, c.y())
            p.drawPath(path)
            p.setBrush(ink)
            p.setPen(Qt.PenStyle.NoPen)
            p.drawEllipse(c, s * 0.3, s * 0.3)
            return
        p.drawPath(path)
