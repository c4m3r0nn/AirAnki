import Foundation
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

private final class MotionStream {
    let detector: LegacyFlickDetector
    let dt: Double
    var t = 0.0
    var events: [FlickDetection] = []
    var traces: [FlickTrace] = []
    init(hz: Double, sensitivity: FlickSensitivity = .medium, reversed: Bool = false) {
        dt = 1 / hz
        detector = LegacyFlickDetector(sensitivity: sensitivity, reversed: reversed)
        detector.onTrace = { [weak self] in self?.traces.append($0) }
        add(0, for: 1)
    }
    func add(_ yaw: Double, for duration: Double, transverse: Double = 0) {
        for _ in 0..<Int((duration / dt).rounded()) {
            events += detector.process(MotionSample(t: t, rotationRate: (transverse, 0, -yaw), gravity: (0, 0, -1)))
            t += dt
        }
    }
    var kinds: [FlickEvent] { events.map(\.event) }
}

final class FlickDetectorTests: XCTestCase {
    func testCleanRightAndLeftAtBothRates() {
        for hz in [25.0, 50.0] {
            for yaw in [10.0, -10.0] {
                let s = MotionStream(hz: hz)
                s.add(yaw, for: 0.24); s.add(0, for: 1)
                XCTAssertEqual(s.kinds, [yaw > 0 ? .right : .left])
                XCTAssertTrue(abs(s.detector.sampleInterval - 1 / hz) < 0.00001)
                XCTAssertEqual(s.traces.filter { $0.event != nil }.count, 1)
                XCTAssertTrue(s.traces.last!.detail.contains("angle="))
                XCTAssertTrue(s.traces.last!.detail.contains("peak="))
            }
        }
    }

    func testReturnSwingNeverCountsEvenWhenItPeaksLate() {
        for hz in [25.0, 50.0] {
            let s = MotionStream(hz: hz)
            s.add(10, for: 0.24); s.add(0, for: 0.08)
            s.add(-3, for: 0.64); s.add(-10, for: 0.24); s.add(0, for: 1)
            XCTAssertEqual(s.kinds, [.right])
            XCTAssertTrue(s.traces.contains { $0.reason == "return swing" })
        }
    }

    func testWindUpThenFlickAtBothRates() {
        for hz in [25.0, 50.0] {
            for duration in [0.08, 0.14] { // compact impulse and the original 55–75° short turn
                let s = MotionStream(hz: hz)
                s.add(8, for: duration); s.add(0, for: 0.04)
                s.add(-10, for: 0.24); s.add(0, for: 1)
                XCTAssertEqual(s.kinds, [.left])
                XCTAssertTrue(s.traces.contains { $0.reason == "pull back before a flick" })
            }
        }
    }

    func testSlowTurnsAndNonHorizontalTurnsAreRejected() {
        for hz in [25.0, 50.0] {
            let s = MotionStream(hz: hz)
            s.add(3, for: 2); s.add(0, for: 1)
            s.add(10, for: 0.24, transverse: 25); s.add(0, for: 1)
            XCTAssertTrue(s.events.isEmpty)
            XCTAssertTrue(s.traces.contains { $0.reason == "not horizontal" })
        }
    }

    func testThreeStrokeShakeSuppressesFlickAndCoolsDown() {
        for hz in [25.0, 50.0] {
            for reversed in [false, true] {
                let s = MotionStream(hz: hz, reversed: reversed)
                s.add(12, for: 0.12); s.add(0, for: 0.04)
                s.add(-12, for: 0.12); s.add(0, for: 0.04)
                s.add(12, for: 0.12); s.add(0, for: 0.04)
                s.add(-12, for: 0.24); s.add(0, for: 1.2)
                XCTAssertEqual(s.kinds, [.shake])
                XCTAssertTrue(s.traces.contains { $0.reason == "cancelled by shake" })
                s.add(10, for: 0.24); s.add(0, for: 1)
                XCTAssertEqual(s.kinds, [.shake, reversed ? .left : .right])
            }
        }
    }

    func testTwoFlicksOneSecondApart() {
        for hz in [25.0, 50.0] {
            for second in [10.0, -10.0] {
                let s = MotionStream(hz: hz)
                s.add(10, for: 0.24); s.add(0, for: 0.76)
                s.add(second, for: 0.24); s.add(0, for: 1)
                XCTAssertEqual(s.kinds, [.right, second > 0 ? .right : .left])
            }
        }
    }

    func testReverseAndActionMapping() {
        for hz in [25.0, 50.0] {
            let s = MotionStream(hz: hz, reversed: true)
            s.add(10, for: 0.24); s.add(0, for: 0.76)
            s.add(-10, for: 0.24); s.add(0, for: 1)
            XCTAssertEqual(s.kinds, [.left, .right])
        }
        XCTAssertEqual(FlickEvent.left.action(), .showOrGrade(ease: 1))
        XCTAssertEqual(FlickEvent.right.action(), .showOrGrade(ease: 4))
        XCTAssertEqual(FlickEvent.right.action(easeForRight: 3), .showOrGrade(ease: 3))
        XCTAssertEqual(FlickEvent.right.action(easeForRight: 1), .showOrGrade(ease: 4))
        XCTAssertEqual(FlickEvent.shake.action(), .undo)
    }

    func testSensitivityScalesFlickAndShakePeaks() {
        for hz in [25.0, 50.0] {
            for sensitivity in FlickSensitivity.allCases {
                let s = MotionStream(hz: hz, sensitivity: sensitivity)
                s.add(5.2, for: 0.4); s.add(0, for: 1)
                XCTAssertEqual(s.kinds, sensitivity == .high ? [.right] : [])
                let medium = MotionStream(hz: hz, sensitivity: sensitivity)
                medium.add(6.5, for: 0.32); medium.add(0, for: 1)
                XCTAssertEqual(medium.kinds, sensitivity == .low ? [] : [.right])
                let shake = MotionStream(hz: hz, sensitivity: sensitivity)
                for yaw in [4.5, -4.5, 4.5] { shake.add(yaw, for: 0.12); shake.add(0, for: 0.04) }
                shake.add(0, for: 1)
                XCTAssertEqual(shake.kinds, sensitivity == .low ? [] : [.shake])
            }
        }
    }

    func testFastSampleRequirementAdaptsToMeasuredRate() {
        for hz in [25.0, 50.0] {
            let s = MotionStream(hz: hz)
            s.add(9, for: 1 / hz); s.add(4, for: 0.24); s.add(0, for: 1)
            XCTAssertEqual(s.kinds, hz == 25 ? [.right] : [])
        }
    }

    func testCompactImpulseAndShortAngleWaitBeforeDelivery() {
        for hz in [25.0, 50.0] {
            for duration in [0.08, 0.14] {
                let s = MotionStream(hz: hz)
                let start = s.t
                s.add(8, for: duration); s.add(0, for: 0.6)
                XCTAssertTrue(s.events.isEmpty)
                s.add(0, for: 0.6)
                XCTAssertEqual(s.kinds, [.right])
                XCTAssertTrue(s.events[0].t >= start + duration - s.dt + LegacyFlickDetector.windupWait + LegacyFlickDetector.shakeHold)
            }
        }
    }

    func testEveryFullFlickWaitsForShakeHold() {
        for hz in [25.0, 50.0] {
            let s = MotionStream(hz: hz)
            let start = s.t
            s.add(10, for: 0.24); s.add(0, for: 0.24)
            XCTAssertTrue(s.events.isEmpty)
            s.add(0, for: 0.4)
            XCTAssertEqual(s.kinds, [.right])
            XCTAssertTrue(s.events[0].t >= start + LegacyFlickDetector.minAngle / 10 - s.dt + LegacyFlickDetector.shakeHold)
        }
    }

    func testStallResetAndInvalidSamplesCannotReleaseHeldFlicks() {
        for hz in [25.0, 50.0] {
            let s = MotionStream(hz: hz)
            s.add(10, for: 0.24)
            XCTAssertTrue(s.detector.process(MotionSample(t: .nan, rotationRate: (0, 0, 0), gravity: (0, 0, -1))).isEmpty)
            XCTAssertTrue(s.detector.process(MotionSample(t: 0, rotationRate: (0, 0, 0), gravity: (0, 0, -1))).isEmpty)
            s.t += 2
            s.add(0, for: 1)
            XCTAssertTrue(s.events.isEmpty)
            XCTAssertTrue(s.traces.contains { $0.reason.contains("stream gap") })
            s.add(10, for: 0.24); s.detector.reset(); s.add(0, for: 1)
            XCTAssertTrue(s.events.isEmpty)
        }
    }

    func testShakeRequiresAlternationAndOneSecondWindow() {
        for hz in [25.0, 50.0] {
            let same = MotionStream(hz: hz)
            for _ in 0..<3 { same.add(4.5, for: 0.12); same.add(0, for: 0.04) }
            same.add(0, for: 1)
            XCTAssertTrue(same.events.isEmpty)
            let slow = MotionStream(hz: hz)
            for yaw in [4.5, -4.5, 4.5] { slow.add(yaw, for: 0.12); slow.add(0, for: 0.5) }
            slow.add(0, for: 1)
            XCTAssertTrue(slow.events.isEmpty)
        }
    }

    func testSampleGapPreservesCooldownAndReturnSuppression() {
        for hz in [25.0, 50.0] {
            let s = MotionStream(hz: hz)
            for yaw in [12.0, -12.0, 12.0] { s.add(yaw, for: 0.12); s.add(0, for: 0.04) }
            s.t += 0.24
            s.add(-12, for: 0.16); s.add(0, for: 1)
            XCTAssertEqual(s.kinds, [.shake])
            let returning = MotionStream(hz: hz)
            returning.add(10, for: 0.16)
            returning.t += 0.24
            returning.add(-10, for: 0.24); returning.add(0, for: 1)
            // The first held flick is discarded by the gap, and its return is blocked.
            XCTAssertTrue(returning.events.isEmpty)
            XCTAssertTrue(returning.traces.contains { $0.reason == "return swing" })
        }
    }

    func testRecordingRegression() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("research/data/two-buds-left-right-both.csv"), encoding: .utf8)
        let result = LabReplay.run(try LabReplay.read(text), detector: LegacyFlickDetector())
        XCTAssertEqual(result.segments, [0, 1, 2, 3, 4])
        XCTAssertEqual(result.events.filter { $0.segment == 2 }.count, 0)
        XCTAssertTrue(result.events.filter { $0.segment == 1 || $0.segment == 3 }.count >= 7)
        XCTAssertEqual(result.events.filter { $0.segment == 0 || $0.segment == 4 }.count, 0)
    }

    func testReplayParsesQuotedFieldsAndRejectsBrokenMotion() throws {
        let csv = LabCSV.header
            + LabCSV.row(monotonic: 1, wallISO: "date", event: "marker", marker: 1, detail: "comma, \"quote\"\nnewline")
            + LabCSV.row(monotonic: 2, wallISO: "date", event: "motion", values: Array(repeating: 0, count: 14))
        let rows = try LabReplay.read(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].marker, 1)
        XCTAssertEqual(rows[1].motion?.t, 2)
        for bad in ["wrong,header\n", LabCSV.header + "2,,motion\n", csv + "\"unterminated"] {
            do { _ = try LabReplay.read(bad); XCTFail("Expected malformed CSV to fail") } catch { }
        }
    }
}
