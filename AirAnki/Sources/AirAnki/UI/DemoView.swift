import SwiftUI

/// A looping storyboard of a real review: reveal, Easy, reveal, Again, then twist to undo the mistake.
/// Every frame is a pure function of time, so it renders identically live and in exported previews.
struct DemoView: View {
    var ease = 4
    var paused = false
    var body: some View {
        TimelineView(.animation(paused: paused)) { context in
            DemoFrameView(frame: DemoScript.frame(at: context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: DemoScript.period), ease: ease))
        }
    }
}

struct DemoCard: Equatable {
    var question: String
    var answer: String
}

struct DemoFrame {
    struct CardState { var card: DemoCard; var reveal: Double; var x: Double; var y: Double; var angle: Double; var opacity: Double }
    var tilt = 0.0, twist = 0.0, streak = 0.0
    var cards: [CardState] = []
    var pop: (ActionStyle, Double)?
    var caption: (gesture: String, result: String, style: ActionStyle, opacity: Double)?
    var opacity = 1.0
}

enum DemoScript {
    static let period = 12.4
    static let cards = [
        DemoCard(question: "Which nerve supplies the deltoid?", answer: "Axillary nerve (C5–C6)"),
        DemoCard(question: "Commonest cause of community-acquired pneumonia?", answer: "Streptococcus pneumoniae"),
        DemoCard(question: "First-line drug for absence seizures?", answer: "Ethosuximide"),
    ]

    private enum Kind { case flick(Double), twist }
    private struct Beat { var at: Double; var kind: Kind; var gesture: String; var result: ActionStyle }
    private static func beats(ease: Int) -> [Beat] {
        [Beat(at: 1.2, kind: .flick(1), gesture: "Flick either way", result: .reveal),
         Beat(at: 2.9, kind: .flick(1), gesture: "Flick right", result: ease == 3 ? .good : .easy),
         Beat(at: 4.9, kind: .flick(-1), gesture: "Flick either way", result: .reveal),
         Beat(at: 6.5, kind: .flick(-1), gesture: "Flick left", result: .again),
         Beat(at: 8.5, kind: .twist, gesture: "Twist", result: .undo)]
    }

    static func frame(at t: Double, ease: Int = 4) -> DemoFrame {
        var f = DemoFrame()
        for beat in beats(ease: ease) {
            let s = t - beat.at
            switch beat.kind {
            case .flick(let d):
                let m = Motion.flick(s, direction: d)
                if s >= 0, s < Motion.flickLength { f.tilt = m.tilt; f.streak = m.streak }
            case .twist:
                if s >= 0, s < Motion.twistLength { f.twist = Motion.twist(s) }
            }
            // The pop lands as the AirPod snaps back, which is when AirAnki really acts.
            let popStart = beat.at + 0.14
            if t >= popStart, t < popStart + 0.75 { f.pop = (beat.result, (t - popStart) / 0.75) }
            if s >= 0, s < 1.45 {
                let a = min(1, s / 0.15) * min(1, (1.45 - s) / 0.3)
                f.caption = (beat.gesture, beat.result.title, beat.result, a)
            }
        }

        // Card choreography.
        func enter(_ start: Double) -> (y: Double, o: Double) {
            let k = Motion.easeOut((t - start) / 0.4)
            return (12 * (1 - k), k)
        }
        func exit(_ start: Double, dx: Double, dy: Double = 0, spin: Double = 0) -> (x: Double, y: Double, a: Double, o: Double) {
            let k = Motion.easeInOut((t - start) / 0.45)
            return (dx * k, dy * k, spin * k, 1 - k)
        }
        func reveal(_ start: Double) -> Double { Motion.easeOut((t - start) / 0.3) }

        let c1 = cards[0], c2 = cards[1], c3 = cards[2]
        if t < 3.9 {
            let e = enter(0.1), x = exit(3.3, dx: 240, spin: 7)
            f.cards.append(.init(card: c1, reveal: reveal(1.34), x: x.x, y: e.y + x.y, angle: x.a, opacity: e.o * x.o))
        }
        if t >= 3.6, t < 7.5 {
            let e = enter(3.6), x = exit(6.9, dx: -240, spin: -7)
            f.cards.append(.init(card: c2, reveal: reveal(5.04), x: x.x, y: e.y, angle: x.a, opacity: e.o * x.o))
        }
        if t >= 7.2, t < 9.4 {
            let e = enter(7.2), x = exit(8.75, dx: 0, dy: 30)
            f.cards.append(.init(card: c3, reveal: 0, x: 0, y: e.y + x.y, angle: 0, opacity: e.o * x.o * (1 - 0.4 * min(1, max(0, (t - 8.75) / 0.2)))))
        }
        if t >= 8.85 {
            // Undo brings the mis-graded card back, answer still showing.
            let k = Motion.easeOut((t - 8.85) / 0.5)
            f.cards.append(.init(card: c2, reveal: 1, x: -240 * (1 - k), y: 0, angle: -7 * (1 - k), opacity: k))
        }
        f.opacity = t > period - 0.6 ? max(0, (period - t) / 0.6) : 1
        return f
    }
}

struct DemoFrameView: View {
    var frame: DemoFrame

    var body: some View {
        HStack(spacing: 28) {
            VStack(spacing: 14) {
                PodFigure(tilt: frame.tilt, twist: frame.twist, streak: frame.streak, size: 92,
                          tint: .primary.opacity(0.88))
                    .frame(width: 170, height: 130)
                caption.frame(height: 50)
            }
            .frame(width: 180)
            ZStack(alignment: .bottom) {
                ZStack {
                    ForEach(Array(frame.cards.enumerated()), id: \.offset) { _, state in
                        CardFace(state: state)
                    }
                }
                .frame(width: 270, height: 168)
                if let (style, progress) = frame.pop {
                    PopBadge(style: style, progress: progress, diameter: 40).offset(y: 36)
                }
            }
            .frame(width: 290, height: 210)
        }
        .opacity(frame.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Demo: flick either way to show the answer, flick right for Easy, flick left for Again, twist to undo.")
    }

    @ViewBuilder private var caption: some View {
        if let c = frame.caption {
            VStack(spacing: 5) {
                Text(c.gesture).font(Theme.heading(14)).foregroundStyle(.primary)
                HStack(spacing: 5) {
                    Image(systemName: c.style.symbol).font(.system(size: 9, weight: .heavy))
                    Text(c.result).font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(c.style.color))
            }
            .opacity(c.opacity)
            .scaleEffect(0.94 + 0.06 * c.opacity)
        } else {
            Color.clear
        }
    }
}

private struct CardFace: View {
    var state: DemoFrame.CardState
    var body: some View {
        VStack(spacing: 10) {
            Text(state.card.question)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Rectangle().fill(.primary.opacity(0.12)).frame(height: 1)
                .scaleEffect(x: state.reveal, anchor: .center)
                .opacity(state.reveal)
            Text(state.card.answer)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.accent)
                .opacity(state.reveal)
                .offset(y: 6 * (1 - state.reveal))
        }
        .padding(.horizontal, 20)
        .frame(width: 270, height: 168)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .rotationEffect(.degrees(state.angle), anchor: .bottom)
        .offset(x: state.x, y: state.y)
        .opacity(state.opacity)
    }
}
