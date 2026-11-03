import Foundation
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

final class StemCommandTests: XCTestCase {
    func testDefaultMappingIgnoresExplicitPlayPause() {
        XCTAssertNil(StemCommand.play.gesture())
        XCTAssertNil(StemCommand.pause.gesture())
        XCTAssertEqual(StemCommand.togglePlayPause.gesture(), .single)
        XCTAssertEqual(StemCommand.nextTrack.gesture(), .double)
        XCTAssertEqual(StemCommand.previousTrack.gesture(), .triple)
    }

    func testAllCommandsUnderBothFilterSettings() {
        for ignore in [true, false] {
            for command in StemCommand.allCases {
                let expected: Gesture?
                switch command {
                case .play, .pause: expected = ignore ? nil : .single
                case .togglePlayPause: expected = .single
                case .nextTrack: expected = .double
                case .previousTrack: expected = .triple
                }
                XCTAssertEqual(command.gesture(ignoreExplicitPlayPause: ignore), expected)
            }
        }
    }

    func testPreferenceDefaultsToFilteringAndRespectsOptOut() {
        let defaults = UserDefaults(suiteName: "local.airanki.tests.\(UUID().uuidString)")!
        XCTAssertTrue(StemCommand.ignoreExplicitPlayPause(in: defaults))
        for ignore in [false, true] {
            defaults.setVolatileDomain(["ignoreExplicitPlayPause": ignore], forName: UserDefaults.argumentDomain)
            XCTAssertEqual(StemCommand.ignoreExplicitPlayPause(in: defaults), ignore)
        }
    }

    func testIgnoredEventsRetainRawCommandTimeAndCSVDetail() {
        let date = Date(timeIntervalSince1970: 1000)
        for command in [StemCommand.play, .pause] {
            let event = StemEvent(command: command, time: 42.5, wall: date)
            XCTAssertNil(event.gesture)
            XCTAssertEqual(event.initialOutcome, "ignored (ear detection?)")
            XCTAssertEqual(event.time, 42.5)
            XCTAssertEqual(event.wall, date)
            let csv = LabCSV.row(monotonic: event.time, wallISO: "date", event: event.csvEvent,
                                 rawCommand: event.command.rawValue, detail: event.detail)
            let fields = csv.trimmingCharacters(in: .newlines).components(separatedBy: ",")
            XCTAssertEqual(fields.count, 21)
            XCTAssertEqual(fields[2], "stem_ignored")
            XCTAssertEqual(fields[18], command.rawValue)
            XCTAssertEqual(fields[20], "ignored-ear-detection")
        }
    }

    func testOptedInAndPausedEventsHaveAccurateDisposition() {
        let event = StemEvent(command: .play, time: 0, wall: Date(), ignoreExplicitPlayPause: false)
        XCTAssertEqual(event.gesture, .single)
        XCTAssertEqual(event.csvEvent, "stem_single")
        XCTAssertEqual(event.detail, "")
        let stale = StemEvent(command: .togglePlayPause, time: 0, wall: Date(), isListening: false)
        XCTAssertNil(stale.gesture)
        XCTAssertEqual(stale.csvEvent, "stem_ignored")
        XCTAssertEqual(stale.detail, "ignored-remote-paused")
    }

    func testLateActionCompletionCannotOverwriteNewerIgnoredEvent() {
        let press = StemEvent(command: .togglePlayPause, time: 0, wall: Date())
        let ignored = StemEvent(command: .pause, time: 1, wall: Date())
        var status = LastPressStatus()
        status.record(press)
        status.record(ignored)
        status.complete(press, outcome: "Graded Easy")
        XCTAssertEqual(status.event?.id, ignored.id)
        XCTAssertEqual(status.outcome, "ignored (ear detection?)")
        XCTAssertTrue(status.title.contains("pause"))
        XCTAssertFalse(status.title.contains("Graded Easy"))
    }

    func testLastPressIncludesGestureRawCommandTimeAndAction() {
        var status = LastPressStatus()
        XCTAssertEqual(status.title, "No presses yet")
        let event = StemEvent(command: .togglePlayPause, time: 0, wall: Date(timeIntervalSince1970: 1000))
        status.record(event)
        status.complete(event, outcome: GestureOutcome.completed(.showedAnswer).title)
        XCTAssertTrue(status.title.contains("Single"))
        XCTAssertTrue(status.title.contains("togglePlayPause"))
        XCTAssertTrue(status.title.contains(event.wall.formatted(date: .omitted, time: .standard)))
        XCTAssertTrue(status.title.contains("Showed answer"))
    }
}

final class ConnectionSettingsTests: XCTestCase {
    func testDefaultAndStoredPortValidation() {
        let defaults = UserDefaults(suiteName: "local.airanki.tests.\(UUID().uuidString)")!
        XCTAssertEqual(AnkiConnectionSettings.port(in: defaults), 8765)
        for port in [-1, 0, 1, 9876, 65535, 65536] {
            defaults.setVolatileDomain(["ankiConnectPort": port], forName: UserDefaults.argumentDomain)
            XCTAssertEqual(AnkiConnectionSettings.port(in: defaults), (1...65535).contains(port) ? port : 8765)
        }
    }

    func testPortFieldRejectsHostsPathsFractionsAndOutOfRangeValues() {
        for text in ["", "0", "-1", "65536", "8765.0", "localhost:8765", "8765/api/v1", "12x", "+8765", "１２３", String(repeating: "9", count: 30)] {
            XCTAssertNil(AnkiConnectionSettings.parsePort(text))
        }
        XCTAssertEqual(AnkiConnectionSettings.parsePort(" 9876\n"), 9876)
        XCTAssertEqual(AnkiConnectionSettings.parsePort("1"), 1)
        XCTAssertEqual(AnkiConnectionSettings.parsePort("65535"), 65535)
    }
}
