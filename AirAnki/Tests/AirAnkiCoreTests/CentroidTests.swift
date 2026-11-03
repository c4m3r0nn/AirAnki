import Foundation
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

private func centroidStroke(_ vector: Vector3, peak: Double = 6, at time: Double = 1) -> FlickStroke {
    FlickStroke(onset: time, decidedAt: time + 0.08, peakTime: time + 0.04, sum: vector, peak: peak)
}
private func centroidCalibration(peak: Double = 6) throws -> CentroidCalibration {
    try CentroidCalibration(captures: [.right: [centroidStroke(.init(1,0,0), peak: peak)],
                                      .left: [centroidStroke(.init(-1,0,0), peak: peak)],
                                      .undo: [centroidStroke(.init(0,1,0), peak: peak)]])
}
private func nearCentroid(_ a: Double, _ b: Double, file: StaticString = #filePath, line: UInt = #line) {
    if !a.isFinite || abs(a-b) > 1e-6 { XCTFail("\(a) != \(b)", file: file, line: line) }
}

final class CentroidTests: XCTestCase {
    func testThreeClassesAmbiguousAndWeakStroke() throws {
        let detector = CentroidDetector(calibration: try centroidCalibration(), requireSnapBack: false)
        let vectors = [Vector3(1,0,0), .init(-1,0,0), .init(0,1,0), .init(1,1,0), .init(0,0,1)]
        let expected: [FlickEvent] = [.right,.left,.undo,.ambiguous,.ambiguous]
        for (index, vector) in vectors.enumerated() {
            let result = detector.classify(centroidStroke(vector, at: Double(index)))
            XCTAssertEqual(result?.event, expected[index])
            XCTAssertNil(result?.speculativeFlickAt)
            nearCentroid(result!.t - result!.onset, 0.08)
        }
        XCTAssertNil(detector.classify(centroidStroke(.init(1,0,0), peak: 3.49, at: 7)))
        XCTAssertNil(CentroidDetector().classify(centroidStroke(.init(1,0,0))))
    }
    func testTemplatesNormalizeEachCaptureAndUseMedianPeaks() throws {
        let c = try CentroidCalibration(captures: [
            .right: [centroidStroke(.init(100,0,0), peak: 4), centroidStroke(.init(1,1,0), peak: 6), centroidStroke(.init(1,-1,0), peak: 20)],
            .left: [centroidStroke(.init(-1,0,0))], .undo: [centroidStroke(.init(0,0,1))]])
        nearCentroid(c.templates[.right]!.direction.x, 1)
        nearCentroid(c.templates[.right]!.direction.y, 0)
        nearCentroid(c.templates[.right]!.medianPeak, 6)
    }
    func testGateScalingAndAbsoluteFloor() throws {
        let c = try centroidCalibration()
        nearCentroid(c.gate(), 3.5); nearCentroid(c.gate(sensitivity: .low), 4.55)
        nearCentroid(c.gate(sensitivity: .high), 3)
        let stronger = try centroidCalibration(peak: 10)
        nearCentroid(stronger.gate(), 5.5); nearCentroid(stronger.gate(sensitivity: .low), 7.15)
        nearCentroid(stronger.gate(sensitivity: .high), 4.4)
    }
    func testAdaptationRequiresConfidentCosineAndResetRestoresBaseline() throws {
        let baseline = try centroidCalibration()
        let detector = CentroidDetector(calibration: baseline, requireSnapBack: false)
        var changes = 0
        detector.onAdaptation = { _ in changes += 1 }
        // cos=.75 is confident but below the adaptation threshold.
        _ = detector.classify(centroidStroke(.init(0.75,0,sqrt(1 - 0.75*0.75))))
        XCTAssertEqual(detector.calibration, baseline)
        let direction = Vector3(0.9,0,sqrt(1 - 0.9*0.9))
        _ = detector.classify(centroidStroke(direction, at: 2))
        let expected = (Vector3(1,0,0)*0.85 + direction*0.15).unit
        nearCentroid(detector.calibration!.adapted[.right]!.x, expected.x)
        nearCentroid(detector.calibration!.adapted[.right]!.z, expected.z)
        XCTAssertEqual(detector.calibration!.templates, baseline.templates)
        XCTAssertEqual(changes, 1)
        _ = detector.classify(centroidStroke(.init(1,1,0), at: 3))
        XCTAssertEqual(changes, 1)
        detector.resetAdaptation(); XCTAssertEqual(detector.calibration, baseline)
        var throttle = AdaptationPersistence(at: 0)
        XCTAssertFalse(throttle.shouldSave(at: 29.99)); XCTAssertTrue(throttle.shouldSave(at: 30))
        XCTAssertFalse(throttle.shouldSave(at: 59.99)); XCTAssertTrue(throttle.shouldSave(at: 60))
    }
    func testRefractorySameClassAndReverse() throws {
        let detector = CentroidDetector(calibration: try centroidCalibration(), reversed: true, requireSnapBack: false)
        XCTAssertEqual(detector.classify(centroidStroke(.init(1,0,0), at: 0))?.event, .left)
        XCTAssertNil(detector.classify(centroidStroke(.init(0,1,0), at: 0.29)))
        XCTAssertNil(detector.classify(centroidStroke(.init(1,0,0), at: 0.299)))
        XCTAssertEqual(detector.classify(centroidStroke(.init(1,0,0), at: 0.30))?.event, .left)
        XCTAssertEqual(detector.classify(centroidStroke(.init(0,1,0), at: 0.60))?.event, .undo)
        XCTAssertEqual(detector.classify(centroidStroke(.init(1,1,0), at: 1.5))?.event, .ambiguous) // after the 800 ms undo refractory
        XCTAssertNil(detector.classify(centroidStroke(.init(-1,0,0), at: 1.7)))
    }
    func testCalibrationSimilarityRejectsAndRedoesOnlyCurrentStep() throws {
        let session = CentroidCalibrationSession()
        var time = 1.0
        for kind in CentroidClass.allCases {
            if kind == .undo {
                for _ in 0..<6 { _ = session.capture(centroidStroke(.init(-1,0,0), at: time)); time += 1 }
                XCTAssertTrue(session.prompt.contains("left and undo look alike"))
                XCTAssertEqual(session.captures[.right]?.count, 6); XCTAssertEqual(session.captures[.left]?.count, 6)
                XCTAssertEqual(session.captures[.undo]?.count, 0); XCTAssertNil(session.calibration)
            }
            let vector = kind == .right ? Vector3(1,0,0) : kind == .left ? .init(-1,0,0) : .init(0,1,0)
            for _ in 0..<6 { _ = session.capture(centroidStroke(vector, at: time)); time += 1 }
        }
        XCTAssertTrue(session.calibration?.isValid == true)
        XCTAssertTrue(session.prompt.contains("complete"))
    }
    func testCaptureWeakAndReturnSwingDoNotAdvance() {
        let session = CentroidCalibrationSession()
        XCTAssertTrue(session.capture(centroidStroke(.init(1,0,0), peak: 3.49, at: 0)))
        XCTAssertTrue(session.prompt.contains("little sharper"))
        XCTAssertEqual(session.captures[.right]?.count ?? 0, 0)
        // Rejected attempts impose no 600 ms hold.
        XCTAssertTrue(session.capture(centroidStroke(.init(1,0,0), peak: 3.5, at: 0.1)))
        XCTAssertFalse(session.capture(centroidStroke(.init(-1,0,0), at: 0.7)))
        XCTAssertTrue(session.capture(centroidStroke(.init(1,0,0), at: 0.78)))
        XCTAssertEqual(session.captures[.right]?.count, 2)
    }
    func testV4PersistenceAndInvalidCalibrationCannotDriveLiveDetector() throws {
        let name = "AirAnki-centroid-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("old".utf8), forKey: "flickCalibrationV3")
        XCTAssertNil(CentroidCalibration.load(from: defaults))
        var c = try centroidCalibration()
        c.adapt(.right, toward: .init(1,0,0.2), rate: 0.15); c.save(to: defaults)
        XCTAssertEqual(CentroidCalibration.load(from: defaults), c)
        c.resetAdaptation(); c.save(to: defaults)
        let baseline = try centroidCalibration()
        XCTAssertEqual(CentroidCalibration.load(from: defaults), baseline)
        let same = [centroidStroke(.init(1,0,0))]
        do { _ = try CentroidCalibration(captures: [.right: same, .left: same, .undo: same]); XCTFail("must reject") } catch { }
        let diagnostic = try CentroidCalibration(captures: [.right: same, .left: same, .undo: same], requireDistinct: false)
        XCTAssertFalse(diagnostic.isValid)
        XCTAssertNil(CentroidDetector(calibration: diagnostic).classify(same[0]))
        diagnostic.save(to: defaults)
        XCTAssertEqual(CentroidCalibration.load(from: defaults), c)
    }
    func testWatchdogStartupLossRecoveryAndStop() {
        var watchdog = MotionWatchdog()
        watchdog.start(at: 10)
        XCTAssertFalse(watchdog.check(at: 11.99)); XCTAssertTrue(watchdog.check(at: 12))
        XCTAssertFalse(watchdog.check(at: 13)); XCTAssertTrue(watchdog.isLost)
        XCTAssertFalse(watchdog.received(at: 10)); XCTAssertTrue(watchdog.isLost)
        XCTAssertTrue(watchdog.received(at: 14)); XCTAssertFalse(watchdog.isLost)
        XCTAssertFalse(watchdog.check(at: 15.9)); XCTAssertTrue(watchdog.check(at: 16))
        watchdog.stop(); XCTAssertFalse(watchdog.check(at: 30)); XCTAssertFalse(watchdog.isLost)
    }
    func testTimeBasedFeatureAndStreamGapAtBothRates() throws {
        for hz in [25.0,50.0] {
            let detector = CentroidDetector(calibration: try centroidCalibration())
            var events: [FlickDetection] = []
            for i in 0..<Int(hz) {
                _ = detector.process(.init(t: Double(i)/hz, rotationRate: (0,0,0), gravity: (0,0,-1)))
            }
            for i in 0...Int(0.08*hz) {
                events += detector.process(.init(t: 1+Double(i)/hz, rotationRate: (6,0,0), gravity: (0,0,-1)))
            }
            // A flick fires only when it snaps back; holding the motion is handling.
            XCTAssertEqual(events, [])
            events += detector.process(.init(t: 1.12, rotationRate: (-3,0,0), gravity: (0,0,-1)))
            XCTAssertEqual(events.map(\.event), [.right]); nearCentroid(events[0].t, 1.12)
            XCTAssertEqual(detector.process(.init(t: 4, rotationRate: (6,0,0), gravity: (0,0,-1))), [])
            XCTAssertEqual(detector.process(.init(t: .nan, rotationRate: (6,0,0), gravity: (0,0,-1))), [])
        }
    }
    func testHandlingWithoutSnapBackNeverFires() throws {
        let detector = CentroidDetector(calibration: try centroidCalibration())
        var events: [FlickDetection] = []
        for i in 0..<25 { events += detector.process(.init(t: Double(i)/25, rotationRate: (0,0,0), gravity: (0,0,-1))) }
        // A sustained turn (picking the AirPod up) that slows down without reversing.
        for i in 0..<12 { events += detector.process(.init(t: 1+Double(i)/25, rotationRate: (6-Double(i)*0.4,0,0), gravity: (0,0,-1))) }
        XCTAssertEqual(events, [])
    }
    func testStrongUndoFiresInstantlyAndWeakUndoIsUnclear() throws {
        let c = try CentroidCalibration(captures: [.right: [centroidStroke(.init(1,0,0), peak: 6)],
                                                   .left: [centroidStroke(.init(-1,0,0), peak: 6)],
                                                   .undo: [centroidStroke(.init(0,1,0), peak: 20)]])
        let detector = CentroidDetector(calibration: c)
        XCTAssertEqual(detector.classify(centroidStroke(.init(0,1,0), peak: 10.9, at: 0))?.event, nil) // unclear: waits for snap-back
        let strong = CentroidDetector(calibration: c)
        XCTAssertEqual(strong.classify(centroidStroke(.init(0,1,0), peak: 12, at: 0))?.event, .undo)
        // The twist's return within 800 ms is ignored.
        XCTAssertNil(strong.classify(centroidStroke(.init(0,-1,0), peak: 12, at: 0.5)))
    }
    func testUndoMayResembleAFlickWhenMuchStronger() throws {
        let similar = try CentroidCalibration(captures: [.right: [centroidStroke(.init(1,0,0), peak: 6)],
                                                         .left: [centroidStroke(.init(-1,0,0), peak: 6)],
                                                         .undo: [centroidStroke(Vector3(-1,1,0).unit, peak: 20)]])
        XCTAssertTrue(similar.isValid)
        do {
            _ = try CentroidCalibration(captures: [.right: [centroidStroke(.init(1,0,0), peak: 6)],
                                                   .left: [centroidStroke(.init(-1,0,0), peak: 6)],
                                                   .undo: [centroidStroke(Vector3(-1,1,0).unit, peak: 7)]])
            XCTFail("weak, similar undo must be rejected")
        } catch { }
    }
    func testBothRecordingRegressionsAndSweep() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for (name, names, counts, score) in [
            ("natural-left15-right15-shake5-idle.csv", ["left","right","undo","idle"],
             [[0,6,1,3,1],[6,0,0,5,0],[0,0,1,0,0],[0,0,0,2,0]], 8),
            ("labelled-right10-left10-shake5-idle.csv", ["right","left","undo","idle"],
             [[4,0,0,0,0],[0,0,0,4,1],[0,0,0,2,0],[3,0,0,4,1]], -9)] {
            let labels = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.offset+1, $0.element) })
            let rows = try LabReplay.read(String(contentsOf: root.appendingPathComponent("research/data/"+name)))
            let training = try CentroidReplay.train(rows, labels: labels, count: 4)
            XCTAssertFalse(training.calibration.isValid)
            let result = CentroidReplay.evaluate(strokes: training.strokes, calibration: training.calibration,
                                                excludedThrough: training.excludedThrough, labels: labels)
            for segment in 1...4 {
                let c = result.confusion[segment]!
                XCTAssertEqual([c.right,c.left,c.undo,c.ambiguous,c.ignored], counts[segment-1])
            }
            XCTAssertEqual(result.score, score)
            XCTAssertTrue(result.events.allSatisfy { $0.detection.onset > (training.excludedThrough[$0.segment] ?? -.infinity) })
            let grid = CentroidReplay.sweep(training: training, labels: labels)
            XCTAssertEqual(grid.count, 600)
            XCTAssertEqual(grid.first?.result.score, name.hasPrefix("natural") ? 8 : 0)
            if name.hasPrefix("natural") { XCTAssertEqual(grid.first?.settings, CentroidSettings()) }
        }
    }
}
