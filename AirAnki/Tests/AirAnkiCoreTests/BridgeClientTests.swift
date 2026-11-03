import Foundation
import Darwin
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

@MainActor
private final class FakeBridge: BridgeServing {
    var lastVersion: String?
    var commands: [(String,Int,Int)] = []
    var replies: [BridgeReply] = []
    var failure: BridgeError?
    var suspended: CheckedContinuation<Void,Never>?
    var suspendFirst = false
    func request(_ command: String, ease: Int, count: Int) async throws -> BridgeReply {
        commands.append((command,ease,count))
        if suspendFirst { suspendFirst = false; await withCheckedContinuation { suspended = $0 } }
        if let failure { throw failure }
        guard !replies.isEmpty else { throw BridgeError.uncertain("missing test reply") }
        let reply = replies.removeFirst()
        if reply.ok { lastVersion = reply.version }
        return reply
    }
}
@MainActor
private final class FallbackClient: AnkiClient {
    var reads = 0, mutations = 0
    func reviewerState() async throws -> ReviewerState { reads += 1; return .question }
    func ping() async throws { reads += 1 }
    func showAnswer() async throws { mutations += 1 }
    func answer(ease: Int) async throws { mutations += 1 }
    func undo() async throws { mutations += 1 }
}

/// A temporary Unix socket, never an Anki endpoint. Serves one connection on a
/// worker queue, with a bounded accept wait and optional split/malformed replies.
private final class TestSocketServer: @unchecked Sendable {
    let path: String
    let fd: Int32
    let done = DispatchGroup()
    init(path: String = "/tmp/airanki-test-\(UUID().uuidString.prefix(8)).sock", requests: Int,
         wrongID: Bool = false, delay: UInt32 = 0, versions: [String?] = [], failedReplies: Set<Int> = []) throws {
        self.path = path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8)+[0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, listen(fd, 1) == 0 else { Darwin.close(fd); throw AnkiError.message("test socket bind") }
        done.enter()
        DispatchQueue.global().async { [self] in
            defer { Darwin.close(fd); unlink(path); done.leave() }
            var wait = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&wait, 1, 2000) > 0 else { return }
            let peer = accept(fd, nil, nil)
            guard peer >= 0 else { return }
            defer { Darwin.close(peer) }
            var one: Int32 = 1
            _ = setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var buffer = Data()
            for index in 0..<requests {
                while !buffer.contains(10) {
                    var wait = pollfd(fd: peer, events: Int16(POLLIN), revents: 0)
                    guard poll(&wait, 1, 1000) > 0 else { return }
                    var bytes = [UInt8](repeating: 0, count: 1024)
                    let count = read(peer, &bytes, bytes.count)
                    guard count > 0 else { return }
                    buffer.append(contentsOf: bytes.prefix(count))
                }
                let end = buffer.firstIndex(of: 10)!
                guard let request = try? JSONSerialization.jsonObject(with: buffer[..<end]) as? [String:Any],
                      let id = request["id"] as? Int else { return }
                buffer.removeSubrange(...end)
                if delay > 0 { usleep(delay) }
                let reply = BridgeReply(id: wrongID ? id+1 : id, ok: !failedReplies.contains(index),
                                        did: "showAnswer", side: "answer",
                                        version: index < versions.count ? versions[index] : nil)
                guard var bytes = try? JSONEncoder().encode(reply) else { return }
                bytes.append(10)
                // Force framing across multiple reads, including the newline separately.
                _ = bytes.withUnsafeBytes { Darwin.write(peer, $0.baseAddress!, $0.count-1) }
                usleep(1000)
                var newline: UInt8 = 10
                _ = Darwin.write(peer, &newline, 1)
            }
        }
    }
}

final class BridgeClientTests: XCTestCase {
    @MainActor func testVersionHandshakeAndLegacyReplies() async throws {
        let legacy = Data(#"{"id":1,"ok":true,"did":"none","side":"none","reviewing":false}"#.utf8)
        let decoded = try JSONDecoder().decode(BridgeReply.self, from: legacy)
        XCTAssertNil(decoded.version)
        let server = try TestSocketServer(requests: 4, versions: ["1.0.0", "9.0.0", "1.1.0", nil], failedReplies: [1])
        let client = BridgeClient(path: server.path)
        let controller = ReviewController(client: FallbackClient(), bridge: client)
        XCTAssertNil(client.lastVersion); XCTAssertNil(controller.bridgeVersion)
        await controller.refresh()
        XCTAssertEqual(client.lastVersion, "1.0.0"); XCTAssertEqual(controller.bridgeVersion, "1.0.0")
        let failed = try await client.request("ping")
        XCTAssertFalse(failed.ok); XCTAssertEqual(client.lastVersion, "1.0.0")
        _ = try await client.request("ping")
        XCTAssertEqual(controller.bridgeVersion, "1.1.0")
        _ = try await client.request("ping")
        XCTAssertNil(client.lastVersion); XCTAssertNil(controller.bridgeVersion)
    }
    @MainActor func testCentroidAmbiguousRevealsOnlyAndUndoNeverCompensates() async {
        let bridge = FakeBridge(), fallback = FallbackClient()
        bridge.replies = [.init(id: 1, did: "showAnswer", side: "answer"),
                          .init(id: 2, did: "none", side: "answer"),
                          .init(id: 3, did: "graded", ease: 4), .init(id: 4, did: "undone", count: 1)]
        let controller = ReviewController(client: fallback, bridge: bridge)
        var feedback: [ActionFeedback] = []
        controller.onFeedback = { feedback.append($0) }
        let revealed = await controller.handleFlick(.init(t: 1, event: .ambiguous))
        let unclear = await controller.handleFlick(.init(t: 2, event: .ambiguous))
        _ = await controller.handleFlick(.init(t: 3, event: .right))
        let undo = await controller.handleFlick(.init(t: 4, event: .undo, speculativeFlickAt: 3))
        XCTAssertEqual(revealed, .completed(.showedAnswer)); XCTAssertEqual(unclear, .completed(.unclear))
        XCTAssertEqual(unclear.title, "unclear flick — try again")
        XCTAssertEqual(undo, .completed(.undone))
        XCTAssertEqual(bridge.commands.map { $0.0 }, ["reveal","reveal","right","undo"])
        XCTAssertEqual(bridge.commands.last?.2, 1)
        XCTAssertEqual(fallback.reads, 0); XCTAssertEqual(fallback.mutations, 0)
        XCTAssertEqual(feedback, [.showedAnswer,.unclear,.graded(4),.undone])
    }
    @MainActor func testCentroidUndoDuringBusyRequestIsDropped() async {
        let bridge = FakeBridge(); bridge.suspendFirst = true
        bridge.replies = [.init(id: 1, did: "graded", ease: 4)]
        let controller = ReviewController(client: FallbackClient(), bridge: bridge)
        let task = Task { await controller.handleFlick(.init(t: 1, event: .right)) }
        while bridge.suspended == nil { await Task.yield() }
        let outcome = await controller.handleFlick(.init(t: 2, event: .undo))
        XCTAssertEqual(outcome, .discarded("busy")); XCTAssertEqual(bridge.commands.count, 1)
        bridge.suspended?.resume(); bridge.suspended = nil
        _ = await task.value
        XCTAssertEqual(bridge.commands.count, 1)
    }

    @MainActor func testBridgeActionsAndStateHaveNoHTTPReads() async {
        let bridge = FakeBridge(), fallback = FallbackClient()
        bridge.replies = [.init(id: 1, side: "answer"), .init(id: 2, did: "graded", ease: 3, side: "question"), .init(id: 3, reviewing: false)]
        let controller = ReviewController(client: fallback, bridge: bridge)
        await controller.refresh()
        let outcome = await controller.handleAction(.showOrGrade(ease: 3), at: ProcessInfo.processInfo.systemUptime)
        XCTAssertEqual(outcome, .completed(.graded(3)))
        XCTAssertEqual(controller.status, .ready(.question)); XCTAssertEqual(controller.link, .bridge)
        await controller.refresh()
        XCTAssertEqual(controller.status, .ready(.notReviewing))
        XCTAssertEqual(fallback.reads, 0); XCTAssertEqual(fallback.mutations, 0)
        XCTAssertEqual(bridge.commands.map { $0.0 }, ["state","right","state"])
        XCTAssertTrue((controller.lastLatencyMS ?? 999) < 100)
    }
    @MainActor func testUnavailableFallsBackButUncertainNeverDoes() async {
        for failure in [BridgeError.unavailable, .uncertain("timeout")] {
            let bridge = FakeBridge(), fallback = FallbackClient(); bridge.failure = failure
            let controller = ReviewController(client: fallback, bridge: bridge)
            let outcome = await controller.handleAction(.showOrGrade(ease: 4), at: 0)
            if case .unavailable = failure {
                XCTAssertEqual(outcome, .completed(.showedAnswer)); XCTAssertEqual(fallback.mutations, 1)
            } else {
                if case .failed = outcome { } else { XCTFail("expected uncertainty") }
                XCTAssertEqual(fallback.reads, 0); XCTAssertEqual(fallback.mutations, 0)
            }
        }
    }
    @MainActor func testSpeculativeShowAndGradeUndoCounts() async {
        for did in ["showAnswer","graded"] {
            let bridge = FakeBridge(), fallback = FallbackClient()
            bridge.replies = [.init(id: 1, did: did, ease: did == "graded" ? 4 : nil), .init(id: 2, did: "undone", count: did == "graded" ? 2 : 1)]
            let controller = ReviewController(client: fallback, bridge: bridge)
            _ = await controller.handleLegacyFlick(.init(t: 1, event: .right))
            let undo = await controller.handleLegacyFlick(.init(t: 1.2, event: .shake, speculativeFlickAt: 1))
            XCTAssertEqual(undo, .completed(.undone))
            XCTAssertEqual(bridge.commands.map { $0.0 }, ["right","undo"])
            XCTAssertEqual(bridge.commands.last?.2, did == "graded" ? 2 : 1)
        }
    }
    @MainActor func testShakeWaitsForInFlightReplyAndBlocksOtherActions() async {
        let bridge = FakeBridge(); bridge.suspendFirst = true
        bridge.replies = [.init(id: 1, did: "graded", ease: 4), .init(id: 2, did: "undone", count: 2)]
        let controller = ReviewController(client: FallbackClient(), bridge: bridge)
        let flick = Task { await controller.handleLegacyFlick(.init(t: 1, event: .right)) }
        while bridge.suspended == nil { await Task.yield() }
        let shake = Task { await controller.handleLegacyFlick(.init(t: 1.2, event: .shake, speculativeFlickAt: 1)) }
        await Task.yield()
        let other = await controller.handleAction(.showOrGrade(ease: 4), at: 2)
        XCTAssertEqual(other, .discarded("busy"))
        XCTAssertEqual(bridge.commands.count, 1)
        bridge.suspended?.resume(); bridge.suspended = nil
        _ = await flick.value
        let outcome = await shake.value
        XCTAssertEqual(outcome, .completed(.undone)); XCTAssertEqual(bridge.commands.last?.2, 2)
    }
    @MainActor func testUncertainSpeculationDoesNotUndoBlindly() async {
        let bridge = FakeBridge(); bridge.failure = .uncertain("timeout")
        let controller = ReviewController(client: FallbackClient(), bridge: bridge)
        _ = await controller.handleLegacyFlick(.init(t: 1, event: .right))
        let undo = await controller.handleLegacyFlick(.init(t: 1.2, event: .shake, speculativeFlickAt: 1))
        if case .failed = undo { } else { XCTFail("must report uncertainty") }
        XCTAssertEqual(bridge.commands.count, 1)
    }
    @MainActor func testPersistentSocketIDsAndSplitFrames() async throws {
        let server = try TestSocketServer(requests: 2)
        let client = BridgeClient(path: server.path)
        let first = try await client.request("right"), second = try await client.request("left")
        XCTAssertEqual(first.id, 1); XCTAssertEqual(second.id, 2)
        XCTAssertEqual(second.side, "answer")
    }
    @MainActor func testSocketReconnectAfterBackoff() async throws {
        let path = "/tmp/airanki-test-\(UUID().uuidString.prefix(8)).sock"
        let client = BridgeClient(path: path)
        do { _ = try await client.request("ping"); XCTFail("socket should be absent") }
        catch BridgeError.unavailable { }
        let server = try TestSocketServer(path: path, requests: 1)
        do { _ = try await client.request("ping"); XCTFail("backoff should prevent an immediate connect") }
        catch BridgeError.unavailable { }
        try await Task.sleep(nanoseconds: 150_000_000)
        let reply = try await client.request("ping")
        XCTAssertTrue(reply.ok); XCTAssertEqual(reply.id, 1)
        _ = server
    }
    @MainActor func testSocketTimeoutWrongIDAndAbsentBackoff() async throws {
        for wrongID in [true,false] {
            let server = try TestSocketServer(requests: 1, wrongID: wrongID, delay: wrongID ? 0 : 400000)
            let client = BridgeClient(path: server.path)
            let began = ProcessInfo.processInfo.systemUptime
            do { _ = try await client.request("right"); XCTFail("expected failure") }
            catch BridgeError.uncertain { }
            catch { XCTFail("wrong failure: \(error)") }
            XCTAssertTrue(ProcessInfo.processInfo.systemUptime - began < 0.6)
        }
        let client = BridgeClient(path: "/tmp/airanki-absent-\(UUID().uuidString.prefix(8)).sock")
        for _ in 0..<2 {
            do { _ = try await client.request("ping"); XCTFail("absent socket") }
            catch BridgeError.unavailable { }
            catch { XCTFail("wrong failure") }
        }
    }
}
