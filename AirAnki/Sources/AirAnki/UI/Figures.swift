import SwiftUI

/// The confirmation pop: grows in with a slight overshoot, holds, then fades, trailing one ripple.
/// `progress` runs 0…1 over the whole pop; mirrors flash.py.
struct PopBadge: View {
    var style: ActionStyle
    var progress: Double
    var diameter: CGFloat = 44

    var body: some View {
        let t = min(max(progress, 0), 1)
        let (scale, alpha) = Self.curve(t)
        let ripple = min(1, t / 0.7)
        ZStack {
            Circle()
                .stroke(style.color.opacity(0.45 * (1 - ripple) * alpha), lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .scaleEffect(1 + 0.75 * sin(ripple * .pi / 2))
            if style == .reveal {
                Circle().fill(.white)
                    .overlay(Circle().strokeBorder(style.color, lineWidth: 2.5))
                    .frame(width: diameter * 0.78, height: diameter * 0.78)
                    .overlay(Image(systemName: style.symbol)
                        .font(.system(size: diameter * 0.3, weight: .bold)).foregroundStyle(style.color))
                    .scaleEffect(scale)
            } else {
                Circle().fill(style.color.gradient)
                    .frame(width: diameter, height: diameter)
                    .overlay(Image(systemName: style.symbol)
                        .font(.system(size: diameter * 0.4, weight: .heavy)).foregroundStyle(.white))
                    .shadow(color: style.color.opacity(0.4), radius: 6, y: 3)
                    .scaleEffect(scale)
            }
        }
        .opacity(alpha)
        .frame(width: diameter * 1.8, height: diameter * 1.8)
        .allowsHitTesting(false)
    }

    static func curve(_ t: Double) -> (scale: Double, alpha: Double) {
        if t < 0.22 {
            let x = t / 0.22, c = 1.9
            return (0.55 + 0.45 * (1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)), min(1, t / 0.12))
        }
        if t < 0.6 { return (1, 1) }
        let k = (t - 0.6) / 0.4
        return (1 - 0.08 * k, (1 - k) * (1 - k))
    }
}

/// One AirPod held stem-down. `tilt` is the flick (degrees, + = right); `twist` spins it about its stem.
struct PodFigure: View {
    var tilt: Double = 0
    var twist: Double = 0
    var streak: Double = 0  // −1…1: motion arcs on the side the flick travels toward
    var size: CGFloat = 96
    var tint: Color = .primary

    var body: some View {
        ZStack {
            // Trailing arcs behind the bud head, concentric with the pivot at the base of the stem.
            MotionArcs(tilt: tilt, side: streak >= 0 ? 1 : -1, pivotY: 0.92)
                .stroke(tint.opacity(0.4 * abs(streak)), style: StrokeStyle(lineWidth: max(1.5, size * 0.03), lineCap: .round))
                .frame(width: size, height: size)
            Image(systemName: "airpodpro.right")
                .resizable().scaledToFit()
                .fontWeight(.light)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .rotation3DEffect(.degrees(twist), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 0.92))
        }
    }
}

private struct MotionArcs: Shape {
    var tilt: Double
    var side: Double
    var pivotY: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pivot = CGPoint(x: rect.midX, y: rect.minY + rect.height * pivotY)
        for r in [0.62, 0.84] {
            let head = -90.0 + tilt
            let a = head - side * 16, b = head - side * 42
            p.addArc(center: pivot, radius: rect.height * r, startAngle: .degrees(min(a, b)), endAngle: .degrees(max(a, b)), clockwise: false)
        }
        return p
    }
}

/// Pure motion profiles shared by the demo, the gesture loops and calibration (seconds since gesture start).
enum Motion {
    static let flickLength = 0.5
    static let twistLength = 0.6

    /// Quick tilt out, snap back past centre, settle — like the real flicks AirAnki listens for.
    static func flick(_ s: Double, direction: Double) -> (tilt: Double, streak: Double) {
        guard s >= 0, s < flickLength else { return (0, 0) }
        let tilt: Double
        if s < 0.11 { tilt = 30 * easeOut(s / 0.11) }
        else if s < 0.26 { tilt = 30 - 38 * easeInOut((s - 0.11) / 0.15) }
        else { tilt = -8 * (1 - easeInOut((s - 0.26) / 0.24)) }
        let streak = s < 0.3 ? max(0, 1 - abs(s - 0.1) / 0.2) : 0
        return (tilt * direction, streak * direction)
    }

    static func twist(_ s: Double) -> Double {
        guard s >= 0, s < twistLength else { return 0 }
        return 62 * sin(s / twistLength * .pi * 4) * (1 - s / twistLength)
    }

    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }
    static func easeInOut(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}

/// A looping single-gesture demo: the AirPod performs it, then the result pops.
struct GestureLoop: View {
    var gesture: DemoGesture
    var style: ActionStyle
    var size: CGFloat = 54
    var period = 2.2
    var paused = false

    var body: some View {
        TimelineView(.animation(paused: paused)) { context in
            let s = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) - 0.35
            frame(s)
        }
    }

    private func pose(_ s: Double) -> (tilt: Double, twist: Double, streak: Double) {
        switch gesture {
        case .right: let m = Motion.flick(s, direction: 1); return (m.tilt, 0, m.streak)
        case .left: let m = Motion.flick(s, direction: -1); return (m.tilt, 0, m.streak)
        case .twist: return (0, Motion.twist(s), 0)
        }
    }

    private func frame(_ s: Double) -> some View {
        let (tilt, twist, streak) = pose(s)
        return ZStack(alignment: .bottomTrailing) {
            PodFigure(tilt: tilt, twist: twist, streak: streak, size: size, tint: .primary.opacity(0.85))
                .frame(width: size * 1.8, height: size * 1.4)
            PopBadge(style: style, progress: (s - 0.18) / 0.65, diameter: size * 0.42)
                .offset(x: size * 0.15, y: size * 0.1)
        }
    }
}
