import Foundation
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

@MainActor
private final class ScriptedTransport: AnkiTransport {
    var port = 8765
    typealias Reply = ([String: Any]) throws -> [String: Any]
    var steps: [(String, String, Reply)] = []
    var requests: [[String: Any]] = []

    func legacy(_ name: String, result: Any = NSNull(), error: String? = nil, params: [String: Any] = [:]) {
        steps.append(("/", name, { request in
            XCTAssertEqual(request["params"] as? NSDictionary, params as NSDictionary)
            return ["result": result, "error": error as Any? ?? NSNull()]
        }))
    }

    func rpc(_ name: String, result: Any = NSNull(), error: [String: Any]? = nil,
             params: [String: Any]? = nil) {
        steps.append(("/api/v1", name, { request in
            if let params { XCTAssertEqual(request["params"] as? NSDictionary, params as NSDictionary) }
            var response: [String: Any] = ["jsonrpc": "2.0", "id": request["id"]!]
            if let error { response["error"] = error } else { response["result"] = result }
            return response
        }))
    }

    func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        requests.append(body)
        guard !steps.isEmpty else { XCTFail("Unexpected request: \(body)"); throw AnkiError.invalidResponse }
        let step = steps.removeFirst()
        XCTAssertEqual(path, step.0)
        XCTAssertEqual(body["action"] as? String ?? body["method"] as? String, step.1)
        if path == "/" { XCTAssertEqual(body["version"] as? Int, 6) }
        return try step.2(body)
    }
}

private func reviewer(_ side: String, id: String = "123", token: String = "token", ratings: [String] = ["again", "hard", "good", "easy"]) -> [String: Any] {
    ["active": side != "none", "side": side, "card": ["id": id], "stateToken": token,
     "answers": ratings.map { ["rating": $0] }]
}

private func legacyCard(_ id: Int = 123) -> [String: Any] {
    // Both HTML fields are present on either side in the official legacy API.
    ["cardId": id, "question": "q", "answer": "a", "buttons": [1, 2, 3, 4]]
}

private let v1Description: [String: Any] = ["apiMajor": 1, "ankiVersion": "26.9.3", "methods": [["name": "reviewer.get"]]]

final class AnkiClientTests: XCTestCase {
    @MainActor func testRevealFallbackPrefersV1SideCheckWhenLegacyAlsoExists() async throws {
        let transport = ScriptedTransport()
        transport.legacy("version", result: 6)
        transport.rpc("api.describe", result: v1Description)
        transport.rpc("reviewer.get", result: reviewer("answer"))
        transport.rpc("reviewer.get", result: reviewer("answer"))
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        let controller = ReviewController(client: client)
        let result = await controller.handleFlick(.init(t: 1, event: .ambiguous))
        XCTAssertEqual(result, .completed(.unclear)); XCTAssertTrue(transport.steps.isEmpty)
        XCTAssertEqual(transport.requests.count, 4)
    }

    @MainActor func testAmbiguousV1AnswerSendsNoWriteAndLegacyNeverGrades() async throws {
        let transport = ScriptedTransport()
        transport.rpc("reviewer.get", result: reviewer("answer"))
        transport.rpc("reviewer.get", result: reviewer("answer"))
        let controller = ReviewController(client: V1AnkiClient(transport: transport))
        let result = await controller.handleFlick(.init(t: 1, event: .ambiguous))
        XCTAssertEqual(result, .completed(.unclear)); XCTAssertTrue(transport.steps.isEmpty)
        XCTAssertEqual(transport.requests.count, 2)
        for accepted in [true,false] {
            let legacy = ScriptedTransport()
            legacy.legacy("guiShowAnswer", result: accepted)
            if !accepted { legacy.legacy("guiCurrentCard", result: legacyCard()) }
            let (feedback, _) = try await LegacyAnkiClient(transport: legacy).performFast(.reveal, ease: 4)
            XCTAssertEqual(feedback, accepted ? .showedAnswer : .unclear)
            XCTAssertTrue(legacy.steps.isEmpty)
            XCTAssertFalse(legacy.requests.contains { $0["action"] as? String == "guiAnswerCard" })
        }
    }

    @MainActor func testMotionShowOrGradeV1QuestionAndAnswer() async {
        for ease in [1, 3, 4] {
            for side in ["question", "answer"] {
                let transport = ScriptedTransport()
                transport.rpc("reviewer.get", result: reviewer(side, token: "initial"))
                if side == "question" {
                    transport.rpc("reviewer.showAnswer", result: ["changed": true], params: ["stateToken": "initial"])
                    transport.rpc("reviewer.get", result: reviewer("answer", token: "shown"))
                    transport.rpc("reviewer.get", result: reviewer("answer", token: "shown"))
                } else {
                    let rating = [1: "again", 3: "good", 4: "easy"][ease]!
                    transport.rpc("reviewer.answer", result: ["operationId": "grade"],
                                  params: ["stateToken": "initial", "rating": rating])
                    transport.rpc("operations.get", result: ["state": "succeeded"], params: ["operationId": "grade"])
                    transport.rpc("reviewer.get", result: reviewer("question", id: "456"))
                }
                let controller = ReviewController(client: V1AnkiClient(transport: transport))
                let outcome = await controller.handleAction(.showOrGrade(ease: ease), at: 0)
                XCTAssertEqual(outcome, .completed(side == "question" ? .showedAnswer : .graded(ease)))
                XCTAssertTrue(transport.steps.isEmpty)
                XCTAssertEqual(transport.requests.count, 4)
                XCTAssertEqual(transport.requests.filter { $0["method"] as? String == "reviewer.answer" }.count,
                               side == "question" ? 0 : 1)
            }
        }
    }

    @MainActor func testMotionShowOrGradeLegacyQuestionAndAnswer() async {
        for ease in [1, 3, 4] {
            for answerVisible in [false, true] {
                let transport = ScriptedTransport()
                transport.legacy("guiCurrentCard", result: legacyCard())
                transport.legacy("guiAnswerCard", result: answerVisible, params: ["ease": ease])
                if !answerVisible { transport.legacy("guiShowAnswer", result: true) }
                transport.legacy("guiCurrentCard", result: legacyCard(answerVisible ? 456 : 123))
                let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
                let outcome = await controller.handleAction(.showOrGrade(ease: ease), at: 0)
                XCTAssertEqual(outcome, .completed(answerVisible ? .graded(ease) : .showedAnswer))
                XCTAssertTrue(transport.steps.isEmpty)
                XCTAssertEqual(transport.requests.count, answerVisible ? 3 : 4)
                XCTAssertEqual(transport.requests.filter { $0["action"] as? String == "guiAnswerCard" }.count, 1)
            }
        }
    }

    @MainActor func testMotionUndoThroughControllerOnBothAPIs() async {
        for side in ["question", "answer"] {
            let v1 = ScriptedTransport()
            v1.rpc("reviewer.get", result: reviewer(side))
            v1.rpc("collection.undo", result: ["operationId": "undo"], params: [:])
            v1.rpc("operations.get", result: ["state": "succeeded"], params: ["operationId": "undo"])
            v1.rpc("reviewer.get", result: reviewer("answer"))
            let controller = ReviewController(client: V1AnkiClient(transport: v1))
            let outcome = await controller.handleAction(.undo, at: 0)
            XCTAssertEqual(outcome, .completed(.undone))
            XCTAssertTrue(v1.steps.isEmpty)
        }
        let legacy = ScriptedTransport()
        legacy.legacy("guiCurrentCard", result: legacyCard())
        legacy.legacy("guiUndo", result: true)
        legacy.legacy("guiCurrentCard", result: legacyCard())
        let controller = ReviewController(client: LegacyAnkiClient(transport: legacy))
        let outcome = await controller.handleAction(.undo, at: 0)
        XCTAssertEqual(outcome, .completed(.undone))
        XCTAssertTrue(legacy.steps.isEmpty)
    }

    @MainActor func testMotionUnofferedV1GradeAndLegacyTimeoutNeverWriteAgain() async {
        let v1 = ScriptedTransport()
        v1.rpc("reviewer.get", result: reviewer("answer", ratings: ["again", "good"]))
        v1.rpc("reviewer.get", result: reviewer("answer", ratings: ["again", "good"]))
        let controller = ReviewController(client: V1AnkiClient(transport: v1))
        let outcome = await controller.handleAction(.showOrGrade(ease: 4), at: 0)
        XCTAssertTrue(outcome.title.contains("not available"))
        XCTAssertTrue(v1.steps.isEmpty)
        XCTAssertTrue(v1.requests.allSatisfy { $0["method"] as? String == "reviewer.get" })
        let legacy = ScriptedTransport()
        legacy.legacy("guiCurrentCard", result: legacyCard())
        legacy.steps.append(("/", "guiAnswerCard", { _ in throw URLError(.timedOut) }))
        legacy.legacy("guiCurrentCard", result: legacyCard())
        let legacyController = ReviewController(client: LegacyAnkiClient(transport: legacy))
        let failed = await legacyController.handleAction(.showOrGrade(ease: 1), at: 0)
        if case .failed = failed { } else { XCTFail("Expected failed grade") }
        XCTAssertTrue(legacy.steps.isEmpty)
        XCTAssertEqual(legacy.requests.compactMap { $0["action"] as? String },
                       ["guiCurrentCard", "guiAnswerCard", "guiCurrentCard"])
    }

    @MainActor func testFastFallbackUsesLegacyEvenWhenV1Exists() async throws {
        for answerVisible in [true, false] {
            let transport = ScriptedTransport()
            transport.legacy("version", result: 6)
            transport.rpc("api.describe", result: v1Description)
            transport.rpc("reviewer.get", result: reviewer("answer"))
            transport.legacy("guiAnswerCard", result: answerVisible, params: ["ease": 4])
            if !answerVisible { transport.legacy("guiShowAnswer", result: true) }
            let client = AutoDetectAnkiClient(transport: transport)
            let controller = ReviewController(client: client)
            await controller.refresh()
            let outcome = await controller.handleAction(.showOrGrade(ease: 4), at: 0)
            XCTAssertEqual(outcome, .completed(answerVisible ? .graded(4) : .showedAnswer))
            XCTAssertTrue(transport.steps.isEmpty)
            XCTAssertEqual(transport.requests.count, answerVisible ? 4 : 5)
            XCTAssertEqual(controller.link, .ankiConnect)
        }
    }

    @MainActor func testFastFallbackTimeoutNeverRevealsOrRetries() async throws {
        let transport = ScriptedTransport()
        transport.legacy("version", result: 6)
        transport.rpc("api.describe", result: v1Description)
        transport.steps.append(("/", "guiAnswerCard", { _ in throw URLError(.timedOut) }))
        transport.rpc("reviewer.get", result: reviewer("answer")) // read-only reconciliation
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        let controller = ReviewController(client: client)
        let outcome = await controller.handleAction(.showOrGrade(ease: 4), at: 0)
        if case .failed = outcome { } else { XCTFail("expected timeout") }
        XCTAssertTrue(transport.steps.isEmpty)
        XCTAssertEqual(transport.requests.filter { $0["action"] as? String == "guiAnswerCard" }.count, 1)
    }

    @MainActor func testAutoDetectsV1AfterLegacyVersionPing() async throws {
        let transport = ScriptedTransport()
        transport.legacy("version", result: 6)
        transport.rpc("api.describe", result: v1Description)
        transport.rpc("reviewer.get", result: reviewer("answer"))
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        let state = try await client.reviewerState()
        XCTAssertEqual(state, .answer)
        XCTAssertTrue(client.apiDescription.contains("V1"))
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testLegacyDetectionSupportsReviewWithoutCardSide() async throws {
        let transport = ScriptedTransport()
        transport.legacy("version", result: 6)
        transport.steps.append(("/api/v1", "api.describe", { _ in ["result": NSNull(), "error": "unsupported action"] }))
        transport.legacy("guiAnswerCard", result: true, params: ["ease": 4])
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        let controller = ReviewController(client: client)
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.single, at: 0)
        XCTAssertEqual(controller.status, .ready(.reviewing))
        XCTAssertEqual(controller.status.title, "Anki: reviewing")
        XCTAssertEqual(feedback, .graded(4))
        XCTAssertEqual(client.apiDescription, "AnkiConnect Legacy v6")
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testNonAnkiListenerIsDetectedOnBothAPIs() async {
        let transport = ScriptedTransport()
        transport.port = 9876
        transport.steps.append(("/", "version", { _ in ["error": "Invalid request"] }))
        transport.steps.append(("/api/v1", "api.describe", { _ in ["error": "Invalid request"] }))
        let client = AutoDetectAnkiClient(transport: transport)
        do { try await client.ping(); XCTFail("Expected port clash") }
        catch {
            XCTAssertEqual(error.localizedDescription, "Something else is answering on port 9876 — not AnkiConnect")
        }
        XCTAssertNil(client.apiName)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testV1DetectionSucceedsWhenLegacyProbeFails() async throws {
        let transport = ScriptedTransport()
        transport.steps.append(("/", "version", { _ in ["unexpected": true] }))
        transport.rpc("api.describe", result: v1Description)
        transport.rpc("reviewer.get", result: reviewer("none"))
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        let state = try await client.reviewerState()
        XCTAssertEqual(state, .notReviewing)
        XCTAssertEqual(client.apiName, "V1")
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testMalformedV1DiscoveryFallsBackToVerifiedLegacy() async throws {
        let transport = ScriptedTransport()
        transport.legacy("version", result: 6)
        transport.rpc("api.describe", result: ["wrong": "shape"])
        transport.legacy("guiCurrentCard", result: legacyCard())
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        let state = try await client.reviewerState()
        XCTAssertEqual(state, .reviewing)
        XCTAssertEqual(client.apiName, "legacy")
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testRedetectionClearsStaleAPIAfterPortClash() async throws {
        let transport = ScriptedTransport()
        transport.legacy("version", result: 6)
        transport.rpc("api.describe", result: v1Description)
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        transport.legacy("version", result: ["unrelated": true])
        transport.rpc("api.describe", error: ["code": -32601, "message": "Unknown method"])
        do { try await client.ping(); XCTFail("Expected failed redetection") }
        catch AnkiError.notAnkiConnect(8765) { } catch { XCTFail("\(error)") }
        XCTAssertNil(client.apiName)
        XCTAssertEqual(client.apiDescription, "AnkiConnect not connected")
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testPortClashNeverAllowsGestureMutations() async {
        let transport = ScriptedTransport()
        for _ in 0..<2 { // Initial read and read-only reconciliation.
            transport.steps.append(("/", "version", { _ in ["error": "Invalid request"] }))
            transport.steps.append(("/api/v1", "api.describe", { _ in [:] }))
        }
        let controller = ReviewController(client: AutoDetectAnkiClient(transport: transport))
        let outcome = await controller.handleWithOutcome(.single, at: 0)
        XCTAssertTrue(outcome.title.contains("not AnkiConnect"))
        XCTAssertEqual(transport.requests.compactMap { $0["action"] as? String ?? $0["method"] as? String },
                       ["version", "api.describe", "version", "api.describe"])
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testAuthenticationAndOldVersionAreNotMisreportedAsPortClashes() async {
        for failure in [AnkiError.http(401), .http(403), .legacy("valid api key must be provided"), .unsupportedVersion(5)] {
            let transport = ScriptedTransport()
            transport.steps.append(("/", "version", { _ in throw failure }))
            transport.steps.append(("/api/v1", "api.describe", { _ in throw AnkiError.invalidResponse }))
            do { try await AutoDetectAnkiClient(transport: transport).ping(); XCTFail("Expected error") }
            catch { XCTAssertEqual(error.localizedDescription, failure.localizedDescription) }
            XCTAssertTrue(transport.steps.isEmpty)
        }
    }

    @MainActor func testMissingReplyDoesNotClaimAnotherProgramIsListening() async {
        for failingPath in ["/", "/api/v1"] {
            let transport = ScriptedTransport()
            transport.port = 9876
            for (path, method) in [("/", "version"), ("/api/v1", "api.describe")] {
                transport.steps.append((path, method, { _ in
                    if path == failingPath { throw URLError(.cannotConnectToHost) }
                    return ["error": "Invalid request"]
                }))
            }
            do { try await AutoDetectAnkiClient(transport: transport).ping(); XCTFail("Expected unreachable") }
            catch {
                XCTAssertTrue(error.localizedDescription.contains("Not reachable"))
                XCTAssertTrue(error.localizedDescription.contains("9876"))
                XCTAssertFalse(error.localizedDescription.contains("not AnkiConnect"))
            }
            XCTAssertTrue(transport.steps.isEmpty)
        }
    }

    @MainActor func testRedetectionCannotBypassPendingV1Operation() async throws {
        let transport = ScriptedTransport()
        transport.legacy("version", result: 6)
        transport.rpc("api.describe", result: v1Description)
        transport.rpc("reviewer.get", result: reviewer("answer"))
        transport.rpc("reviewer.answer", result: ["operationId": "pending"])
        transport.steps.append(("/api/v1", "operations.get", { _ in throw URLError(.timedOut) }))
        transport.steps.append(("/api/v1", "operations.get", { _ in throw URLError(.timedOut) }))
        transport.rpc("operations.get", result: ["state": "succeeded"])
        transport.rpc("reviewer.get", result: reviewer("question"))
        let client = AutoDetectAnkiClient(transport: transport)
        try await client.ping()
        _ = try await client.reviewerState()
        do { try await client.answer(ease: 4); XCTFail("Expected timeout") } catch { }
        do { try await client.ping(); XCTFail("Pending operation must block redetection") } catch { }
        XCTAssertEqual(client.apiName, "V1")
        let state = try await client.reviewerState()
        XCTAssertEqual(state, .question)
        XCTAssertEqual(transport.requests.filter { $0["action"] as? String == "version" }.count, 1)
        XCTAssertEqual(transport.requests.filter { $0["method"] as? String == "reviewer.answer" }.count, 1)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testLegacyNotReviewingAndExactMutationNames() async throws {
        let transport = ScriptedTransport()
        transport.legacy("guiCurrentCard", error: "Gui review is not currently active.")
        transport.legacy("guiShowAnswer", result: true)
        transport.legacy("guiAnswerCard", result: true, params: ["ease": 4])
        transport.legacy("guiUndo", result: true)
        let client = LegacyAnkiClient(transport: transport)
        let state = try await client.reviewerState()
        XCTAssertEqual(state, .notReviewing)
        try await client.showAnswer()
        try await client.answer(ease: 4)
        try await client.undo()
        XCTAssertEqual((transport.requests[2]["params"] as? [String: Int])?["ease"], 4)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testLegacyFalseResultIsFailure() async {
        let transport = ScriptedTransport(); transport.legacy("guiAnswerCard", result: false, params: ["ease": 4])
        do {
            try await LegacyAnkiClient(transport: transport).answer(ease: 4)
            XCTFail("False must not appear as successful feedback")
        } catch { XCTAssertTrue(error.localizedDescription.contains("declined")) }
    }

    @MainActor func testLegacySingleQuestionAttemptsGradeThenShowsAnswer() async {
        for ease in [3, 4] {
            let transport = ScriptedTransport()
            transport.legacy("guiCurrentCard", result: legacyCard())
            transport.legacy("guiAnswerCard", result: false, params: ["ease": ease])
            transport.legacy("guiShowAnswer", result: true)
            transport.legacy("guiCurrentCard", result: legacyCard())
            let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
            controller.easeForSingle = ease
            var feedback: ActionFeedback?
            controller.onFeedback = { feedback = $0 }
            await controller.handle(.single, at: 0)
            XCTAssertEqual(feedback, .showedAnswer)
            XCTAssertEqual(controller.status, .ready(.reviewing))
            XCTAssertEqual(transport.requests.count, 4)
            XCTAssertTrue(transport.steps.isEmpty)
        }
    }

    @MainActor func testLegacySingleAnswerGradesEasyOrGood() async {
        for ease in [3, 4] {
            let transport = ScriptedTransport()
            transport.legacy("guiCurrentCard", result: legacyCard())
            transport.legacy("guiAnswerCard", result: true, params: ["ease": ease])
            transport.legacy("guiCurrentCard", result: legacyCard(456))
            let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
            controller.easeForSingle = ease
            var feedback: ActionFeedback?
            controller.onFeedback = { feedback = $0 }
            await controller.handle(.single, at: 0)
            XCTAssertEqual(feedback, .graded(ease))
            XCTAssertEqual(controller.status, .ready(.reviewing))
            XCTAssertEqual(transport.requests.count, 3)
            XCTAssertTrue(transport.steps.isEmpty)
        }
    }

    @MainActor func testLegacyDoubleQuestionShowsChecksCardThenGradesAgain() async {
        let transport = ScriptedTransport()
        transport.legacy("guiCurrentCard", result: legacyCard())
        transport.legacy("guiAnswerCard", result: false, params: ["ease": 1])
        transport.legacy("guiShowAnswer", result: true)
        transport.legacy("guiCurrentCard", result: legacyCard())
        transport.legacy("guiAnswerCard", result: true, params: ["ease": 1])
        transport.legacy("guiCurrentCard", result: legacyCard(456))
        let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.double, at: 0)
        XCTAssertEqual(feedback, .graded(1))
        XCTAssertEqual(controller.status, .ready(.reviewing))
        XCTAssertEqual(transport.requests.count, 6)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testLegacyDoubleAnswerGradesAgainWithoutShowing() async {
        let transport = ScriptedTransport()
        transport.legacy("guiCurrentCard", result: legacyCard())
        transport.legacy("guiAnswerCard", result: true, params: ["ease": 1])
        transport.legacy("guiCurrentCard", result: NSNull())
        let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.double, at: 0)
        XCTAssertEqual(feedback, .graded(1))
        XCTAssertEqual(controller.status, .ready(.notReviewing))
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testLegacyChangedOrMissingCardAfterShowSendsNoGrade() async {
        for outcome in ["changed", "null", "inactive"] {
            let transport = ScriptedTransport()
            transport.legacy("guiCurrentCard", result: legacyCard())
            transport.legacy("guiAnswerCard", result: false, params: ["ease": 1])
            transport.legacy("guiShowAnswer", result: true)
            transport.legacy("guiCurrentCard", result: outcome == "changed" ? legacyCard(456) : NSNull(),
                             error: outcome == "inactive" ? "Gui review is not currently active." : nil)
            transport.legacy("guiCurrentCard", result: legacyCard(456)) // Read-only error reconciliation.
            let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
            var feedback: ActionFeedback?
            controller.onFeedback = { feedback = $0 }
            await controller.handle(.double, at: 0)
            XCTAssertEqual(feedback, .error)
            XCTAssertTrue(controller.status.title.contains("card changed"))
            XCTAssertEqual(transport.requests.filter { $0["action"] as? String == "guiAnswerCard" }.count, 1)
            XCTAssertTrue(transport.steps.isEmpty)
        }
    }

    @MainActor func testLegacyUndoDuringReview() async {
        let transport = ScriptedTransport()
        transport.legacy("guiCurrentCard", result: legacyCard())
        transport.legacy("guiUndo", result: true)
        transport.legacy("guiCurrentCard", result: legacyCard(456))
        let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.triple, at: 0)
        XCTAssertEqual(feedback, .undone)
        XCTAssertEqual(controller.status, .ready(.reviewing))
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testLegacyNotReviewingSendsNoMutationsForAnyGesture() async {
        for error: String? in [nil, "Gui review is not currently active.", "reviewer is not available"] {
            for gesture in Gesture.allCases {
                let transport = ScriptedTransport()
                transport.legacy("guiCurrentCard", error: error)
                let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
                var feedback: ActionFeedback?
                controller.onFeedback = { feedback = $0 }
                await controller.handle(gesture, at: 0)
                XCTAssertEqual(controller.status, .ready(.notReviewing))
                XCTAssertNil(feedback)
                XCTAssertEqual(transport.requests.count, 1)
                XCTAssertTrue(transport.steps.isEmpty)
            }
        }
    }

    @MainActor func testLegacyDeclinedFinalGradeIsNotRetried() async {
        let transport = ScriptedTransport()
        transport.legacy("guiCurrentCard", result: legacyCard())
        transport.legacy("guiAnswerCard", result: false, params: ["ease": 1])
        transport.legacy("guiShowAnswer", result: true)
        transport.legacy("guiCurrentCard", result: legacyCard())
        transport.legacy("guiAnswerCard", result: false, params: ["ease": 1])
        transport.legacy("guiCurrentCard", result: legacyCard())
        let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.double, at: 0)
        XCTAssertEqual(feedback, .error)
        XCTAssertTrue(controller.status.title.contains("declined guiAnswerCard"))
        XCTAssertEqual(transport.requests.count, 6)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testLegacyDeclinedShowDoesNotGradeOrRetry() async {
        for gesture in [Gesture.single, .double] {
            let transport = ScriptedTransport()
            transport.legacy("guiCurrentCard", result: legacyCard())
            transport.legacy("guiAnswerCard", result: false, params: ["ease": gesture == .single ? 4 : 1])
            transport.legacy("guiShowAnswer", result: false)
            transport.legacy("guiCurrentCard", result: legacyCard())
            let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
            var feedback: ActionFeedback?
            controller.onFeedback = { feedback = $0 }
            await controller.handle(gesture, at: 0)
            XCTAssertEqual(feedback, .error)
            XCTAssertTrue(controller.status.title.contains("declined guiShowAnswer"))
            XCTAssertEqual(transport.requests.count, 4)
            XCTAssertTrue(transport.steps.isEmpty)
        }
    }

    @MainActor func testLegacyMutationTimeoutNeverRetriesOrContinues() async {
        for stage in ["singleGrade", "singleShow", "doubleGrade", "doubleShow", "doubleFinalGrade", "undo"] {
            let transport = ScriptedTransport()
            transport.legacy("guiCurrentCard", result: legacyCard())
            let gesture: Gesture = stage.hasPrefix("single") ? .single : stage == "undo" ? .triple : .double
            if stage.hasSuffix("Show") || stage == "doubleFinalGrade" {
                transport.legacy("guiAnswerCard", result: false, params: ["ease": gesture == .single ? 4 : 1])
            }
            if stage == "doubleFinalGrade" {
                transport.legacy("guiShowAnswer", result: true)
                transport.legacy("guiCurrentCard", result: legacyCard())
            }
            let failingAction = stage.hasSuffix("Show") ? "guiShowAnswer" : stage == "undo" ? "guiUndo" : "guiAnswerCard"
            transport.steps.append(("/", failingAction, { _ in throw URLError(.timedOut) }))
            transport.legacy("guiCurrentCard", result: legacyCard())
            let expectedRequests = transport.steps.map { $0.1 }
            let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
            var feedback: ActionFeedback?
            controller.onFeedback = { feedback = $0 }
            await controller.handle(gesture, at: 0)
            XCTAssertEqual(feedback, .error)
            XCTAssertEqual(controller.status, .error(URLError(.timedOut).localizedDescription))
            XCTAssertEqual(transport.requests.compactMap { $0["action"] as? String }, expectedRequests)
            XCTAssertFalse(controller.isBusy)
            XCTAssertTrue(transport.steps.isEmpty)
        }
    }

    @MainActor func testLegacyMalformedGradeResultDoesNotTriggerFallback() async {
        let transport = ScriptedTransport()
        transport.legacy("guiCurrentCard", result: legacyCard())
        transport.legacy("guiAnswerCard", result: NSNull(), params: ["ease": 4])
        transport.legacy("guiCurrentCard", result: legacyCard())
        let controller = ReviewController(client: LegacyAnkiClient(transport: transport))
        var feedback: ActionFeedback?
        controller.onFeedback = { feedback = $0 }
        await controller.handle(.single, at: 0)
        XCTAssertEqual(feedback, .error)
        XCTAssertEqual(controller.status, .error(AnkiError.invalidResponse.localizedDescription))
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testV1ShowThenAgainUsesFreshTokenAndWaitsForCompletion() async throws {
        let transport = ScriptedTransport()
        transport.rpc("reviewer.get", result: reviewer("question", token: "question-token"))
        transport.rpc("reviewer.showAnswer", result: ["changed": true], params: ["stateToken": "question-token"])
        transport.rpc("reviewer.get", result: reviewer("answer", token: "answer-token"))
        transport.rpc("reviewer.answer", result: ["operationId": "op1"], params: ["stateToken": "answer-token", "rating": "again"])
        transport.rpc("operations.get", result: ["state": "running"], params: ["operationId": "op1"])
        transport.rpc("operations.get", result: ["state": "succeeded", "result": ["cardId": "123"]])
        let client = V1AnkiClient(transport: transport)
        _ = try await client.reviewerState()
        try await client.showAnswer()
        try await client.answer(ease: 1)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testChangedCardDuringShowCannotBeGraded() async throws {
        let transport = ScriptedTransport()
        transport.rpc("reviewer.get", result: reviewer("question"))
        transport.rpc("reviewer.showAnswer", result: ["changed": true])
        transport.rpc("reviewer.get", result: reviewer("answer", id: "different"))
        let client = V1AnkiClient(transport: transport)
        _ = try await client.reviewerState()
        do { try await client.showAnswer(); XCTFail("Must reject changed card") }
        catch { XCTAssertTrue(error.localizedDescription.contains("card changed")) }
        do { try await client.answer(ease: 1); XCTFail("Snapshot must be invalidated") }
        catch { }
        XCTAssertEqual(transport.requests.count, 3)
    }

    @MainActor func testUnofferedGradeSendsNoWrite() async throws {
        let transport = ScriptedTransport()
        transport.rpc("reviewer.get", result: reviewer("answer", ratings: ["again", "good"]))
        let client = V1AnkiClient(transport: transport)
        _ = try await client.reviewerState()
        do { try await client.answer(ease: 4); XCTFail("Easy is unavailable") }
        catch { XCTAssertTrue(error.localizedDescription.contains("not available")) }
        XCTAssertEqual(transport.requests.count, 1)
    }

    @MainActor func testUndoUsesCollectionAPIAndPolls() async throws {
        let transport = ScriptedTransport()
        transport.rpc("collection.undo", result: ["operationId": "undo1"], params: [:])
        transport.rpc("operations.get", result: ["state": "succeeded", "result": ["changed": true]], params: ["operationId": "undo1"])
        try await V1AnkiClient(transport: transport).undo()
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testV1OperationFailureSurfacesWithoutRetry() async throws {
        let transport = ScriptedTransport()
        transport.rpc("collection.undo", result: ["operationId": "undo1"])
        transport.rpc("operations.get", result: ["state": "failed", "error": ["code": 1009, "message": "Nothing to undo", "data": ["type": "invalidState"]]])
        do { try await V1AnkiClient(transport: transport).undo(); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Nothing to undo")) }
        XCTAssertEqual(transport.requests.count, 2)
    }

    @MainActor func testPendingOperationSurvivesTransportFailure() async throws {
        let transport = ScriptedTransport()
        transport.rpc("collection.undo", result: ["operationId": "pending"])
        transport.steps.append(("/api/v1", "operations.get", { _ in throw URLError(.timedOut) }))
        transport.rpc("operations.get", result: ["state": "succeeded", "result": ["changed": true]], params: ["operationId": "pending"])
        transport.rpc("reviewer.get", result: reviewer("answer"))
        let client = V1AnkiClient(transport: transport)
        do { try await client.undo(); XCTFail("Expected timeout") } catch { }
        let state = try await client.reviewerState()
        XCTAssertEqual(state, .answer)
        XCTAssertEqual(transport.requests.filter { $0["method"] as? String == "collection.undo" }.count, 1)
        XCTAssertTrue(transport.steps.isEmpty)
    }

    @MainActor func testStaleTokenErrorIsNotRetried() async throws {
        let transport = ScriptedTransport()
        transport.rpc("reviewer.get", result: reviewer("answer"))
        transport.rpc("reviewer.answer", error: ["code": 1008, "message": "Stale token", "data": ["type": "conflict"]])
        let client = V1AnkiClient(transport: transport)
        _ = try await client.reviewerState()
        do { try await client.answer(ease: 4); XCTFail("Expected conflict") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Stale token")) }
        XCTAssertEqual(transport.requests.count, 2)
    }

    @MainActor func testCollectionUnavailableIsNotReviewing() async throws {
        let transport = ScriptedTransport()
        transport.rpc("reviewer.get", error: ["code": 1004, "message": "No collection", "data": ["type": "collectionUnavailable"]])
        let state = try await V1AnkiClient(transport: transport).reviewerState()
        XCTAssertEqual(state, .notReviewing)
    }

    @MainActor func testMalformedResponseAndWrongRequestIDAreRejected() async {
        for reply: [String: Any] in [["jsonrpc": "2.0", "id": 999, "result": reviewer("answer")],
                                    ["jsonrpc": "2.0", "id": 1, "result": ["active": true, "side": "answer"]]] {
            let transport = ScriptedTransport()
            transport.steps.append(("/api/v1", "reviewer.get", { _ in reply }))
            do { _ = try await V1AnkiClient(transport: transport).reviewerState(); XCTFail("Malformed response") }
            catch AnkiError.invalidResponse { } catch { XCTFail("\(error)") }
        }
    }
}

/// URLProtocol intercepts requests before any socket is opened.
private final class StubURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    static func bodyData(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        // URLSession can convert the body to a stream before URLProtocol sees it.
        guard let stream = request.httpBodyStream else { throw AnkiError.message("Missing request body") }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count == 0 { return result }
            if count < 0 { throw stream.streamError ?? AnkiError.invalidResponse }
            result.append(contentsOf: bytes.prefix(count))
        }
    }
}

final class HTTPTransportTests: XCTestCase {
    @MainActor func testCustomPortIsUsedForBothAPIs() async throws {
        for port in [1, 9876, 65535] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            let transport = URLSessionAnkiTransport(port: port, configuration: configuration)
            var paths: [String] = []
            StubURLProtocol.respond = { request in
                XCTAssertEqual(request.url?.host, "127.0.0.1")
                XCTAssertEqual(request.url?.port, port)
                XCTAssertEqual(request.url?.scheme, "http")
                paths.append(request.url!.path)
                let body = try JSONSerialization.jsonObject(with: StubURLProtocol.bodyData(request)) as! [String: Any]
                if request.url?.path == "/" { return (200, Data("{\"result\":6,\"error\":null}".utf8)) }
                XCTAssertEqual(body["method"] as? String, "api.describe")
                return (200, try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": body["id"]!, "result": v1Description]))
            }
            defer { StubURLProtocol.respond = nil }
            let client = AutoDetectAnkiClient(transport: transport)
            try await client.ping()
            XCTAssertEqual(paths, ["/", "/api/v1"])
            XCTAssertEqual(client.apiName, "V1")
        }
    }

    @MainActor func testInvalidPortsNeverSendRequests() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.respond = { _ in XCTFail("Invalid port must not send HTTP"); return (200, Data()) }
        defer { StubURLProtocol.respond = nil }
        for port in [0, -1, 65536, Int.max] {
            let transport = URLSessionAnkiTransport(port: port, configuration: configuration)
            do { _ = try await transport.post(path: "/", body: [:]); XCTFail("Expected invalid port") }
            catch { XCTAssertTrue(error.localizedDescription.contains("1 to 65535")) }
        }
    }

    @MainActor func testMalformedHTTPListenersReportConfiguredPort() async {
        for (status, body) in [(200, "{\"error\":\"Invalid request\"}"), (200, "<html>Not Anki</html>"),
                               (200, "[]"), (200, "{}"), (404, ""), (500, "")] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            let transport = URLSessionAnkiTransport(port: 9876, configuration: configuration)
            var count = 0
            StubURLProtocol.respond = { _ in count += 1; return (status, Data(body.utf8)) }
            defer { StubURLProtocol.respond = nil }
            do { try await AutoDetectAnkiClient(transport: transport).ping(); XCTFail("Expected port clash") }
            catch AnkiError.notAnkiConnect(9876) { } catch { XCTFail("\(error)") }
            XCTAssertEqual(count, 2)
        }
    }

    @MainActor func testUnreachableHTTPPortRetainsNetworkDiagnostic() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let transport = URLSessionAnkiTransport(port: 9876, configuration: configuration)
        StubURLProtocol.respond = { _ in throw URLError(.cannotConnectToHost) }
        defer { StubURLProtocol.respond = nil }
        do { try await AutoDetectAnkiClient(transport: transport).ping(); XCTFail("Expected unreachable") }
        catch AnkiError.unreachable(let port, _) { XCTAssertEqual(port, 9876) }
        catch { XCTFail("\(error)") }
    }

    @MainActor func testURLSessionLoopbackPostTimeoutAndAPIKey() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let transport = URLSessionAnkiTransport(apiKey: "test-key", configuration: configuration)
        StubURLProtocol.respond = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8765/")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 2)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
            let body = try JSONSerialization.jsonObject(with: StubURLProtocol.bodyData(request)) as! [String: Any]
            XCTAssertEqual(body["action"] as? String, "version")
            XCTAssertEqual(body["version"] as? Int, 6)
            XCTAssertEqual(body["key"] as? String, "test-key")
            return (200, Data("{\"result\":6,\"error\":null}".utf8))
        }
        try await LegacyAnkiClient(transport: transport).ping()
        StubURLProtocol.respond = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8765/api/v1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            return (200, Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"active\":false}}".utf8))
        }
        let state = try await V1AnkiClient(transport: transport).reviewerState()
        XCTAssertEqual(state, .notReviewing)
    }

    @MainActor func testHTTPFailureAndInvalidPathCannotMutate() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let transport = URLSessionAnkiTransport(configuration: configuration)
        StubURLProtocol.respond = { _ in (403, Data()) }
        do { try await LegacyAnkiClient(transport: transport).ping(); XCTFail("Expected HTTP failure") }
        catch AnkiError.http(403) { } catch { XCTFail("\(error)") }
        do { _ = try await transport.post(path: "https://example.com", body: [:]); XCTFail("Invalid path") }
        catch AnkiError.invalidResponse { } catch { XCTFail("\(error)") }
    }
}
