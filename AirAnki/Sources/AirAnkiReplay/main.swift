import AirAnkiCore
import Foundation

let usage = "Usage: AirAnkiReplay <lab.csv> [--sensitivity low|medium|high] [--trace] [--labels left,right,undo,idle] [--label-start 1] [--calibrate-from-labels N] [--detector centroid|lda|legacy] [--expected 10,10,5,0] [--hold] [--quiet-seconds Q] [--onset O] [--peak-min P] [--shake-lobe L] [--shake-window W] [--sweep] [--save-calibration file.json] [--load-calibration file.json]"
var arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] { print(usage); exit(0) }
guard let path = arguments.first, !path.hasPrefix("--") else { fputs(usage + "\n", stderr); exit(2) }
arguments.removeFirst()
var sensitivity = FlickSensitivity.medium
var trace = false, instant = true, sweep = false, detectorName = "centroid", labelNames: [String] = [], start = 1, calibrationCount = 0
var expectedCounts: [Int] = [], settings = FlickSettings()
var savePath: String?, loadPath: String?
var ldaOptionsUsed = false
func value() -> String {
    guard !arguments.isEmpty else { fputs(usage + "\n", stderr); exit(2) }
    return arguments.removeFirst()
}
while !arguments.isEmpty {
    let option = arguments.removeFirst()
    switch option {
    case "--quiet-seconds": ldaOptionsUsed = true; settings.quietTime = Double(value()) ?? -1
    case "--onset": ldaOptionsUsed = true; settings.onset = Double(value()) ?? -1
    case "--peak-min": ldaOptionsUsed = true; settings.peakMin = Double(value()) ?? -1
    case "--shake-lobe": ldaOptionsUsed = true; settings.shakeLobe = Double(value()) ?? -1
    case "--shake-window": ldaOptionsUsed = true; settings.shakeWindow = Double(value()) ?? -1
    case "--sweep": sweep = true
    case "--save-calibration": savePath = value()
    case "--load-calibration": loadPath = value()
    case "--trace": trace = true
    case "--hold": instant = false
    case "--sensitivity":
        guard let parsed = FlickSensitivity(rawValue: value()) else { fputs(usage + "\n", stderr); exit(2) }; sensitivity = parsed
    case "--labels": labelNames = value().split(separator: ",").map(String.init)
    case "--label-start": start = Int(value()) ?? -1
    case "--calibrate-from-labels": calibrationCount = Int(value()) ?? -1
    case "--detector": detectorName = value()
    case "--expected": expectedCounts = value().split(separator: ",").map { Int($0) ?? -1 }
    default: fputs("Unknown option: \(option)\n\(usage)\n", stderr); exit(2)
    }
}
guard settings.isValid, ["centroid", "lda", "legacy"].contains(detectorName), start >= 0, calibrationCount >= 0,
      loadPath == nil || calibrationCount == 0,
      detectorName != "centroid" || (instant && !ldaOptionsUsed && expectedCounts.isEmpty),
      !sweep || (calibrationCount > 0 && detectorName != "legacy" && instant && sensitivity == .medium),
      labelNames.allSatisfy({ ["right", "left", "undo", "shake", "idle"].contains($0) }),
      expectedCounts.allSatisfy({ $0 >= 0 }), expectedCounts.isEmpty || expectedCounts.count == labelNames.count else {
    fputs(usage + "\n", stderr); exit(2)
}
do {
    let rows = try LabReplay.read(String(contentsOfFile: path, encoding: .utf8))
    var labels = Dictionary(uniqueKeysWithValues: labelNames.enumerated().map { (start + $0.offset, $0.element) })
    if detectorName == "centroid" {
        let training = calibrationCount > 0 ? try CentroidReplay.train(rows, labels: labels, count: calibrationCount) : nil
        let calibration: CentroidCalibration
        if let loadPath {
            calibration = try JSONDecoder().decode(CentroidCalibration.self, from: Data(contentsOf: URL(fileURLWithPath: loadPath)))
        } else if let training { calibration = training.calibration }
        else { throw AnkiError.message("Centroid needs --calibrate-from-labels or --load-calibration.") }
        guard calibration.isUsable else { throw AnkiError.message("Invalid V4 calibration.") }
        if !calibration.isValid {
            print("WARNING: labelled training fails the live similarity check (\(calibration.quality)); offline diagnostics only, live calibration must be redone.")
        }
        var centroidSettings = CentroidSettings()
        if sweep, let training {
            let results = CentroidReplay.sweep(training: training, labels: labels)
            print("Grid: gate=[.45,.50,.55,.60,.65,.70] cos=[.60,.65,.70,.75,.80] margin=[.10,.15,.20,.25,.30] adaptation=[0,.10,.15,.25]")
            print("\(results.count) settings; score=correct-3*wrong-3*idleConfident-idleAmbiguous; ties closest to brief defaults, then grid order")
            for (i, row) in results.prefix(5).enumerated() { print("\(i + 1). \(row.settings.description) \(row.result.description)") }
            centroidSettings = results[0].settings
        }
        if let savePath {
            guard calibration.isValid else { throw AnkiError.message("Cannot save templates that fail the live similarity check.") }
            try JSONEncoder().encode(calibration).write(to: URL(fileURLWithPath: savePath), options: .atomic)
        }
        let strokes = training?.strokes ?? ReplayEvaluation.segment(rows)
        let result = CentroidReplay.evaluate(strokes: strokes, calibration: calibration,
            excludedThrough: training?.excludedThrough ?? [:], labels: labels, settings: centroidSettings, sensitivity: sensitivity,
            trace: trace ? { print(String(format: "trace t=%.3f %@ %@", $0.t, $0.csvEvent, $0.detail)) } : nil)
        print("\(URL(fileURLWithPath: path).lastPathComponent) detector=centroid sensitivity=\(sensitivity.rawValue) calibration_per_class=\(calibrationCount)")
        print("\(centroidSettings.description) peakGate=\(calibration.gate(sensitivity: sensitivity, multiplier: centroidSettings.gateMultiplier)) \(calibration.quality)")
        for kind in CentroidClass.allCases {
            let template = calibration.templates[kind]!
            print("template \(kind.rawValue) u=\(template.direction) medianPeak=\(template.medianPeak)")
        }
        print("segment label | right / left / undo / ambiguous / ignored | total strokes / training prefix")
        for segment in Set(strokes.keys).union(labels.keys).sorted() {
            let row = result.confusion[segment] ?? CentroidReplay.Confusion()
            print("\(segment) \(labels[segment] ?? "unlabelled") | \(row.description) | \(strokes[segment, default: []].count) / \(strokes[segment, default: []].count - row.total)")
        }
        print(result.description)
        print("Counts are segmented strokes, not matched trials. Calibration prefixes do not adapt templates; held-out strokes adapt in timestamp order.")
        // Live-equivalent pass: every sample through process(), so snap-back confirmation applies.
        let live = CentroidDetector(calibration: calibration, sensitivity: sensitivity, settings: centroidSettings,
                                    allowSimilarTemplatesForReplay: true)
        if trace { live.onTrace = { print(String(format: "live t=%.3f %@ %@", $0.t, $0.csvEvent, $0.detail)) } }
        var segment = 0, counts: [Int: [FlickEvent: Int]] = [:], latencies: [Double] = []
        let excluded = training?.excludedThrough ?? [:]
        for row in rows {
            if row.marker != nil { segment += 1; live.reset(); continue }
            guard let sample = row.motion, sample.t > (excluded[segment] ?? -.infinity) else { continue }
            for detection in live.process(sample) {
                counts[segment, default: [:]][detection.event, default: 0] += 1
                latencies.append((detection.t - detection.onset) * 1000)
            }
        }
        print("live stream (snap-back) | right / left / undo / ambiguous")
        for seg in Set(counts.keys).union(labels.keys).sorted() {
            let c = counts[seg] ?? [:]
            print("\(seg) \(labels[seg] ?? "unlabelled") | \(c[.right] ?? 0) / \(c[.left] ?? 0) / \(c[.undo] ?? 0) / \(c[.ambiguous] ?? 0)")
        }
        let sorted = latencies.sorted()
        if !sorted.isEmpty { print(String(format: "onset-to-fire latency median=%.0f ms max=%.0f ms", sorted[sorted.count / 2], sorted.last!)) }
        exit(0)
    }
    labels = labels.mapValues { $0 == "undo" ? "shake" : $0 }
    if sweep {
        let results = ReplayEvaluation.sweep(rows, labels: labels, count: calibrationCount)
        guard let chosen = results.first else { throw AnkiError.message("No grid setting has sufficient accepted calibration strokes.") }
        print("Grid: quiet=[.15,.20,.25,.30] onset=[3.5,4,4.5] peakMin=[5,5.5,6] shakeLobe=[2,2.5,3,3.5,4] window=[.5,.6,.7,.8,.9]")
        print("\(results.count)/900 valid settings; score=right+left+shakes-2*idle-2*wrong; ties use grid order")
        for (index, result) in results.prefix(5).enumerated() {
            print("\(index + 1). \(result.settings.description) \(result.metrics.description)")
        }
        settings = chosen.settings
        print("Chosen: \(settings.description)")
    }
    let training = calibrationCount > 0 ? try ReplayEvaluation.train(rows, labels: labels, count: calibrationCount, settings: settings) : nil
    let calibration: FlickCalibration?
    if let loadPath {
        let value = try JSONDecoder().decode(FlickCalibration.self, from: Data(contentsOf: URL(fileURLWithPath: loadPath)))
        guard value.isValid else { throw AnkiError.message("Invalid saved calibration; recalibrate.") }
        calibration = value
    } else { calibration = training?.calibration }
    if let savePath, let calibration {
        try JSONEncoder().encode(calibration).write(to: URL(fileURLWithPath: savePath), options: .atomic)
    }
    var expected = Dictionary(uniqueKeysWithValues: expectedCounts.enumerated().map { (start + $0.offset, $0.element) })
    let strokes = training?.strokes ?? ReplayEvaluation.segment(rows, settings: settings)
    for (segment, label) in labels where label == "left" || label == "right" {
        if let training {
            let excludedCount = strokes[segment, default: []].count - training.remaining(in: segment)
            if let count = expected[segment] { expected[segment] = max(0, count - excludedCount) }
        }
    }
    let log: ((FlickTrace) -> Void)? = trace ? { decision in
        print(String(format: "trace t=%.3f %@ %@", decision.t, decision.csvEvent, decision.detail))
    } : nil
    let result: LabReplay.Result
    if detectorName == "legacy" {
        let detector = LegacyFlickDetector(sensitivity: sensitivity); detector.onTrace = log
        result = LabReplay.run(rows, detector: detector)
    } else {
        guard let calibration else { throw AnkiError.message("The LDA comparison detector needs --labels and --calibrate-from-labels, or --load-calibration. Evaluation strokes are never used for training.") }
        let detector = FlickDetector(calibration: calibration, sensitivity: sensitivity, instant: instant, settings: settings)
        detector.onTrace = log
        result = LabReplay.run(rows, detector: detector)
    }
    print("\(URL(fileURLWithPath: path).lastPathComponent) detector=\(detectorName) sensitivity=\(sensitivity.rawValue) motion_rows=\(result.motionCount) calibration_per_direction=\(calibrationCount)")
    print(settings.description)
    if let c = calibration { print("axis=\(c.axis) mid=\(c.mid) half=\(c.half) calibratedPeakMin=\(c.peakMin)") }
    for segment in result.segments {
        print("strokes segment=\(segment) total=\(strokes[segment, default: []].count) training_weak_rejected=\(training?.rejected[segment] ?? 0) held_out=\(training?.remaining(in: segment) ?? strokes[segment, default: []].count)")
    }
    let events = ReplayEvaluation.heldOut(result, training: training)
    for event in events {
        print(String(format: "t=%.3f marker=%d %@%@", event.detection.t, event.segment, event.detection.event.rawValue,
                     event.detection.speculativeFlickAt.map { " compensates=\($0)" } ?? ""))
    }
    print(ReplayEvaluation.summary(events, segments: result.segments, labels: labels, expected: expected))
    if !labels.isEmpty { print(ReplayEvaluation.metrics(events, labels: labels).description) }
} catch {
    fputs("AirAnkiReplay: \(error.localizedDescription)\n", stderr); exit(1)
}
