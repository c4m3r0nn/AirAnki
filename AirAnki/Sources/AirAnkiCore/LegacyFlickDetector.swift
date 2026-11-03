import Foundation

/// AirClicker's gravity-projected yaw detector, adapted for handheld 25 Hz streams.
/// See THIRD_PARTY_NOTICES.md for the upstream MIT notice.
public final class LegacyFlickDetector {
    // AirClicker thresholds. Angles are deliberately NOT sensitivity-scaled: they
    // distinguish a deliberate flick from its wind-up.
    public static let peakRate = 6.5              // rad/s, left flick
    public static let rightPeakRate = 5.5         // rad/s, right flick
    public static let minAngle = 75.0 * .pi / 180 // radians, immediate candidate
    public static let shortAngle = 55.0 * .pi / 180 // radians, candidate after wind-up wait
    // Held-bud recordings contain brief sharp wrist impulses well below
    // 55°. Admit these only as short candidates, with the same wind-up wait.
    public static let impulseAngle = 15.0 * .pi / 180 // radians; never scale the measured angle
    public static let impulseDuration = 0.16     // seconds between first/last burst samples; excludes sustained turns
    public static let windupWait = 0.35          // seconds to rule out a pull-back
    public static let burstStart = 2.0           // rad/s, leave rest
    public static let burstEnd = 1.5             // rad/s, return to rest (hysteresis)
    public static let horizontalShare = 0.5      // yaw / total rotation at fast samples
    public static let repeatGap = 0.35           // seconds between same-direction candidates
    public static let returnGap = 0.6            // seconds; opposite turns starting here are returns
    public static let slowSampleInterval = 0.030 // seconds; above this, one fast sample suffices
    public static let fastSampleCount = 2        // consecutive fast samples at ~50 Hz
    public static let intervalWindow = 31        // intervals in the rolling median
    public static let initialInterval = 0.020    // seconds until an interval is measured
    public static let maxSampleGap = 0.20        // seconds; discard stale work across a stream stall
    public static let shakeWindow = 1.0          // seconds from first burst start to third peak
    public static let shakePeakRate = 4.0        // rad/s, sensitivity-scaled
    public static let shakeStrokeCount = 3       // alternating yaw bursts
    public static let shakeHold = 0.45           // seconds every flick waits for a possible shake
    public static let shakeCooldown = 0.8        // seconds ignoring all motion after Undo

    public let sensitivity: FlickSensitivity
    public let reversed: Bool
    public var onTrace: ((FlickTrace) -> Void)?
    public private(set) var sampleInterval = initialInterval

    private struct Burst {
        let right: Bool
        let start: TimeInterval
        var lastTime: TimeInterval
        var angle = 0.0
        var peakYaw = 0.0
        var fastSamples = 0
        var sharp = false
        var fired = false
        var shakeCounted = false
        var reason = "not sharp enough"
    }
    private struct Candidate {
        let right: Bool
        let start: TimeInterval
        let end: TimeInterval
        let angle: Double
        let peak: Double
        let reason: String
    }
    private struct Stroke {
        let right: Bool
        let start: TimeInterval
        let peak: Double
        let angle: Double
    }
    private var burst: Burst?
    private var pending: Candidate?
    private var held: [Candidate] = []
    private var strokes: [Stroke] = []
    private var intervals: [TimeInterval] = []
    private var lastTime: TimeInterval?
    private var lastFire: (time: TimeInterval, right: Bool)?
    private var ignoreUntil = -TimeInterval.infinity

    public init(sensitivity: FlickSensitivity = .medium, reversed: Bool = false) {
        self.sensitivity = sensitivity
        self.reversed = reversed
    }

    /// Stop/restart, disconnects and setting changes discard all unfinished gestures.
    public func reset() {
        burst = nil; pending = nil; held.removeAll(); strokes.removeAll()
        intervals.removeAll(); lastTime = nil; lastFire = nil
        ignoreUntil = -.infinity
        sampleInterval = Self.initialInterval
    }

    public func process(_ sample: MotionSample) -> [FlickDetection] {
        let now = sample.t, r = sample.rotationRate, g = sample.gravity
        guard [now, r.x, r.y, r.z, g.x, g.y, g.z].allSatisfy({ $0.isFinite }) else { return [] }
        var dt = 0.0
        if let previous = lastTime {
            guard now > previous else { return [] }
            dt = now - previous
            if dt > Self.maxSampleGap {
                for candidate in held + [pending].compactMap({ $0 }) {
                    trace(candidate, at: now, event: nil, reason: "stream gap; discarded stale flick")
                }
                // A missing sample cancels delayed work, but cannot shorten the
                // post-shake cooldown or turn a recent return swing into a flick.
                let cooldown = ignoreUntil, previousFire = lastFire
                reset()
                ignoreUntil = cooldown
                lastFire = previousFire
                dt = 0
            } else {
                intervals.append(dt)
                if intervals.count > Self.intervalWindow { intervals.removeFirst() }
                let sorted = intervals.sorted()
                let middle = sorted.count / 2
                sampleInterval = sorted.count.isMultiple(of: 2)
                    ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            }
        }
        lastTime = now
        guard now >= ignoreUntil else { return [] }
        let yaw = r.x * g.x + r.y * g.y + r.z * g.z
        let total = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
        if let current = burst, abs(yaw) < Self.burstEnd || (yaw > 0) != current.right {
            endBurst(at: now)
        }
        if burst == nil, abs(yaw) > Self.burstStart {
            burst = Burst(right: yaw > 0, start: now, lastTime: now - dt)
        }
        if var current = burst {
            // Rectangle integration with actual dt, including the first sample's
            // interval. At 25 Hz an entire sharp impulse may occupy one sample.
            current.angle += yaw * (now - current.lastTime)
            current.lastTime = now
            if abs(yaw) > abs(current.peakYaw) { current.peakYaw = yaw }
            if !current.shakeCounted, abs(yaw) > Self.shakePeakRate * sensitivity.scale {
                current.shakeCounted = true
                strokes.removeAll { now - $0.start > Self.shakeWindow }
                if strokes.last?.right == current.right { strokes.removeAll() }
                strokes.append(Stroke(right: current.right, start: current.start,
                                      peak: current.peakYaw, angle: current.angle))
                if strokes.count >= Self.shakeStrokeCount {
                    for candidate in held + [pending].compactMap({ $0 }) {
                        trace(candidate, at: now, event: nil, reason: "cancelled by shake")
                    }
                    onTrace?(FlickTrace(t: now, event: .shake, reason: "three alternating yaw bursts",
                                       peakYaw: strokes.max(by: { abs($0.peak) < abs($1.peak) })!.peak,
                                       angle: strokes.reduce(0) { $0 + abs($1.angle) }))
                    let shakeOnset = strokes.first!.start
                    burst = nil; pending = nil; held.removeAll(); strokes.removeAll()
                    lastFire = nil
                    ignoreUntil = now + Self.shakeCooldown
                    return [FlickDetection(t: now, event: .shake, onset: shakeOnset)]
                }
            }
            // Keep peak/angle diagnostics for completed shake strokes up to date.
            if current.shakeCounted, strokes.last?.start == current.start {
                strokes[strokes.count - 1] = Stroke(right: current.right, start: current.start,
                                                   peak: current.peakYaw, angle: current.angle)
            }
            if !current.fired {
                let threshold = (current.right ? Self.rightPeakRate : Self.peakRate) * sensitivity.scale
                if abs(yaw) > threshold, abs(yaw) >= Self.horizontalShare * total {
                    current.fastSamples += 1
                    let required = sampleInterval > Self.slowSampleInterval ? 1 : Self.fastSampleCount
                    if current.fastSamples >= required { current.sharp = true }
                } else {
                    current.fastSamples = 0
                    if abs(yaw) > threshold, !current.sharp { current.reason = "not horizontal" }
                }
                if current.sharp {
                    current.reason = "too short (wind-up)"
                    if abs(current.angle) > Self.minAngle {
                        if let reason = blocked(right: current.right, start: current.start, now: now) {
                            current.reason = reason
                        } else {
                            current.fired = true
                            hold(candidate(current, reason: "full angle"), at: now)
                        }
                    }
                }
            }
            burst = current
        }
        // Resolve after updating sharpness, so a reversing sample on the deadline
        // cancels its wind-up before that wind-up can escape the hold.
        resolvePending(at: now)
        var events: [FlickDetection] = []
        while let candidate = held.first, now - candidate.end >= Self.shakeHold {
            held.removeFirst()
            let event: FlickEvent = candidate.right != reversed ? .right : .left
            trace(candidate, at: now, event: event, reason: candidate.reason + "; shake hold complete")
            events.append(FlickDetection(t: now, event: event, onset: candidate.start, peakTime: candidate.end))
        }
        return events
    }

    private func candidate(_ burst: Burst, reason: String) -> Candidate {
        Candidate(right: burst.right, start: burst.start, end: burst.lastTime,
                  angle: burst.angle, peak: burst.peakYaw, reason: reason)
    }

    private func blocked(right: Bool, start: TimeInterval, now: TimeInterval) -> String? {
        guard let lastFire else { return nil }
        if right != lastFire.right, start - lastFire.time < Self.returnGap { return "return swing" }
        if right == lastFire.right, now - lastFire.time < Self.repeatGap { return "too soon" }
        return nil
    }

    private func hold(_ candidate: Candidate, at now: TimeInterval) {
        // Start return/repeat suppression at qualification, NOT at delayed delivery.
        lastFire = (now, candidate.right)
        held.append(Candidate(right: candidate.right, start: candidate.start, end: now,
                              angle: candidate.angle, peak: candidate.peak, reason: candidate.reason))
    }

    private func endBurst(at now: TimeInterval) {
        guard let current = burst else { return }
        burst = nil
        guard !current.fired else { return }
        let rejection = blocked(right: current.right, start: current.start, now: current.lastTime)
        let compactImpulse = abs(current.angle) >= Self.impulseAngle
            && current.lastTime - current.start <= Self.impulseDuration
        if current.sharp, (abs(current.angle) >= Self.shortAngle || compactImpulse), abs(current.angle) <= Self.minAngle,
           rejection == nil {
            if let pending { trace(pending, at: now, event: nil, reason: "superseded short turn") }
            pending = candidate(current, reason: abs(current.angle) >= Self.shortAngle
                                ? "short angle after wind-up wait" : "compact impulse after wind-up wait")
        } else {
            trace(candidate(current, reason: current.reason), at: now, event: nil,
                  reason: rejection ?? current.reason)
        }
    }

    private func resolvePending(at now: TimeInterval) {
        guard let waiting = pending else { return }
        if let current = burst, current.right != waiting.right, current.sharp {
            pending = nil
            trace(waiting, at: now, event: nil, reason: "pull back before a flick")
            return
        }
        guard now - waiting.end >= Self.windupWait else { return }
        pending = nil
        if let reason = blocked(right: waiting.right, start: waiting.start, now: now) {
            trace(waiting, at: now, event: nil, reason: reason)
        } else {
            hold(waiting, at: now)
        }
    }

    private func trace(_ candidate: Candidate, at now: TimeInterval, event: FlickEvent?, reason: String) {
        onTrace?(FlickTrace(t: now, event: event, reason: reason, peakYaw: candidate.peak, angle: candidate.angle))
    }
}
