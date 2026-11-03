import Foundation

public enum ReviewerState: String, Equatable, Sendable {
    case question, answer, notReviewing
    /// Legacy confirms an active card, but does not report its visible side.
    case reviewing
}

@MainActor
public protocol AnkiClient: AnyObject {
    func reviewerState() async throws -> ReviewerState
    func showAnswer() async throws
    func answer(ease: Int) async throws
    func undo() async throws
    func ping() async throws
    func perform(_ action: RemoteAction, from state: ReviewerState, ease: Int) async throws -> ActionFeedback
}

public extension AnkiClient {
    /// Side-aware flow used by V1. Legacy overrides this with server-side checks.
    func perform(_ action: RemoteAction, from state: ReviewerState, ease: Int) async throws -> ActionFeedback {
        guard state == .question || state == .answer else { throw AnkiError.invalidResponse }
        switch action {
        case .reveal:
            guard state != .answer else { return .unclear }
            try await showAnswer()
            return .showedAnswer
        case .showOrEasy:
            return try await perform(.showOrGrade(ease: ease), from: state, ease: ease)
        case .showOrGrade(let ease):
            if state == .question {
                try await showAnswer()
                return .showedAnswer
            }
            try await answer(ease: ease)
            return .graded(ease)
        case .again:
            if state == .question { try await showAnswer() }
            try await answer(ease: 1)
            return .graded(1)
        case .undo:
            try await undo()
            return .undone
        case .none: throw AnkiError.invalidResponse
        }
    }
}

public enum AnkiError: LocalizedError {
    case message(String)
    case http(Int)
    case legacy(String)
    case rpc(code: Int, type: String, message: String)
    case invalidResponse
    case notAnkiConnect(port: Int)
    case unreachable(port: Int, reason: String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .message(let text), .legacy(let text): return text
        case .http(let status): return "AnkiConnect HTTP \(status). Check the add-on and API key."
        case .rpc(_, _, let message): return "Anki: \(message)"
        case .invalidResponse: return "Unexpected AnkiConnect response. Check the installed add-on."
        case .notAnkiConnect(let port): return "Something else is answering on port \(port) — not AnkiConnect"
        case .unreachable(let port, let reason): return "Not reachable — AnkiConnect on port \(port) (\(reason)). Open Anki and check the add-on."
        case .unsupportedVersion(let version): return "AnkiConnect API version 6 or later is required (found \(version))."
        }
    }

    var isAuthenticationFailure: Bool {
        switch self {
        case .http(401), .http(403): return true
        case .legacy(let text): return text.lowercased().contains("api key") || text.lowercased().contains("api access")
        default: return false
        }
    }

    var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }
}

/// Narrow injection point for tests. Production only permits the two loopback paths.
@MainActor
public protocol AnkiTransport {
    var port: Int { get }
    func post(path: String, body: [String: Any]) async throws -> [String: Any]
}

public extension AnkiTransport {
    var port: Int { AnkiConnectionSettings.defaultPort }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
public final class URLSessionAnkiTransport: AnkiTransport {
    public let port: Int
    private let session: URLSession
    private let apiKey: String?

    public init(port: Int = AnkiConnectionSettings.defaultPort, apiKey: String? = nil,
                configuration: URLSessionConfiguration = .ephemeral) {
        self.port = port
        self.apiKey = apiKey?.isEmpty == false ? apiKey : nil
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.connectionProxyDictionary = [:]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    public func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard path == "/" || path == "/api/v1" else { throw AnkiError.invalidResponse }
        guard AnkiConnectionSettings.isValidPort(port) else {
            throw AnkiError.message("Enter an AnkiConnect port from 1 to 65535.")
        }
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = body
        if let apiKey {
            if path == "/" { payload["key"] = apiKey }
            else { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw AnkiError.invalidResponse }
            guard response.statusCode == 200 else { throw AnkiError.http(response.statusCode) }
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw AnkiError.invalidResponse
            }
            return object
        } catch let error as URLError {
            throw AnkiError.unreachable(port: port, reason: error.localizedDescription)
        }
    }
}

@MainActor
public final class LegacyAnkiClient: AnkiClient {
    private let transport: AnkiTransport
    private var cardID: Int?
    public init(transport: AnkiTransport) { self.transport = transport }

    func call(_ action: String, params: [String: Any] = [:]) async throws -> Any {
        let reply = try await transport.post(path: "/", body: ["action": action, "version": 6, "params": params])
        if let error = reply["error"] as? String { throw AnkiError.legacy(error) }
        guard reply["error"] is NSNull, let result = reply["result"] else { throw AnkiError.invalidResponse }
        return result
    }

    public func ping() async throws {
        guard let version = try await call("version") as? Int else { throw AnkiError.invalidResponse }
        guard version >= 6 else { throw AnkiError.unsupportedVersion(version) }
    }

    public func reviewerState() async throws -> ReviewerState {
        cardID = nil
        do {
            let result = try await call("guiCurrentCard")
            if result is NSNull { return .notReviewing }
            guard let card = result as? [String: Any], let id = card["cardId"] as? Int else {
                throw AnkiError.invalidResponse
            }
            cardID = id
            return .reviewing
        } catch AnkiError.legacy(let message) where message == "Gui review is not currently active." || message == "reviewer is not available" {
            return .notReviewing
        }
    }

    public func perform(_ action: RemoteAction, from state: ReviewerState, ease: Int) async throws -> ActionFeedback {
        guard state == .reviewing, let originalCardID = cardID else { throw AnkiError.invalidResponse }
        switch action {
        case .reveal:
            try await showAnswer()
            return .showedAnswer
        case .showOrEasy:
            return try await perform(.showOrGrade(ease: ease), from: state, ease: ease)
        case .showOrGrade(let ease):
            // A definite false means no grade occurred. A thrown error (including
            // a timeout) exits immediately; it must never trigger another mutation.
            if try await accepted("guiAnswerCard", params: ["ease": ease]) { return .graded(ease) }
            try await showAnswer()
            return .showedAnswer
        case .again:
            if try await accepted("guiAnswerCard", params: ["ease": 1]) { return .graded(1) }
            try await showAnswer()
            let refreshed = try await reviewerState()
            guard refreshed == .reviewing, cardID == originalCardID else {
                throw AnkiError.message("The card changed while showing its answer; no grade was sent.")
            }
            // Only one attempt after showing the same card; false is now an error.
            try await answer(ease: 1)
            return .graded(1)
        case .undo:
            try await undo()
            return .undone
        case .none: throw AnkiError.invalidResponse
        }
    }

    /// Server-side side check: one grade call, or a definite false then one reveal.
    /// No stale local card-side snapshot and no read before/after the common flick path.
    public func performFast(_ action: RemoteAction, ease: Int) async throws -> (ActionFeedback?, ReviewerState) {
        switch action {
        case .reveal:
            if try await accepted("guiShowAnswer") { return (.showedAnswer, .answer) }
            let state = try await reviewerState()
            return (state == .notReviewing ? nil : .unclear, state)
        case .showOrEasy: return try await performFast(.showOrGrade(ease: ease), ease: ease)
        case .showOrGrade(let grade):
            if try await accepted("guiAnswerCard", params: ["ease": grade]) { return (.graded(grade), .reviewing) }
            if try await accepted("guiShowAnswer") { return (.showedAnswer, .answer) }
            return (nil, .notReviewing)
        default:
            let state = try await reviewerState()
            guard state != .notReviewing else { return (nil, state) }
            return (try await perform(action, from: state, ease: ease), .reviewing)
        }
    }

    private func accepted(_ name: String, params: [String: Any] = [:]) async throws -> Bool {
        guard let result = try await call(name, params: params) as? Bool else { throw AnkiError.invalidResponse }
        return result
    }

    private func command(_ name: String, params: [String: Any] = [:]) async throws {
        guard try await accepted(name, params: params) else {
            throw AnkiError.message("Anki declined \(name). Refresh the reviewer before trying again.")
        }
    }
    public func showAnswer() async throws { try await command("guiShowAnswer") }
    public func answer(ease: Int) async throws { try await command("guiAnswerCard", params: ["ease": ease]) }
    public func undo() async throws { try await command("guiUndo") }
}

@MainActor
public final class V1AnkiClient: AnkiClient {
    private struct Snapshot {
        let state: ReviewerState
        let cardID: String
        let token: String
        let ratings: Set<String>
    }
    private let transport: AnkiTransport
    private var nextID = 0
    private var snapshot: Snapshot?
    private var pendingOperation: String?
    var hasPendingOperation: Bool { pendingOperation != nil }

    public init(transport: AnkiTransport) { self.transport = transport }

    private func call(_ method: String, params: [String: Any] = [:]) async throws -> Any {
        nextID += 1
        let id = nextID
        let reply = try await transport.post(path: "/api/v1", body: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        // Older listeners may parse this as a legacy request instead of returning 404.
        if let error = reply["error"] as? String { throw AnkiError.legacy(error) }
        guard reply["jsonrpc"] as? String == "2.0", reply["id"] as? Int == id else { throw AnkiError.invalidResponse }
        if let error = reply["error"] as? [String: Any] { throw rpcError(error) }
        guard let result = reply["result"] else { throw AnkiError.invalidResponse }
        return result
    }

    private func rpcError(_ error: [String: Any]) -> AnkiError {
        .rpc(code: error["code"] as? Int ?? -32603,
             type: (error["data"] as? [String: Any])?["type"] as? String ?? "",
             message: error["message"] as? String ?? "Operation failed")
    }

    public func ping() async throws {
        // V1's discovery method is api.describe; “version” exists only in legacy.
        guard let description = try await call("api.describe") as? [String: Any],
              description["apiMajor"] as? Int == 1,
              description["ankiVersion"] is String,
              description["methods"] is [[String: Any]] else { throw AnkiError.invalidResponse }
    }

    public func reviewerState() async throws -> ReviewerState {
        snapshot = nil
        if let pendingOperation { try await waitForOperation(pendingOperation) }
        do {
            guard let value = try await call("reviewer.get") as? [String: Any],
                  let active = value["active"] as? Bool else { throw AnkiError.invalidResponse }
            guard active else { return .notReviewing }
            guard let side = value["side"] as? String else { throw AnkiError.invalidResponse }
            if side == "none" { return .notReviewing } // includes transitions
            guard let state = ReviewerState(rawValue: side), state == .question || state == .answer,
                  let card = value["card"] as? [String: Any], let id = card["id"] as? String,
                  let token = value["stateToken"] as? String, !token.isEmpty,
                  let answers = value["answers"] as? [[String: Any]] else { throw AnkiError.invalidResponse }
            snapshot = Snapshot(state: state, cardID: id, token: token,
                                ratings: Set(answers.compactMap { $0["rating"] as? String }))
            return state
        } catch AnkiError.rpc(_, let type, _) where type == "collectionUnavailable" {
            return .notReviewing
        }
    }

    public func showAnswer() async throws {
        guard let current = snapshot, current.state == .question else {
            throw AnkiError.message("Reviewer changed; press again after checking Anki.")
        }
        snapshot = nil
        guard let ack = try await call("reviewer.showAnswer", params: ["stateToken": current.token]) as? [String: Any],
              ack["changed"] as? Bool == true else { throw AnkiError.invalidResponse }
        let state = try await reviewerState()
        guard state == .answer, snapshot?.cardID == current.cardID else {
            snapshot = nil
            throw AnkiError.message("The card changed while showing its answer; no grade was sent.")
        }
    }

    public func answer(ease: Int) async throws {
        let names = [1: "again", 2: "hard", 3: "good", 4: "easy"]
        guard let current = snapshot, current.state == .answer,
              let rating = names[ease], current.ratings.contains(rating) else {
            throw AnkiError.message("This grade is not available on the current answer.")
        }
        snapshot = nil
        try await performOperation("reviewer.answer", params: ["stateToken": current.token, "rating": rating])
    }

    public func undo() async throws {
        snapshot = nil
        try await performOperation("collection.undo")
    }

    private func performOperation(_ method: String, params: [String: Any] = [:]) async throws {
        guard let handle = try await call(method, params: params) as? [String: Any],
              let id = handle["operationId"] as? String, !id.isEmpty else { throw AnkiError.invalidResponse }
        pendingOperation = id
        try await waitForOperation(id)
    }

    private func waitForOperation(_ id: String) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        repeat {
            guard let operation = try await call("operations.get", params: ["operationId": id]) as? [String: Any],
                  let state = operation["state"] as? String else { throw AnkiError.invalidResponse }
            switch state {
            case "succeeded": pendingOperation = nil; return
            case "failed", "cancelled":
                pendingOperation = nil
                throw rpcError(operation["error"] as? [String: Any] ?? [:])
            case "queued", "running", "waitingForUser": break
            default: throw AnkiError.invalidResponse
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        // Retain the handle; subsequent reads must resolve it before another write.
        throw AnkiError.message("Anki is still finishing the action. It was not repeated.")
    }
}

/// Probe both read-only discovery APIs, preferring V1. Never mutate during detection.
@MainActor
public final class AutoDetectAnkiClient: AnkiClient {
    private let legacy: LegacyAnkiClient
    private let v1: V1AnkiClient
    private let port: Int
    private var selected: AnkiClient?
    private var legacyAvailable = false
    public private(set) var apiDescription = "Detecting API"
    public private(set) var apiName: String?

    public init(transport: AnkiTransport) {
        legacy = LegacyAnkiClient(transport: transport)
        v1 = V1AnkiClient(transport: transport)
        port = transport.port
    }

    public func ping() async throws {
        // A connection check must not allow legacy fallback to overtake an unresolved V1 write.
        if v1.hasPendingOperation { _ = try await v1.reviewerState() }
        selected = nil
        apiName = nil
        apiDescription = "Detecting API"
        legacyAvailable = false
        var legacyError: Error?
        do { try await legacy.ping(); legacyAvailable = true }
        catch { legacyError = error }
        do {
            try await v1.ping()
            selected = v1
            apiName = "V1"
            apiDescription = "AnkiConnect V1"
        } catch {
            if let legacyError {
                apiDescription = "AnkiConnect not connected"
                // Authentication/version errors and absent replies do not prove a port clash.
                for failure in [legacyError, error] {
                    if let anki = failure as? AnkiError, anki.isAuthenticationFailure { throw anki }
                }
                for failure in [legacyError, error] {
                    if let anki = failure as? AnkiError, anki.isUnreachable { throw anki }
                    if let url = failure as? URLError { throw AnkiError.unreachable(port: port, reason: url.localizedDescription) }
                }
                if case AnkiError.unsupportedVersion = legacyError { throw legacyError }
                throw AnkiError.notAnkiConnect(port: port)
            }
            // A valid legacy version is sufficient even if V1 is absent or unrecognized.
            selected = legacy
            apiName = "legacy"
            apiDescription = "AnkiConnect Legacy v6"
        }
    }

    private func client() async throws -> AnkiClient {
        if selected == nil { try await ping() }
        guard let selected else { throw AnkiError.invalidResponse }
        return selected
    }
    public func reviewerState() async throws -> ReviewerState { try await client().reviewerState() }
    public func showAnswer() async throws { try await client().showAnswer() }
    public func answer(ease: Int) async throws { try await client().answer(ease: ease) }
    public func undo() async throws { try await client().undo() }
    public func performFast(_ action: RemoteAction, ease: Int) async throws -> (ActionFeedback?, ReviewerState) {
        let selected = try await client()
        if legacyAvailable, action != .reveal || selected is LegacyAnkiClient { return try await legacy.performFast(action, ease: ease) }
        let state = try await selected.reviewerState()
        guard state != .notReviewing else { return (nil, state) }
        return (try await selected.perform(action, from: state, ease: ease), try await selected.reviewerState())
    }
    public func perform(_ action: RemoteAction, from state: ReviewerState, ease: Int) async throws -> ActionFeedback {
        try await client().perform(action, from: state, ease: ease)
    }
}
