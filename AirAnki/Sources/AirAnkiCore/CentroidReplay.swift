import Foundation

public enum CentroidReplay {
    public struct Training {
        public let calibration: CentroidCalibration
        public let excludedThrough: [Int: Double]
        public let strokes: [Int: [FlickStroke]]
        public let rejected: [Int: Int]
    }
    public static func train(_ rows: [LabReplay.Row], labels: [Int: String], count: Int) throws -> Training {
        guard count > 0 else { throw AnkiError.message("Calibration count must be positive.") }
        let strokes = ReplayEvaluation.segment(rows)
        var captures: [CentroidClass: [FlickStroke]] = [:], excluded: [Int: Double] = [:], rejected: [Int: Int] = [:]
        for segment in strokes.keys.sorted() {
            guard let kind = labels[segment].flatMap(CentroidClass.init) else { continue }
            var captureAfter = -Double.infinity
            for stroke in strokes[segment, default: []] {
                if captures[kind, default: []].count == count { break }
                excluded[segment] = stroke.decidedAt
                guard stroke.onset >= captureAfter, stroke.peak >= 3.5, stroke.sum.magnitude > 1e-9 else {
                    rejected[segment, default: 0] += 1; continue
                }
                captures[kind, default: []].append(stroke)
                captureAfter = stroke.decidedAt + 0.6
            }
        }
        guard CentroidClass.allCases.allSatisfy({ captures[$0, default: []].count == count }) else {
            throw AnkiError.message("Not enough accepted strokes per class: \(CentroidClass.allCases.map { "\($0.rawValue)=\(captures[$0, default: []].count)" }.joined(separator: ", ")); requested \(count).")
        }
        return try Training(calibration: CentroidCalibration(captures: captures, requireDistinct: false), excludedThrough: excluded, strokes: strokes, rejected: rejected)
    }
    public struct Confusion: Equatable {
        public init() {}
        public var right = 0, left = 0, undo = 0, ambiguous = 0, ignored = 0
        public var confident: Int { right + left + undo }
        public var total: Int { confident + ambiguous + ignored }
        public var description: String { "\(right) / \(left) / \(undo) / \(ambiguous) / \(ignored)" }
        mutating func record(_ event: FlickEvent?) {
            switch event {
            case .right: right += 1
            case .left: left += 1
            case .undo: undo += 1
            case .ambiguous: ambiguous += 1
            default: ignored += 1
            }
        }
    }
    public struct Result {
        public let confusion: [Int: Confusion]
        public let events: [LabReplay.Event]
        public let calibration: CentroidCalibration
        public let correct: Int, wrong: Int, idleConfident: Int, idleAmbiguous: Int
        public var score: Int { correct - 3 * wrong - 3 * idleConfident - idleAmbiguous }
        public var description: String { "score=\(score) correct=\(correct) wrong=\(wrong) idleConfident=\(idleConfident) idleAmbiguous=\(idleAmbiguous)" }
    }
    public static func evaluate(strokes: [Int: [FlickStroke]], calibration: CentroidCalibration,
                                excludedThrough: [Int: Double] = [:], labels: [Int: String],
                                settings: CentroidSettings = .init(), sensitivity: FlickSensitivity = .medium,
                                trace: ((FlickTrace) -> Void)? = nil) -> Result {
        let detector = CentroidDetector(calibration: calibration, sensitivity: sensitivity, settings: settings,
                                        allowSimilarTemplatesForReplay: true, requireSnapBack: false)
        detector.onTrace = trace
        var confusion: [Int: Confusion] = [:], events: [LabReplay.Event] = []
        // No training stroke enters the adaptive detector, including those in later segments.
        let ordered = strokes.flatMap { segment, values in values.map { (segment, $0) } }.sorted { $0.1.onset < $1.1.onset }
        for (segment, stroke) in ordered where stroke.onset > (excludedThrough[segment] ?? -.infinity) {
            let detection = detector.classify(stroke)
            confusion[segment, default: Confusion()].record(detection?.event)
            if let detection { events.append(LabReplay.Event(detection: detection, segment: segment)) }
        }
        var correct = 0, wrong = 0, idleConfident = 0, idleAmbiguous = 0
        for (segment, row) in confusion {
            if labels[segment] == "idle" { idleConfident += row.confident; idleAmbiguous += row.ambiguous }
            else if let kind = labels[segment].flatMap(CentroidClass.init) {
                let matches: Int
                switch kind { case .right: matches = row.right; case .left: matches = row.left; case .undo: matches = row.undo }
                correct += matches; wrong += row.confident - matches
            }
        }
        return Result(confusion: confusion, events: events, calibration: detector.calibration!, correct: correct,
                      wrong: wrong, idleConfident: idleConfident, idleAmbiguous: idleAmbiguous)
    }
    public struct SweepResult {
        public let settings: CentroidSettings
        public let result: Result
        fileprivate let index: Int
    }
    public static func sweep(training: Training, labels: [Int: String]) -> [SweepResult] {
        var results: [SweepResult] = []
        for gate in [0.45, 0.50, 0.55, 0.60, 0.65, 0.70] {
            for cosine in [0.60, 0.65, 0.70, 0.75, 0.80] {
                for margin in [0.10, 0.15, 0.20, 0.25, 0.30] {
                    for rate in [0.0, 0.10, 0.15, 0.25] {
                        var settings = CentroidSettings()
                        settings.gateMultiplier = gate; settings.cosine = cosine; settings.margin = margin; settings.adaptationRate = rate
                        let result = evaluate(strokes: training.strokes, calibration: training.calibration,
                                              excludedThrough: training.excludedThrough, labels: labels, settings: settings)
                        results.append(SweepResult(settings: settings, result: result, index: results.count))
                    }
                }
            }
        }
        // Prefer the brief's defaults among tied scores, then the fixed grid order.
        func distance(_ s: CentroidSettings) -> Double {
            abs(s.gateMultiplier - 0.55) + abs(s.cosine - 0.70) + abs(s.margin - 0.20) + abs(s.adaptationRate - 0.15)
        }
        return results.sorted {
            if $0.result.score != $1.result.score { return $0.result.score > $1.result.score }
            let a = distance($0.settings), b = distance($1.settings)
            if abs(a - b) > 1e-9 { return a < b }
            return $0.index < $1.index
        }
    }
}
