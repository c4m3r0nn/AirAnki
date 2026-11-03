import Foundation

public enum ReplayEvaluation {
    public struct Training {
        public let calibration: FlickCalibration
        public let excludedThrough: [Int: Double]
        public let strokes: [Int: [FlickStroke]]
        public let rejected: [Int: Int]
        public func remaining(in segment: Int) -> Int {
            strokes[segment, default: []].filter { $0.onset > (excludedThrough[segment] ?? -.infinity) }.count
        }
    }
    public static func segment(_ rows: [LabReplay.Row], settings: FlickSettings = .init()) -> [Int: [FlickStroke]] {
        let segmenter = StrokeSegmenter(settings: settings)
        var segment = 0, strokes: [Int: [FlickStroke]] = [:]
        for row in rows {
            if let marker = row.marker { segment = marker }
            if let sample = row.motion, let stroke = segmenter.process(sample) {
                strokes[segment, default: []].append(stroke)
            }
        }
        return strokes
    }
    /// First N accepted strokes, in chronological order; weak captures are rejected
    /// exactly as in live calibration. The whole training prefix is held out, including
    /// rejected attempts. No later stroke contributes to the discriminant or peak gate.
    public static func train(_ rows: [LabReplay.Row], labels: [Int: String], count: Int,
                             settings: FlickSettings = .init()) throws -> Training {
        guard count > 0 else { throw AnkiError.message("Calibration count must be positive.") }
        let strokes = segment(rows, settings: settings)
        var right: [FlickStroke] = [], left: [FlickStroke] = []
        var excluded: [Int: Double] = [:], rejected: [Int: Int] = [:]
        for segment in strokes.keys.sorted() {
            guard labels[segment] == "right" || labels[segment] == "left" else { continue }
            let isRight = labels[segment] == "right"
            for stroke in strokes[segment, default: []] {
                guard (isRight ? right.count : left.count) < count else { break }
                excluded[segment] = stroke.decidedAt
                guard stroke.peak >= 5 else { rejected[segment, default: 0] += 1; continue }
                if isRight { right.append(stroke) } else { left.append(stroke) }
            }
        }
        guard right.count == count, left.count == count else {
            throw AnkiError.message("Not enough accepted calibration strokes in both labelled directions (right \(right.count), left \(left.count), requested \(count)).")
        }
        return try Training(calibration: FlickCalibration(right: right, left: left), excludedThrough: excluded,
                            strokes: strokes, rejected: rejected)
    }
    public struct Metrics {
        public let right: Int, left: Int, shakes: Int, idle: Int, wrong: Int
        public var score: Int { right + left + shakes - 2 * idle - 2 * wrong }
        public var description: String { "score=\(score) right=\(right) left=\(left) shakes=\(shakes) idle=\(idle) wrong=\(wrong)" }
    }
    public static func metrics(_ events: [LabReplay.Event], labels: [Int: String]) -> Metrics {
        let net = netEvents(events)
        func count(_ label: String, _ kind: FlickEvent) -> Int {
            net.filter { labels[$0.segment] == label && $0.detection.event == kind }.count
        }
        return Metrics(right: count("right", .right), left: count("left", .left), shakes: count("shake", .shake),
                       idle: net.filter { labels[$0.segment] == "idle" }.count,
                       wrong: count("right", .left) + count("left", .right))
    }
    public struct SweepResult {
        public let settings: FlickSettings
        public let metrics: Metrics
    }
    /// Fixed, file-independent grid. Ties keep the grid order (shorter windows first).
    public static func sweep(_ rows: [LabReplay.Row], labels: [Int: String], count: Int) -> [SweepResult] {
        var results: [SweepResult] = []
        for quiet in [0.15, 0.20, 0.25, 0.30] {
            for onset in [3.5, 4.0, 4.5] {
                for peak in [5.0, 5.5, 6.0] {
                    for lobe in [2.0, 2.5, 3.0, 3.5, 4.0] {
                        for window in [0.5, 0.6, 0.7, 0.8, 0.9] {
                            let settings = FlickSettings(quietTime: quiet, onset: onset, peakMin: peak, shakeLobe: lobe, shakeWindow: window)
                            guard let training = try? train(rows, labels: labels, count: count, settings: settings) else { continue }
                            let result = LabReplay.run(rows, detector: FlickDetector(calibration: training.calibration, settings: settings))
                            results.append(SweepResult(settings: settings, metrics: metrics(heldOut(result, training: training), labels: labels)))
                        }
                    }
                }
            }
        }
        return results.enumerated().sorted {
            $0.element.metrics.score == $1.element.metrics.score ? $0.offset < $1.offset : $0.element.metrics.score > $1.element.metrics.score
        }.map(\.element)
    }
    public static func heldOut(_ result: LabReplay.Result, training: Training?) -> [LabReplay.Event] {
        result.events.filter { $0.detection.onset > (training?.excludedThrough[$0.segment] ?? -.infinity) }
    }
    /// A shake compensates its initial speculative action. Count final gestures separately
    /// from raw deliveries; otherwise each correctly recognized shake looks like a false flick.
    public static func netEvents(_ events: [LabReplay.Event]) -> [LabReplay.Event] {
        let compensated = Set(events.compactMap { $0.detection.speculativeFlickAt })
        return events.filter { $0.detection.event == .shake || !compensated.contains($0.detection.t) }
    }
    public static func summary(_ events: [LabReplay.Event], segments: [Int], labels: [Int: String],
                               expected: [Int: Int] = [:]) -> String {
        let net = netEvents(events)
        var lines = ["segment label right left shake nothing extra (net of speculative flicks)"]
        for segment in segments {
            let actual = net.filter { $0.segment == segment }
            let counts = [FlickEvent.right, .left, .shake].map { kind in actual.filter { $0.detection.event == kind }.count }
            let missing = expected[segment].map { String(max(0, $0 - actual.count)) } ?? "?"
            let extra = expected[segment].map { String(max(0, actual.count - $0)) } ?? "?"
            lines.append("\(segment) \(labels[segment] ?? "unlabelled") \(counts[0]) \(counts[1]) \(counts[2]) \(missing) \(extra)")
        }
        let idle = net.filter { labels[$0.segment] == "idle" }.count
        lines.append(labels.values.contains("idle") ? "idle false positives: \(idle)" : "idle false positives: unlabelled")
        for kind in ["flick", "shake"] {
            let detections = events.map(\.detection).filter { kind == "shake" ? $0.event == .shake : $0.event != .shake }
            let latencies = detections.map { ($0.t - $0.onset) * 1000 }.sorted()
            if !latencies.isEmpty {
                let median = (latencies[(latencies.count-1)/2] + latencies[latencies.count/2]) / 2
                lines.append(String(format: "%@ onset latency median=%.1f ms max=%.1f ms n=%d", kind, median, latencies.last!, latencies.count))
            }
        }
        lines.append("Counts are segment totals, not per-trial matching; nothing/extra require --expected ground-truth counts.")
        return lines.joined(separator: "\n")
    }
}
