import Foundation
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

private func assertNear(_ actual: Double, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
    if !actual.isFinite || abs(actual-expected) >= 1e-6 { XCTFail("\(actual) != \(expected)", file: file, line: line) }
}
private func motion(_ t: Double, _ v: Vector3) -> MotionSample {
    MotionSample(t: t, rotationRate: (v.x,v.y,v.z), gravity: (0,0,-1))
}
private func stroke(_ vectors: [Vector3], hz: Double = 25) -> FlickStroke {
    let segmenter = StrokeSegmenter()
    for i in 0..<Int(hz) { _ = segmenter.process(motion(Double(i)/hz, .init(0,0,0))) }
    var result: FlickStroke?
    for i in 0...Int((0.08*hz).rounded()) {
        let offset = Double(i)/hz, position = offset/0.04
        let index = min(1, Int(position)), fraction = position-Double(index)
        let vector = vectors[index] + (vectors[index+1]-vectors[index])*fraction
        result = segmenter.process(motion(1+offset, vector)) ?? result
    }
    return result!
}
private func stroke(_ vector: Vector3) -> FlickStroke { stroke([vector, vector, vector]) }
private func calibration() throws -> FlickCalibration {
    try FlickCalibration(right: [stroke(.init(8,0,0))], left: [stroke(.init(-8,0,0))])
}
private final class InstantStream {
    let detector: FlickDetector, dt: Double
    var t = 0.0
    var events: [FlickDetection] = []
    init(hz: Double = 25, reversed: Bool = false, instant: Bool = true) throws {
        dt = 1/hz
        detector = FlickDetector(calibration: try calibration(), reversed: reversed, instant: instant)
        add(0, duration: 0.4)
    }
    func add(_ x: Double, duration: Double) {
        for _ in 0..<Int((duration/dt).rounded()) {
            events += detector.process(motion(t, .init(x,0,0))); t += dt
        }
    }
}
final class InstantDetectorTests: XCTestCase {
    func testCalibratedFlickLatencyAndReturnAtBothRates() throws {
        for hz in [25.0,50.0] {
            for direction in [8.0,-8.0] {
                let s = try InstantStream(hz: hz)
                s.add(direction, duration: 0.12); s.add(0, duration: 0.04)
                s.add(-direction, duration: 0.12); s.add(0, duration: 1)
                XCTAssertEqual(s.events.map(\.event), [direction > 0 ? .right : .left])
                assertNear(s.events[0].t - s.events[0].onset, 0.08)
                s.add(direction, duration: 0.12)
                XCTAssertEqual(s.events.count, 2)
            }
        }
    }
    func testSummedCurvedLeftAndStraightRightAtBothRates() throws {
        let curved = [Vector3(4.2,0,0.9), Vector3(6.2,2.1,-6.3), Vector3(9.5,-6,0.6)]
        let c = try FlickCalibration(right: [stroke(.init(4,2,4))], left: [stroke(.init(4,0,-4))])
        for hz in [25.0, 50.0] {
            let captured = stroke(curved, hz: hz)
            assertNear(captured.sum.x, 19.9)
            assertNear(captured.sum.y, -3.9)
            assertNear(captured.sum.z, -4.8)
            assertNear(captured.peak, curved[2].magnitude)
            XCTAssertTrue(c.projection(captured) < -0.35*c.half)
            let detector = FlickDetector(calibration: c)
            for i in 0..<Int(hz) { _ = detector.process(motion(Double(i)/hz, .init(0,0,0))) }
            var events: [FlickDetection] = []
            for i in 0...Int((0.08*hz).rounded()) {
                let position = Double(i)/hz/0.04, index = min(1,Int(position))
                events += detector.process(motion(1+Double(i)/hz, curved[index]+(curved[index+1]-curved[index])*(position-Double(index))))
            }
            XCTAssertEqual(events.map(\.event), [.left])
            assertNear(stroke([.init(8,0,0),.init(8,0,0),.init(8,0,0)], hz: hz).sum.x, 24)
        }
    }
    func testShakeCompensatesOnlyFirstStrokeAndCooldown() throws {
        for hz in [25.0,50.0] {
            let s = try InstantStream(hz: hz)
            s.add(8, duration: 0.12); s.add(0, duration: 0.20)
            s.add(-8, duration: 0.12); s.add(0, duration: 0.04)
            s.add(8, duration: 0.12)
            // Three lobes only contain two sign changes.
            XCTAssertEqual(s.events.map(\.event), [.right])
            s.add(0, duration: 0.04); s.add(-8, duration: 0.12)
            XCTAssertEqual(s.events.map(\.event), [.right,.shake])
            XCTAssertEqual(s.events.last?.speculativeFlickAt, s.events.first?.t)
            s.add(8, duration: 0.12); s.add(-8, duration: 0.12); s.add(8, duration: 0.12)
            XCTAssertEqual(s.events.count, 2)
        }
    }
    func testHeldModeCancelsQuickShakeAndDeliversSingleAfter300ms() throws {
        let s = try InstantStream(instant: false)
        s.add(8, duration: 0.12); s.add(-8, duration: 0.04); s.add(8, duration: 0.04); s.add(-8, duration: 0.04)
        XCTAssertEqual(s.events.map(\.event), [.shake]); XCTAssertNil(s.events[0].speculativeFlickAt)
        s.add(0, duration: 1.2); s.add(8, duration: 0.12); s.add(0, duration: 0.4)
        XCTAssertEqual(s.events.map(\.event), [.shake,.right])
        XCTAssertTrue(s.events[1].t-s.events[1].onset >= 0.38-1e-6)
    }
    func testLateShakeCompensatesDeliveredHold() throws {
        let s = try InstantStream(instant: false)
        s.add(8, duration: 0.12); s.add(0, duration: 0.08)
        s.add(-8, duration: 0.12); s.add(0, duration: 0.08)
        s.add(8, duration: 0.12); s.add(0, duration: 0.08); s.add(-8, duration: 0.12)
        XCTAssertEqual(s.events.map(\.event), [.right,.shake])
        XCTAssertEqual(s.events.last?.speculativeFlickAt, s.events.first?.t)
    }
    func testUncalibratedInvalidAndGapStreamsCannotAct() throws {
        let empty = FlickDetector()
        for i in 0..<100 { XCTAssertTrue(empty.process(motion(Double(i)*0.04, .init(10,0,0))).isEmpty) }
        let s = try InstantStream(instant: false)
        s.add(8, duration: 0.12); s.t += 1; s.add(0, duration: 1)
        XCTAssertTrue(s.events.isEmpty)
        XCTAssertTrue(s.detector.process(motion(.nan, .init(8,0,0))).isEmpty)
        XCTAssertTrue(s.detector.process(motion(s.t, .init(.nan,0,0))).isEmpty)
        s.detector.reset(); s.add(0, duration: 0.4); s.add(8, duration: 0.12); s.add(0, duration: 0.4)
        XCTAssertEqual(s.events.count, 1)
    }
    func testReverseCalibrationValidationAndTraceFields() throws {
        let s = try InstantStream(reversed: true)
        var traces: [FlickTrace] = []; s.detector.onTrace = { traces.append($0) }
        s.add(8, duration: 0.12)
        XCTAssertEqual(s.events.map(\.event), [.left])
        XCTAssertTrue(traces[0].detail.contains("sR=")); XCTAssertTrue(traces[0].detail.contains("latency="))
        do { _ = try FlickCalibration(right: [stroke(.init(8,0,0))], left: [stroke(.init(8,0,0))]); XCTFail("identical directions") } catch {
            XCTAssertTrue(error.localizedDescription.contains("half 0.0"))
        }
        do { _ = try FlickCalibration(right: [stroke(.init(4.5,0,0))], left: [stroke(.init(-8,0,0))]); XCTFail("weak capture") } catch { }
        let c = try calibration(), encoded = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(FlickCalibration.self, from: encoded)
        XCTAssertEqual(decoded, c); XCTAssertTrue(decoded.isValid)
        assertNear(c.half, 24); assertNear(c.mid, 0)
        assertNear(c.peakMin, 5.2)
        XCTAssertEqual(FlickCalibration.defaultsKey, "flickCalibrationV3")
    }
    func testContinuousQuietArmingAndWeakIdleRejection() throws {
        let s = try InstantStream()
        // Quiet cannot remain latched through movement between quiet and onset.
        s.add(3.2, duration: 0.4); s.add(8, duration: 0.12)
        XCTAssertTrue(s.events.isEmpty)
        s.add(0, duration: 0.4); s.add(4.7, duration: 0.12); s.add(0, duration: 0.4)
        s.add(5.1, duration: 0.12); s.add(0, duration: 0.4)
        XCTAssertTrue(s.events.isEmpty)
        s.add(8, duration: 0.12)
        XCTAssertEqual(s.events.map(\.event), [.right])
    }
    func testExpiredShakeLobesDoNotSuppressLaterFlick() throws {
        let s = try InstantStream()
        s.add(8, duration: 0.12); s.add(-8, duration: 0.12)
        s.add(0, duration: 1); s.add(8, duration: 0.12)
        XCTAssertEqual(s.events.map(\.event), [.right,.right])
        s.add(0, duration: 1); s.add(-8, duration: 0.12)
        XCTAssertEqual(s.events.map(\.event), [.right,.right,.left])
    }
    func testCalibrationSessionRequiresSixStrongCapturesAndShowsQuality() throws {
        let session = FlickCalibrationSession()
        var t = 0.0
        func add(_ x: Double, _ duration: Double) {
            for _ in 0..<Int((duration/0.04).rounded()) { _ = session.process(motion(t, .init(x,0,0))); t += 0.04 }
        }
        func capture(_ x: Double) { add(0,1); add(x,0.12) }
        capture(4.5)
        XCTAssertEqual(session.right.count, 0); XCTAssertTrue(session.prompt.contains("A bit sharper"))
        for _ in 0..<6 { capture(8) }
        XCTAssertEqual(session.right.count, 6); XCTAssertTrue(session.prompt.contains("LEFT 6"))
        for _ in 0..<5 { capture(-8) }
        XCTAssertNil(session.calibration)
        capture(-8)
        XCTAssertTrue(session.calibration?.isValid == true); XCTAssertTrue(session.prompt.contains("half 24.0"))
        let bad = FlickCalibrationSession()
        t = 0
        for _ in 0..<12 {
            for _ in 0..<25 { _ = bad.process(motion(t, .init(0,0,0))); t += 0.04 }
            for _ in 0..<3 { _ = bad.process(motion(t, .init(8,0,0))); t += 0.04 }
        }
        XCTAssertNil(bad.calibration); XCTAssertEqual(bad.right.count,0); XCTAssertEqual(bad.left.count,0)
        XCTAssertTrue(bad.prompt.contains("more distinctly")); XCTAssertTrue(bad.prompt.contains("half 0.0"))
    }
    func testWeakProjectionLobesCannotMakeShake() throws {
        let s = try InstantStream()
        for x in [1.0,-1.0,1.0,-1.0] {
            for _ in 0..<3 {
                s.events += s.detector.process(motion(s.t, .init(x,8,0))); s.t += s.dt
            }
        }
        XCTAssertTrue(s.events.isEmpty)
    }
    func testPrototypeParityAt25Hz() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let rows = try LabReplay.read(String(contentsOf: root.appendingPathComponent("research/data/labelled-right10-left10-shake5-idle.csv")))
        let settings = FlickSettings(quietTime: 0.3, onset: 4, peakMin: 5, shakeLobe: 3, shakeWindow: 0.7)
        let actual = ReplayEvaluation.segment(rows, settings: settings)
        var segment = 0, samples: [(Int, MotionSample)] = []
        for row in rows {
            if let marker = row.marker { segment = marker }
            if let sample = row.motion { samples.append((segment, sample)) }
        }
        // Independent reference: the supplied Python prototype's three raw samples.
        var last = -Double.infinity, reference: [Int: [(Vector3, Double)]] = [:]
        for i in 0..<(samples.count-2) {
            let (segment, sample) = samples[i], magnitude = Vector3(sample.rotationRate).magnitude
            if magnitude > 4 && sample.t-last > 0.3 {
                let vectors = samples[i...i+2].map { Vector3($0.1.rotationRate) }
                reference[segment, default: []].append((vectors.reduce(.init(0,0,0), +), vectors.map(\.magnitude).max()!))
            }
            if magnitude > 3 { last = sample.t }
        }
        for segment in reference.keys {
            XCTAssertEqual(actual[segment]?.count, reference[segment]?.count)
            for (stroke, ref) in zip(actual[segment, default: []], reference[segment, default: []]) {
                assertNear(stroke.sum.x, ref.0.x); assertNear(stroke.sum.y, ref.0.y); assertNear(stroke.sum.z, ref.0.z)
                assertNear(stroke.peak, ref.1)
            }
        }
        XCTAssertEqual(actual[1]?.count,8); XCTAssertEqual(actual[2]?.count,6)
        // The prototype includes weak calibration candidates. Retain that baseline
        // here only; production calibration rejects those candidates as requested.
        func mean(_ segment: Int) -> Vector3 { actual[segment]!.prefix(3).reduce(.init(0,0,0)) { $0 + $1.sum } * (1.0/3) }
        let r = mean(1), l = mean(2), axis = (r-l).unit
        let mid = (axis.dot(r)+axis.dot(l))/2, half = (axis.dot(r)-axis.dot(l))/2
        XCTAssertEqual(actual[1]!.filter { $0.peak >= 5 && axis.dot($0.sum)-mid > 0.35*half }.count,8)
        XCTAssertEqual(actual[2]!.filter { $0.peak >= 5 && axis.dot($0.sum)-mid < -0.35*half }.count,4)
    }
    func testLabelledRecordingMeasuredRegressionAndSilentBud() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let rows = try LabReplay.read(String(contentsOf: root.appendingPathComponent("research/data/labelled-right10-left10-shake5-idle.csv")))
        let labels = [1:"right",2:"left",3:"shake",4:"idle"]
        for n in [3,5] {
            let training = try ReplayEvaluation.train(rows, labels: labels, count: n)
            let result = LabReplay.run(rows, detector: FlickDetector(calibration: training.calibration))
            let heldOut = ReplayEvaluation.heldOut(result, training: training)
            let metrics = ReplayEvaluation.metrics(heldOut, labels: labels)
            XCTAssertEqual(metrics.right, n == 3 ? 5 : 3)
            XCTAssertEqual(metrics.left, n == 3 ? 2 : 0)
            XCTAssertEqual(metrics.shakes, n == 3 ? 3 : 2)
            XCTAssertEqual(metrics.idle, 0); XCTAssertEqual(metrics.wrong,0)
            XCTAssertEqual(training.strokes[1]?.count,8); XCTAssertEqual(training.strokes[2]?.count,9)
            XCTAssertEqual(training.remaining(in: 1),8-n); XCTAssertEqual(training.remaining(in: 2),7-n)
            XCTAssertEqual(training.rejected[2],2)
            XCTAssertTrue(heldOut.filter { $0.detection.event != .shake }.allSatisfy { abs($0.detection.t-$0.detection.onset-0.08) < 1e-6 })
            XCTAssertTrue(heldOut.allSatisfy { $0.detection.onset > (training.excludedThrough[$0.segment] ?? -.infinity) })
            let other = try LabReplay.read(String(contentsOf: root.appendingPathComponent("research/data/two-buds-left-right-both.csv")))
            let replay = LabReplay.run(other, detector: FlickDetector(calibration: training.calibration))
            XCTAssertEqual(replay.events.filter { $0.segment == 2 }.count, 0)
            let budNet = ReplayEvaluation.netEvents(replay.events)
            XCTAssertEqual(budNet.filter { $0.detection.event == .left }.count,5)
            XCTAssertEqual(budNet.filter { $0.detection.event == .right }.count,n == 3 ? 2 : 0)
            XCTAssertEqual(budNet.filter { $0.detection.event == .shake }.count,0)
            let free = try LabReplay.read(String(contentsOf: root.appendingPathComponent("research/data/handheld-free-flicks.csv")))
            let freeResult = LabReplay.run(free, detector: FlickDetector(calibration: training.calibration))
            let freeNet = ReplayEvaluation.netEvents(freeResult.events)
            XCTAssertEqual(freeNet.filter { $0.detection.event == .right }.count,2)
            XCTAssertEqual(freeNet.filter { $0.detection.event == .left }.count,4)
            XCTAssertEqual(freeNet.filter { $0.detection.event == .shake }.count,1)
        }
    }
}
