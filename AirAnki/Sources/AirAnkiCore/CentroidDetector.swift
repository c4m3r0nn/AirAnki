import Foundation

public enum CentroidClass: String, Codable, CaseIterable, Sendable {
    case right, left, undo
    public var event: FlickEvent {
        switch self { case .right: return .right; case .left: return .left; case .undo: return .undo }
    }
}

public struct CentroidSettings: Equatable, Sendable {
    public var gateMultiplier = 0.55
    public var cosine = 0.70
    public var margin = 0.20
    public var adaptationRate = 0.15
    public init() {}
    public var isValid: Bool {
        gateMultiplier.isFinite && (0...1).contains(gateMultiplier) && cosine.isFinite && (0...1).contains(cosine)
            && margin.isFinite && (0...2).contains(margin) && adaptationRate.isFinite && (0...1).contains(adaptationRate)
    }
    public var description: String {
        String(format: "gate=%.2f cos=%.2f margin=%.2f adaptation=%.2f", gateMultiplier, cosine, margin, adaptationRate)
    }
}

public struct CentroidTemplate: Codable, Equatable, Sendable {
    public let direction: Vector3
    public let medianPeak: Double
    public init(strokes: [FlickStroke]) {
        direction = strokes.reduce(Vector3(0, 0, 0)) { $0 + $1.sum.unit }.unit
        let peaks = strokes.map(\.peak).sorted()
        medianPeak = peaks.isEmpty ? 0 : (peaks[(peaks.count - 1) / 2] + peaks[peaks.count / 2]) / 2
    }
    public var isValid: Bool { direction.isFinite && abs(direction.magnitude - 1) < 1e-6 && medianPeak.isFinite && medianPeak >= 3.5 }
}

public struct CentroidCalibration: Codable, Equatable, Sendable {
    public static let defaultsKey = "flickCalibrationV4"
    public let templates: [CentroidClass: CentroidTemplate]
    public private(set) var adapted: [CentroidClass: Vector3]
    public var quality: String {
        String(format: "maximum similarity %.2f", Self.similarity(templates)?.cosine ?? 0)
    }
    public struct Similarity {
        public let first: CentroidClass, second: CentroidClass
        public let cosine: Double
    }
    /// Undo may point like a flick when it is clearly stronger: magnitude separates it.
    public static let undoStrengthRatio = 1.6
    public static func similarity(_ templates: [CentroidClass: CentroidTemplate]) -> Similarity? {
        var result: Similarity?
        for (i, a) in CentroidClass.allCases.enumerated() {
            for b in CentroidClass.allCases.dropFirst(i + 1) {
                guard let u = templates[a], let v = templates[b] else { continue }
                var cosine = u.direction.dot(v.direction)
                if b == .undo, v.medianPeak >= undoStrengthRatio * u.medianPeak, cosine <= 0.8 { cosine = min(cosine, 0) }
                if result == nil || cosine > result!.cosine { result = Similarity(first: a, second: b, cosine: cosine) }
            }
        }
        return result
    }
    public init(captures: [CentroidClass: [FlickStroke]], requireDistinct: Bool = true) throws {
        guard CentroidClass.allCases.allSatisfy({ !(captures[$0] ?? []).isEmpty }),
              captures.values.flatMap({ $0 }).allSatisfy({ $0.peak.isFinite && $0.peak >= 3.5 && $0.sum.isFinite && $0.sum.magnitude > 1e-9 }) else {
            throw AnkiError.message("Flick a little sharper; capture all three gestures at 3.5 rad/s or above.")
        }
        templates = captures.mapValues(CentroidTemplate.init)
        adapted = templates.mapValues(\.direction)
        if requireDistinct, let pair = Self.similarity(templates), pair.cosine > 0.5 {
            throw AnkiError.message("\(pair.first.rawValue) and \(pair.second.rawValue) look alike — redo \(pair.second.rawValue) with a more distinct twist")
        }
        guard isUsable else { throw AnkiError.message("Indistinct captures — redo calibration.") }
    }
    public var isValid: Bool { isUsable && (Self.similarity(templates)?.cosine ?? 1) <= 0.5 }
    /// Structural validity permits offline diagnostics of recordings that need recalibration.
    /// Live creation/loading still requires the pairwise quality check above.
    public var isUsable: Bool {
        CentroidClass.allCases.allSatisfy {
            guard let template = templates[$0], template.isValid, let u = adapted[$0] else { return false }
            return u.isFinite && abs(u.magnitude - 1) < 1e-6
        }
    }
    public func gate(sensitivity: FlickSensitivity = .medium, multiplier: Double = 0.55) -> Double {
        let scale: Double
        switch sensitivity { case .low: scale = 1.3; case .medium: scale = 1; case .high: scale = 0.8 }
        return max(3.0, max(3.5, multiplier * (templates.values.map(\.medianPeak).min() ?? 0)) * scale)
    }
    public mutating func adapt(_ kind: CentroidClass, toward direction: Vector3, rate: Double) {
        guard let current = adapted[kind], direction.isFinite, direction.magnitude > 1e-9, (0...1).contains(rate) else { return }
        adapted[kind] = (current * (1 - rate) + direction.unit * rate).unit
    }
    public mutating func resetAdaptation() { adapted = templates.mapValues(\.direction) }
    public static func load(from defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }
    public func save(to defaults: UserDefaults) {
        if isValid, let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// The live recognizer: one instant class per armed stroke, with no speculative undo.
public final class CentroidDetector {
    public private(set) var calibration: CentroidCalibration?
    public let settings: CentroidSettings
    public let sensitivity: FlickSensitivity
    public let reversed: Bool
    public var onTrace: ((FlickTrace) -> Void)?
    public var onAdaptation: ((CentroidCalibration) -> Void)?
    private let segmenter = StrokeSegmenter()
    private let allowSimilarTemplatesForReplay: Bool
    private var lastFire: FlickDetection?
    private var classFires: [FlickEvent: Double] = [:]
    /// A flick candidate waiting for its snap-back. Handling never snaps back; real flicks do within ~120-240 ms.
    private var pending: (event: FlickEvent, stroke: FlickStroke, direction: Vector3)?
    public static let snapBackRate = 1.5        // rad/s against the stroke direction
    public static let snapBackWindow = 0.30     // seconds from onset
    public static let undoGateRatio = 0.55      // undo needs this share of its calibrated median peak
    public static let undoRefractory = 0.80     // seconds; covers the twist's return
    public let requireSnapBack: Bool
    public init(calibration: CentroidCalibration? = nil, sensitivity: FlickSensitivity = .medium,
                reversed: Bool = false, settings: CentroidSettings = .init(), allowSimilarTemplatesForReplay: Bool = false,
                requireSnapBack: Bool = true) {
        self.calibration = calibration; self.sensitivity = sensitivity; self.reversed = reversed; self.settings = settings
        self.requireSnapBack = requireSnapBack
        self.allowSimilarTemplatesForReplay = allowSimilarTemplatesForReplay
    }
    public func reset() { segmenter.reset(); lastFire = nil; classFires = [:]; pending = nil }
    public func resetAdaptation() { calibration?.resetAdaptation() }
    public func process(_ sample: MotionSample) -> [FlickDetection] {
        var out: [FlickDetection] = []
        if let confirmed = confirmPending(sample) { out.append(confirmed) }
        if let stroke = segmenter.process(sample), let detection = classify(stroke) { out.append(detection) }
        return out
    }

    private func confirmPending(_ sample: MotionSample) -> FlickDetection? {
        guard let p = pending else { return nil }
        if sample.t - p.stroke.onset > Self.snapBackWindow + 1e-6 {
            pending = nil
            onTrace?(FlickTrace(t: sample.t, event: nil, reason: "no snap-back (handling)", peakYaw: p.stroke.peak, angle: 0,
                                sR: 0, sL: 0, latency: sample.t - p.stroke.onset))
            return nil
        }
        guard Vector3(sample.rotationRate).dot(p.direction) <= -Self.snapBackRate else { return nil }
        pending = nil
        onTrace?(FlickTrace(t: sample.t, event: p.event, reason: "snap-back confirmed", peakYaw: p.stroke.peak, angle: 0,
                            sR: 0, sL: 0, latency: sample.t - p.stroke.onset))
        let detection = FlickDetection(t: sample.t, event: p.event, onset: p.stroke.onset, peakTime: p.stroke.peakTime)
        lastFire = detection; classFires[p.event] = detection.t
        return detection
    }
    /// Also used by replay; only held-out strokes enter this method during evaluation.
    public func classify(_ stroke: FlickStroke) -> FlickDetection? {
        guard var calibration, calibration.isUsable, calibration.isValid || allowSimilarTemplatesForReplay, settings.isValid,
              stroke.sum.isFinite, stroke.peak.isFinite, stroke.onset.isFinite, stroke.decidedAt.isFinite else { return nil }
        let scores = CentroidClass.allCases.map { ($0, stroke.sum.unit.dot(calibration.adapted[$0]!)) }
            .sorted { $0.1 > $1.1 }
        let best = scores[0], runner = scores[1]
        var event: FlickEvent?, reason = "weak peak"
        if stroke.peak >= calibration.gate(sensitivity: sensitivity, multiplier: settings.gateMultiplier) {
            event = best.1 >= settings.cosine && best.1 - runner.1 >= settings.margin ? best.0.event : .ambiguous
            if reversed { if event == .left { event = .right } else if event == .right { event = .left } }
            let undoGate = Self.undoGateRatio * (calibration.templates[.undo]?.medianPeak ?? 0)
            if event == .undo, stroke.peak < undoGate { event = .ambiguous }
            let sinceLast = stroke.onset - (lastFire?.t ?? -.infinity)
            if pending != nil || sinceLast < 0.22 - 1e-6 || (lastFire?.event == .undo && sinceLast < Self.undoRefractory) {
                event = nil; reason = "refractory"
            } else if stroke.decidedAt - (classFires[event!] ?? -.infinity) < 0.30 - 1e-6 {
                event = nil; reason = "same class refractory"
            } else {
                reason = event == .ambiguous ? "unclear flick" : "confident \(best.0.rawValue)"
                if event != .ambiguous, best.1 >= 0.80, settings.adaptationRate > 0 {
                    calibration.adapt(best.0, toward: stroke.sum, rate: settings.adaptationRate)
                    self.calibration = calibration
                    onAdaptation?(calibration)
                }
            }
        }
        onTrace?(FlickTrace(t: stroke.decidedAt, event: event, reason: reason, peakYaw: stroke.peak, angle: 0,
                           sR: best.1, sL: runner.1, latency: stroke.decidedAt - stroke.onset))
        guard let event else { return nil }
        // Undo is strong and distinct, so it fires now; flicks wait for their snap-back.
        guard event == .undo || !requireSnapBack else {
            pending = (event, stroke, stroke.sum.unit)
            return nil
        }
        let detection = FlickDetection(t: stroke.decidedAt, event: event, onset: stroke.onset, peakTime: stroke.peakTime)
        lastFire = detection; classFires[event] = detection.t
        return detection
    }
}

public final class CentroidCalibrationSession {
    public private(set) var captures: [CentroidClass: [FlickStroke]] = [:]
    public private(set) var calibration: CentroidCalibration?
    public private(set) var step = CentroidClass.right
    public private(set) var prompt = "Flick RIGHT 6× — 0/6"
    public static let instruction = "Flick the way you would while studying, not extra hard."
    public static let required = 6
    /// The latest correction ("a little sharper", "redo"), cleared by the next accepted capture.
    public private(set) var notice: String?
    public func captured(_ kind: CentroidClass) -> Int { captures[kind, default: []].count }
    private let segmenter = StrokeSegmenter()
    private var captureAfter = -Double.infinity
    public init() {}
    private var progress: String {
        let title = step == .undo ? "Do your UNDO gesture 6× (a quick twist/shake)" : "Flick \(step.rawValue.uppercased()) 6×"
        return "\(title) — \(captures[step, default: []].count)/6"
    }
    public func process(_ sample: MotionSample) -> Bool {
        guard let stroke = segmenter.process(sample) else { return false }
        return capture(stroke)
    }
    @discardableResult public func capture(_ stroke: FlickStroke) -> Bool {
        guard calibration == nil, stroke.onset >= captureAfter else { return false }
        guard stroke.peak.isFinite, stroke.peak >= 3.5, stroke.sum.isFinite, stroke.sum.magnitude > 1e-9 else {
            notice = "A little sharper"
            prompt = "A little sharper. " + progress; return true
        }
        captureAfter = stroke.decidedAt + 0.6
        notice = nil
        captures[step, default: []].append(stroke)
        if captures[step]!.count == 6 {
            let templates = captures.mapValues(CentroidTemplate.init)
            if !templates[step]!.isValid {
                captures[step] = []; notice = "Those weren't consistent — let's redo this one"
                prompt = "Inconsistent gesture — redo. " + progress; return true
            }
            if let pair = CentroidCalibration.similarity(templates), pair.cosine > 0.5 {
                captures[step] = []
                notice = "Too similar to your \((pair.first == step ? pair.second : pair.first).rawValue) flick — make it more distinct"
                prompt = "\(pair.first.rawValue) and \(pair.second.rawValue) look alike — redo \(step.rawValue) with a more distinct twist. " + progress
                return true
            }
            if CentroidClass.allCases.allSatisfy({ captures[$0, default: []].count == 6 }) {
                do {
                    calibration = try CentroidCalibration(captures: captures)
                    prompt = "Calibration complete — \(calibration!.quality)"
                } catch {
                    captures[step] = []; notice = "Let's redo this one"
                    prompt = error.localizedDescription + " " + progress
                }
                return true
            }
            step = CentroidClass.allCases.first { captures[$0, default: []].count < 6 }!
        }
        prompt = progress
        return true
    }
}
