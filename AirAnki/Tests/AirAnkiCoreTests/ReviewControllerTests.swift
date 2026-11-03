import Foundation
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

@MainActor
private final class MockAnkiClient: AnkiClient {
    var state: ReviewerState
    var calls: [String] = []
    var unreachable = false
    var suspendRead = false
    var suspended: CheckedContinuation<Void, Never>?
    var failShow = false
    var finishReviewAfterGrade = false
    var failReadAfterGrade = false

    init(_ state: ReviewerState = .question) { self.state = state }
    func reviewerState() async throws -> ReviewerState {
        calls.append("state")
        if suspendRead {
            suspendRead = false
            await withCheckedContinuation { suspended = $0 }
        }
        if unreachable { throw AnkiError.message("Anki unreachable") }
        return state
    }
    func ping() async throws { calls.append("ping") }
    func showAnswer() async throws {
        calls.append("show")
        if failShow { throw AnkiError.message("show failed") }
        state = .answer
    }
    func answer(ease: Int) async throws {
        calls.append("answer:\(ease)")
        state = finishReviewAfterGrade ? .notReviewing : .question
        if failReadAfterGrade { unreachable = true }
    }
    func undo() async throws { calls.append("undo"); state = .answer }
}

final class ReviewControllerTests: XCTestCase {
    @MainActor func testCentroidMappingOnBothSidesAndOutsideReview() async {
        for state in [ReviewerState.question, .answer, .notReviewing] {
            for event in [FlickEvent.right, .left, .undo, .ambiguous] {
                let mock = MockAnkiClient(state)
                let target = ReviewController(client: mock)
                let outcome = await target.handleFlick(.init(t: 1, event: event), easeForRight: 3)
                if state == .notReviewing {
                    XCTAssertEqual(outcome, .notReviewing); XCTAssertEqual(mock.calls, ["state"])
                } else if event == .undo {
                    XCTAssertEqual(outcome, .completed(.undone)); XCTAssertEqual(mock.calls, ["state","undo","state"])
                } else if state == .question {
                    XCTAssertEqual(outcome, .completed(.showedAnswer)); XCTAssertEqual(mock.calls, ["state","show","state"])
                } else if event == .ambiguous {
                    XCTAssertEqual(outcome, .completed(.unclear)); XCTAssertEqual(mock.calls, ["state","state"])
                } else {
                    XCTAssertEqual(outcome, .completed(.graded(event == .left ? 1 : 3)))
                }
            }
        }
    }

    @MainActor func testMotionAndStemsShareQuietPeriodAndBusyLock() async {
        let mock = MockAnkiClient(); let controller = ReviewController(client: mock)
        let shown = await controller.handleAction(.showOrGrade(ease: 1), at: 0)
        XCTAssertEqual(shown, .completed(.showedAnswer))
        let stem = await controller.handleWithOutcome(.single, at: 0.06)
        XCTAssertEqual(stem, .discarded("debounce"))
        let motion = await controller.handleAction(.showOrGrade(ease: 4), at: 0.1)
        XCTAssertEqual(motion, .discarded("debounce"))
        mock.suspendRead = true
        let first = Task { await controller.handleAction(.showOrGrade(ease: 1), at: 1) }
        while mock.suspended == nil { await Task.yield() }
        let busy = await controller.handleAction(.undo, at: 2)
        XCTAssertEqual(busy, .discarded("busy"))
        mock.suspended?.resume(); mock.suspended = nil
        let graded = await first.value
        XCTAssertEqual(graded, .completed(.graded(1)))
        XCTAssertEqual(mock.calls, ["state", "show", "state", "state", "answer:1", "state"])
    }

    @MainActor func testMotionOutsideReviewHasNoMutations() async {
        for action in [RemoteAction.showOrGrade(ease: 1), .showOrGrade(ease: 4), .undo] {
            let mock = MockAnkiClient(.notReviewing); let controller = ReviewController(client: mock)
            let outcome = await controller.handleAction(action, at: 0)
            XCTAssertEqual(outcome, .notReviewing)
            XCTAssertEqual(mock.calls, ["state"])
        }
    }

    @MainActor func testActionOutcomesDescribeActualResultAndDroppedGestures() async {
        let mock = MockAnkiClient(); let controller = ReviewController(client: mock)
        let shown = await controller.handleWithOutcome(.single, at: 0)
        XCTAssertEqual(shown, .completed(.showedAnswer))
        let debounce = await controller.handleWithOutcome(.single, at: 0.06)
        XCTAssertEqual(debounce, .discarded("debounce"))
        controller.easeForSingle = 3
        let graded = await controller.handleWithOutcome(.single, at: 1)
        XCTAssertEqual(graded, .completed(.graded(3)))
        XCTAssertEqual(graded.title, "Graded Good")
        controller.mapping.double = .none
        let disabled = await controller.handleWithOutcome(.double, at: 2)
        XCTAssertEqual(disabled, .discarded("mapped to Do nothing"))
        mock.state = .notReviewing
        let inactive = await controller.handleWithOutcome(.single, at: 3)
        XCTAssertEqual(inactive, .notReviewing)
        XCTAssertEqual(inactive.title, "No action (not reviewing)")
    }

    @MainActor func testCompletedGradeIsReportedWhenStatusRefreshFails() async {
        let mock = MockAnkiClient(.answer); mock.failReadAfterGrade = true
        let controller = ReviewController(client: mock)
        let outcome = await controller.handleWithOutcome(.single, at: 0)
        XCTAssertEqual(outcome, .failed("Anki unreachable", completedAction: .graded(4)))
        XCTAssertTrue(outcome.title.contains("Graded Easy; status refresh failed"))
        XCTAssertEqual(mock.calls, ["state", "answer:4", "state", "state"])
    }

    @MainActor func testLiveRefreshIsReadOnlyAndSharesActionLock() async {
        let mock = MockAnkiClient(); let controller = ReviewController(client: mock)
        await controller.refresh(redetect: false)
        XCTAssertEqual(mock.calls, ["state"])
        mock.state = .notReviewing
        await controller.refresh(redetect: false)
        XCTAssertEqual(controller.status, .ready(.notReviewing))
        mock.state = .question
        mock.suspendRead = true
        let first = Task { await controller.handle(.single, at: 0) }
        while mock.suspended == nil { await Task.yield() }
        let count = mock.calls.count
        await controller.refresh(redetect: false)
        XCTAssertEqual(mock.calls.count, count)
        let busy = await controller.handleWithOutcome(.double, at: 1)
        XCTAssertEqual(busy, .discarded("busy"))
        mock.suspended?.resume(); mock.suspended = nil
        _ = await first.value
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor func testBusyNotificationsIncludeUnlockAfterError() async {
        let mock = MockAnkiClient(); mock.unreachable = true
        let controller = ReviewController(client: mock)
        var states: [Bool] = []
        controller.onBusyChange = { states.append(controller.isBusy) }
        await controller.refresh()
        XCTAssertEqual(states, [true, false])
        XCTAssertEqual(controller.status, .error("Anki unreachable"))
        controller.onBusyChange = nil
    }

    @MainActor func testSingleQuestionShowsAnswer() async {
        let mock = MockAnkiClient(); let controller = ReviewController(client: mock)
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.single, at: 0)
        XCTAssertEqual(mock.calls, ["state", "show", "state"])
        XCTAssertEqual(controller.status, .ready(.answer))
        XCTAssertEqual(feedback, .showedAnswer)
    }

    @MainActor func testSingleAnswerGradesEasy() async {
        let mock = MockAnkiClient(.answer); let controller = ReviewController(client: mock)
        await controller.handle(.single, at: 0)
        XCTAssertEqual(mock.calls, ["state", "answer:4", "state"])
    }

    @MainActor func testSingleAnswerCanGradeGood() async {
        let mock = MockAnkiClient(.answer); let controller = ReviewController(client: mock)
        controller.easeForSingle = 3
        await controller.handle(.single, at: 0)
        XCTAssertEqual(mock.calls, ["state", "answer:3", "state"])
    }

    @MainActor func testDoubleQuestionShowsThenGradesAgain() async {
        let mock = MockAnkiClient(); let controller = ReviewController(client: mock)
        await controller.handle(.double, at: 0)
        XCTAssertEqual(mock.calls, ["state", "show", "answer:1", "state"])
    }

    @MainActor func testDoubleAnswerGradesAgain() async {
        let mock = MockAnkiClient(.answer); let controller = ReviewController(client: mock)
        await controller.handle(.double, at: 0)
        XCTAssertEqual(mock.calls, ["state", "answer:1", "state"])
    }

    @MainActor func testTripleUndoes() async {
        for state in [ReviewerState.question, .answer] {
            let mock = MockAnkiClient(state); let controller = ReviewController(client: mock)
            await controller.handle(.triple, at: 0)
            XCTAssertEqual(mock.calls, ["state", "undo", "state"])
        }
    }

    @MainActor func testNotReviewingHasNoMutationsForAnyGesture() async {
        for gesture in Gesture.allCases {
            let mock = MockAnkiClient(.notReviewing); let controller = ReviewController(client: mock)
            await controller.handle(gesture, at: 0)
            XCTAssertEqual(mock.calls, ["state"])
            XCTAssertEqual(controller.status, .ready(.notReviewing))
        }
    }

    @MainActor func testUnreachableSurfacesErrorAndUnlocks() async {
        let mock = MockAnkiClient(); mock.unreachable = true
        let controller = ReviewController(client: mock)
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.single, at: 0)
        XCTAssertEqual(controller.status, .error("Anki unreachable"))
        XCTAssertEqual(feedback, .error)
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(mock.calls.allSatisfy { $0 == "state" })
    }

    @MainActor func testRapidDuplicateGesturesOnlyActOnce() async {
        let mock = MockAnkiClient(); let controller = ReviewController(client: mock)
        await controller.handle(.single, at: 0)
        let accepted = await controller.handle(.single, at: 0.06)
        XCTAssertFalse(accepted)
        XCTAssertEqual(mock.calls, ["state", "show", "state"])
    }

    @MainActor func testOverlappingActionIsDroppedAndNeverQueued() async {
        let mock = MockAnkiClient(); mock.suspendRead = true
        let controller = ReviewController(client: mock)
        let first = Task { await controller.handle(.single, at: 0) }
        while mock.suspended == nil { await Task.yield() }
        let second = await controller.handle(.double, at: 1)
        XCTAssertFalse(second)
        mock.suspended?.resume(); mock.suspended = nil
        _ = await first.value
        XCTAssertEqual(mock.calls, ["state", "show", "state"])
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor func testFailedShowDoesNotGradeOrRetry() async {
        let mock = MockAnkiClient(); mock.failShow = true
        let controller = ReviewController(client: mock)
        await controller.handle(.double, at: 0)
        XCTAssertEqual(mock.calls, ["state", "show", "state"])
        XCTAssertEqual(controller.status, .error("show failed"))
    }

    @MainActor func testPostActionRefreshDetectsFinishedDeck() async {
        let mock = MockAnkiClient(.answer); mock.finishReviewAfterGrade = true
        let controller = ReviewController(client: mock)
        await controller.handle(.single, at: 0)
        XCTAssertEqual(controller.status, .ready(.notReviewing))
    }

    @MainActor func testDisabledMappingMakesNoCalls() async {
        let mock = MockAnkiClient(); let controller = ReviewController(client: mock)
        controller.mapping.single = .none
        let result = await controller.handle(.single, at: 0)
        XCTAssertFalse(result)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testDebouncerBoundaryAndSlidingQuietPeriod() {
        var debouncer = Debouncer()
        XCTAssertTrue(debouncer.accept(at: 0))
        XCTAssertFalse(debouncer.accept(at: 0.06))
        XCTAssertFalse(debouncer.accept(at: 0.1))
        XCTAssertTrue(debouncer.accept(at: 1))
        var boundary = Debouncer()
        XCTAssertTrue(boundary.accept(at: 0))
        XCTAssertTrue(boundary.accept(at: Debouncer.threshold))
    }

    func testMappingCanRoundTripWithoutWritingPreferences() {
        // A volatile domain avoids writing to ~/Library/Preferences during tests.
        let defaults = UserDefaults(suiteName: "local.airanki.tests.\(UUID().uuidString)")!
        defaults.setVolatileDomain(["mapping.single": "undo", "mapping.double": "none", "mapping.triple": "invalid"], forName: UserDefaults.argumentDomain)
        let mapping = Mapping(defaults: defaults)
        XCTAssertEqual(mapping.single, .undo)
        XCTAssertEqual(mapping.double, .none)
        XCTAssertEqual(mapping.triple, .undo)
        XCTAssertEqual(Mapping.validatedEase(0), 4)
        XCTAssertEqual(Mapping.validatedEase(3), 3)
    }

    func testLabCSVColumnsMarkersAndEscaping() {
        XCTAssertEqual(LabCSV.header.trimmingCharacters(in: .newlines).split(separator: ",").count, 21)
        let row = LabCSV.row(monotonic: 3.5, wallISO: "date", event: "marker", marker: 3)
        let fields = row.trimmingCharacters(in: .newlines).components(separatedBy: ",")
        XCTAssertEqual(fields.count, 21)
        XCTAssertEqual(fields[2], "marker")
        XCTAssertEqual(fields[19], "3")
        let escaped = LabCSV.row(monotonic: 0, wallISO: "date", event: "motion_error", detail: "one, \"two\"")
        XCTAssertTrue(escaped.contains("\"one, \"\"two\"\"\""))
        let motion = LabCSV.row(monotonic: 0, wallISO: "date", event: "motion", values: Array(repeating: 1, count: 14))
        XCTAssertEqual(motion.components(separatedBy: ",")[17], "1.00000000")
    }
}
