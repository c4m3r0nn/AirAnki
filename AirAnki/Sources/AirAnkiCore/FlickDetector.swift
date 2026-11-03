import Foundation

public struct Vector3: Codable, Equatable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public init(_ v: (x: Double, y: Double, z: Double)) { self.init(v.x, v.y, v.z) }
    public var magnitude: Double { sqrt(dot(self)) }
    public var unit: Vector3 { magnitude > 1e-9 ? self * (1 / magnitude) : .init(0, 0, 0) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public func dot(_ v: Vector3) -> Double { x * v.x + y * v.y + z * v.z }
    public static func + (a: Vector3, b: Vector3) -> Vector3 { .init(a.x+b.x, a.y+b.y, a.z+b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { .init(a.x-b.x, a.y-b.y, a.z-b.z) }
    public static func * (a: Vector3, b: Double) -> Vector3 { .init(a.x*b, a.y*b, a.z*b) }
}

public struct FlickSettings: Equatable, Sendable {
    public var quietTime: Double
    public var onset: Double
    public var peakMin: Double
    public var shakeLobe: Double
    public var shakeWindow: Double
    public static let quiet = 3.0
    public static let featureTime = 0.08
    public static let margin = 0.35
    public static let refractory = 0.22
    public static let shakeCooldown = 0.60
    public init(quietTime: Double = 0.15, onset: Double = 3.5, peakMin: Double = 5.0,
                shakeLobe: Double = 2.0, shakeWindow: Double = 0.80) {
        self.quietTime = quietTime; self.onset = onset; self.peakMin = peakMin
        self.shakeLobe = shakeLobe; self.shakeWindow = shakeWindow
    }
    public var isValid: Bool {
        quietTime.isFinite && (0.15...0.30).contains(quietTime) && onset.isFinite && onset > Self.quiet
            && peakMin.isFinite && peakMin >= 5 && shakeLobe.isFinite && shakeLobe > 0
            && shakeWindow.isFinite && (0.5...0.9).contains(shakeWindow)
    }
    public var description: String {
        String(format: "quiet=%.2f onset=%.1f peakMin=%.1f shakeLobe=%.1f window=%.2f",
               quietTime, onset, peakMin, shakeLobe, shakeWindow)
    }
}

public struct FlickStroke: Sendable {
    public let onset: Double
    public let decidedAt: Double
    public let peakTime: Double
    /// Integral in units of a 40 ms sample; exactly w0 + w1 + w2 at 25 Hz.
    public let sum: Vector3
    public let peak: Double
    public init(onset: Double, decidedAt: Double, peakTime: Double, sum: Vector3, peak: Double) {
        self.onset = onset; self.decidedAt = decidedAt; self.peakTime = peakTime; self.sum = sum; self.peak = peak
    }
}

public struct FlickCalibration: Codable, Equatable, Sendable {
    public let mR: Vector3
    public let mL: Vector3
    public let weakestPeak: Double
    public static let defaultsKey = "flickCalibrationV3"
    public var axis: Vector3 { (mR - mL).unit }
    public var mid: Double { (axis.dot(mR) + axis.dot(mL)) / 2 }
    public var half: Double { (axis.dot(mR) - axis.dot(mL)) / 2 }
    public var peakMin: Double { max(5, 0.65 * weakestPeak) }
    public var quality: String { String(format: "half %.1f", half) }

    public init(right: [FlickStroke], left: [FlickStroke]) throws {
        guard !right.isEmpty, !left.isEmpty else { throw AnkiError.message("Capture both directions first.") }
        let strokes = right + left
        guard strokes.allSatisfy({ $0.sum.isFinite && $0.peak.isFinite && $0.peak >= 5 }) else {
            throw AnkiError.message("Flick a bit sharper; captures need a peak of at least 5 rad/s.")
        }
        func mean(_ strokes: [FlickStroke]) -> Vector3 {
            strokes.reduce(Vector3(0, 0, 0)) { $0 + $1.sum } * (1 / Double(strokes.count))
        }
        mR = mean(right); mL = mean(left); weakestPeak = strokes.map(\.peak).min()!
        guard isValid else {
            throw AnkiError.message("Quality \(quality) (need 5). Flick more distinctly and redo calibration.")
        }
    }
    public var isValid: Bool {
        mR.isFinite && mL.isFinite && weakestPeak.isFinite && weakestPeak >= 5 && half.isFinite && half >= 5
    }
    public func projection(_ stroke: FlickStroke) -> Double { axis.dot(stroke.sum) - mid }
    public static func load(from defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }
    public func save(to defaults: UserDefaults) {
        if isValid, let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// Foundation-only segmenter shared by calibration, replay and live recognition.
public final class StrokeSegmenter {
    public let settings: FlickSettings
    private var quietSince: Double?
    private var sawQuiet = false
    private var previous: MotionSample?
    private var start: Double?
    private var integral = Vector3(0, 0, 0)
    private var peak = 0.0
    private var peakTime = 0.0
    public init(settings: FlickSettings = .init()) { self.settings = settings }
    public func reset() {
        quietSince = nil; sawQuiet = false; previous = nil; start = nil; integral = .init(0, 0, 0)
    }
    public func process(_ sample: MotionSample) -> FlickStroke? {
        let v = Vector3(sample.rotationRate), now = sample.t, magnitude = v.magnitude
        guard now.isFinite, v.isFinite, Vector3(sample.gravity).isFinite else { return nil }
        if let previous {
            guard now > previous.t else { return nil }
            if now - previous.t > 0.20 { reset() }
        }
        defer { previous = sample }
        // As in the prototype, measure quiet from the last non-quiet sample.
        // A real quiet sample is required after startup, a gap or a reset.
        let armed = sawQuiet && now - (quietSince ?? now) >= settings.quietTime - 1e-6
        if magnitude >= FlickSettings.quiet { quietSince = now; sawQuiet = false }
        else { if quietSince == nil { quietSince = now }; sawQuiet = true }
        if start == nil, armed, magnitude > settings.onset {
            start = now; integral = v * 0.02; peak = magnitude; peakTime = now
            return nil
        }
        guard let start, let previous else { return nil }
        let end = start + FlickSettings.featureTime
        let time = min(now, end)
        let old = Vector3(previous.rotationRate)
        let fraction = min(1, max(0, (time - previous.t) / (now - previous.t)))
        let current = old + (v - old) * fraction
        // Trapezoids plus 20 ms endpoint cells reproduce the three-sample sum
        // at 25 Hz without shrinking the feature when the stream runs at 50 Hz.
        integral = integral + (old + current) * (max(0, time - previous.t) / 2)
        if current.magnitude > peak { peak = current.magnitude; peakTime = time }
        guard now >= end - 1e-6 else { return nil }
        let sum = (integral + current * 0.02) * 25
        self.start = nil
        return FlickStroke(onset: start, decidedAt: now, peakTime: peakTime, sum: sum, peak: peak)
    }
}

/// Six accepted captures per direction; weak captures do not advance the UI.
public final class FlickCalibrationSession {
    public private(set) var right: [FlickStroke] = [], left: [FlickStroke] = []
    public private(set) var calibration: FlickCalibration?
    public private(set) var prompt = "Flick RIGHT 6 times — 0/6"
    private let segmenter = StrokeSegmenter()
    private var captureAfter = -Double.infinity
    public init() {}
    /// Returns true only when there is new feedback to display.
    public func process(_ sample: MotionSample) -> Bool {
        guard calibration == nil, let stroke = segmenter.process(sample), stroke.onset >= captureAfter else { return false }
        captureAfter = stroke.decidedAt + 0.6
        let progress = { self.right.count < 6 ? "Flick RIGHT 6 times — \(self.right.count)/6" : "Flick LEFT 6 times — \(self.left.count)/6" }
        guard stroke.peak >= 5 else { prompt = "A bit sharper. " + progress(); return true }
        if right.count < 6 { right.append(stroke) } else { left.append(stroke) }
        if left.count == 6 {
            do {
                let value = try FlickCalibration(right: right, left: left)
                calibration = value; prompt = "Calibration complete — quality \(value.quality)"
            } catch {
                right = []; left = []; segmenter.reset()
                prompt = error.localizedDescription + " " + progress()
            }
        } else { prompt = progress() }
        return true
    }
}

/// Linear discriminant with speculative firing and projection-based shake cancellation.
public final class FlickDetector {
    public var onTrace: ((FlickTrace) -> Void)?
    public let calibration: FlickCalibration?
    public let sensitivity: FlickSensitivity
    public let reversed: Bool
    public let instant: Bool
    public let settings: FlickSettings
    private let segmenter: StrokeSegmenter
    private var lastTime: Double?
    private var lastFire: FlickDetection?
    private var held: (FlickDetection, FlickStroke, Double)?
    private var ignoreUntil = -Double.infinity
    private var shakeLobes: [(t: Double, positive: Bool)] = []
    private var lobeSign: Bool?
    private var lobeCounted = false
    private var speculative: FlickDetection?

    public init(calibration: FlickCalibration? = nil, sensitivity: FlickSensitivity = .medium,
                reversed: Bool = false, instant: Bool = true, settings: FlickSettings = .init()) {
        self.calibration = calibration; self.sensitivity = sensitivity; self.reversed = reversed
        self.instant = instant; self.settings = settings
        segmenter = StrokeSegmenter(settings: settings)
    }
    public func reset() {
        segmenter.reset(); lastTime = nil; lastFire = nil; held = nil; speculative = nil
        shakeLobes.removeAll(keepingCapacity: true); lobeSign = nil; lobeCounted = false; ignoreUntil = -.infinity
    }
    public func process(_ sample: MotionSample) -> [FlickDetection] {
        let now = sample.t, vector = Vector3(sample.rotationRate)
        guard now.isFinite, vector.isFinite, Vector3(sample.gravity).isFinite else { return [] }
        if let lastTime {
            guard now > lastTime else { return [] }
            if now - lastTime > 0.20 {
                segmenter.reset(); held = nil; speculative = nil; shakeLobes.removeAll(keepingCapacity: true)
                lobeSign = nil; lobeCounted = false
            }
        }
        lastTime = now
        guard now >= ignoreUntil, let calibration, calibration.isValid, settings.isValid else { return [] }
        shakeLobes.removeAll { now - $0.t > settings.shakeWindow + 1e-6 }
        let projection = vector.dot(calibration.axis)
        // Zero does not create an extra lobe. Each real sign lobe qualifies once.
        if projection != 0 {
            let sign = projection > 0
            if sign != lobeSign { lobeSign = sign; lobeCounted = false }
            if abs(projection) >= settings.shakeLobe * sensitivity.scale, !lobeCounted {
                lobeCounted = true
                if shakeLobes.last?.positive == sign { shakeLobes.removeAll(keepingCapacity: true) }
                shakeLobes.append((now, sign))
                // Three sign changes require FOUR qualifying lobes.
                if shakeLobes.count >= 4 {
                    let first = shakeLobes[0].t
                    let spec = speculative.flatMap { $0.onset >= first - 0.12 && now - $0.onset <= settings.shakeWindow + 0.12 ? $0.t : nil }
                    let event = FlickDetection(t: now, event: .shake, onset: first, peakTime: now, speculativeFlickAt: spec)
                    onTrace?(FlickTrace(t: now, event: .shake,
                        reason: spec == nil ? "three projection sign changes" : "shakeAfterSpeculative(flickWasAt: \(spec!))",
                        peakYaw: vector.magnitude, angle: 0, sR: projection, sL: -projection, latency: now - first))
                    held = nil; speculative = nil; shakeLobes.removeAll(keepingCapacity: true)
                    segmenter.reset(); lobeSign = nil; lobeCounted = false; ignoreUntil = now + FlickSettings.shakeCooldown
                    return [event]
                }
            }
        }
        var events: [FlickDetection] = []
        if let stroke = segmenter.process(sample) {
            let p = calibration.projection(stroke)
            let margin = FlickSettings.margin * calibration.half * sensitivity.scale
            var reason = stroke.peak < max(5, max(settings.peakMin, calibration.peakMin) * sensitivity.scale) ? "weak peak" : "ambiguous projection"
            if abs(p) > margin, stroke.peak >= max(5, max(settings.peakMin, calibration.peakMin) * sensitivity.scale) {
                let direction: FlickEvent = (p > 0) != reversed ? .right : .left
                let elapsed = lastFire.map { stroke.onset - $0.t } ?? .infinity
                if elapsed < FlickSettings.refractory { reason = "refractory" }
                else if held != nil { reason = "pending flick" }
                else if shakeLobes.count >= 2, let speculative,
                        speculative.onset >= shakeLobes[0].t - 0.12,
                        stroke.onset > speculative.onset,
                        now - speculative.onset <= settings.shakeWindow + 0.12 {
                    reason = "possible shake return; first stroke owns speculation"
                } else {
                    let detection = FlickDetection(t: now, event: direction, onset: stroke.onset, peakTime: stroke.peakTime)
                    lastFire = detection
                    if instant {
                        events.append(detection); speculative = detection
                        trace(stroke, at: now, event: direction, reason: "instant", p: p)
                    } else { held = (detection, stroke, p) }
                    reason = "accepted"
                }
            }
            if reason != "accepted" { trace(stroke, at: now, event: nil, reason: reason, p: p) }
        }
        if let pending = held, now - pending.0.t >= 0.3 - 1e-6 {
            held = nil
            let detection = FlickDetection(t: now, event: pending.0.event, onset: pending.0.onset, peakTime: pending.0.peakTime)
            events.append(detection); speculative = detection
            trace(pending.1, at: now, event: detection.event, reason: "300 ms hold complete", p: pending.2)
        }
        return events
    }
    private func trace(_ stroke: FlickStroke, at time: Double, event: FlickEvent?, reason: String, p: Double) {
        // Preserve the Lab CSV shape: sR is the centered linear score, sL its negative.
        onTrace?(FlickTrace(t: time, event: event, reason: reason, peakYaw: stroke.peak, angle: 0,
                           sR: p, sL: -p, latency: time - stroke.onset))
    }
}
