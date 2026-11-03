import Foundation
import Darwin

public enum BridgeError: LocalizedError {
    /// No bytes were sent; falling back to AnkiConnect is safe.
    case unavailable
    /// A write may have reached Anki. Never fall back or repeat this request.
    case uncertain(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "AirAnki Bridge unavailable"
        case .uncertain(let text): return "Bridge: \(text). Action not repeated."
        }
    }
}

public struct BridgeReply: Codable, Equatable, Sendable {
    public let id: Int
    public let ok: Bool
    public let did: String
    public let ease: Int?
    public let count: Int?
    public let side: String
    public let reviewing: Bool
    public let error: String?
    public let version: String?
    public init(id: Int, ok: Bool = true, did: String = "none", ease: Int? = nil, count: Int? = nil,
                side: String = "question", reviewing: Bool = true, error: String? = nil, version: String? = nil) {
        self.id = id; self.ok = ok; self.did = did; self.ease = ease; self.count = count
        self.side = side; self.reviewing = reviewing; self.error = error; self.version = version
    }
    public var reviewerState: ReviewerState {
        guard reviewing else { return .notReviewing }
        return ReviewerState(rawValue: side) ?? .reviewing
    }
    public var feedback: ActionFeedback? {
        switch did {
        case "showAnswer": return .showedAnswer
        case "graded": return ease.map(ActionFeedback.graded)
        case "undone": return .undone
        default: return nil
        }
    }
}

@MainActor
public protocol BridgeServing: AnyObject {
    var lastVersion: String? { get }
    func request(_ command: String, ease: Int, count: Int) async throws -> BridgeReply
}

@MainActor
public final class BridgeClient: BridgeServing {
    public nonisolated static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AirAnki/bridge.sock").path
    }
    public private(set) var lastVersion: String?
    private let worker: SocketWorker
    public init(path: String = BridgeClient.defaultPath) { worker = SocketWorker(path: path) }
    public func request(_ command: String, ease: Int = 4, count: Int = 1) async throws -> BridgeReply {
        let reply: BridgeReply = try await withCheckedThrowingContinuation { continuation in
            worker.queue.async { [worker] in
                do { continuation.resume(returning: try worker.request(command, ease: ease, count: count)) }
                catch { continuation.resume(throwing: error) }
            }
        }
        if reply.ok { lastVersion = reply.version }
        return reply
    }
}

/// All descriptor and framing state is confined to this serial queue. Poll blocks
/// this worker only, with one 300 ms deadline covering connect/write/read.
private final class SocketWorker: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.camerondent.AirAnki.bridge", qos: .userInteractive)
    let path: String
    var fd: Int32 = -1
    var nextID = 0
    var retryAt = 0.0
    var backoff = 0.1
    var buffer = Data()
    init(path: String) { self.path = path }
    deinit { if fd >= 0 { Darwin.close(fd) } }
    func disconnect() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        buffer.removeAll(keepingCapacity: true)
        retryAt = ProcessInfo.processInfo.systemUptime + backoff
        backoff = min(2, backoff * 2)
    }
    func ready(_ events: Int16, until deadline: Double) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw BridgeError.uncertain("300 ms timeout") }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(&descriptor, 1, Int32(ceil(remaining * 1000)))
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw BridgeError.uncertain("300 ms timeout or socket error") }
            if descriptor.revents & events != 0 { return }
            throw BridgeError.uncertain("connection closed")
        }
    }
    func connect(until deadline: Double) throws {
        if fd >= 0 { return }
        guard ProcessInfo.processInfo.systemUptime >= retryAt else { throw BridgeError.unavailable }
        let bytes = Array(path.utf8) + [0]
        var address = sockaddr_un()
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw BridgeError.unavailable }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.unavailable }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        do {
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw BridgeError.unavailable }
                try ready(Int16(POLLOUT), until: deadline)
                var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw BridgeError.unavailable }
            }
        } catch { disconnect(); throw BridgeError.unavailable }
    }
    func request(_ command: String, ease: Int, count: Int) throws -> BridgeReply {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        try connect(until: deadline)
        nextID += 1
        let id = nextID
        var payload = try JSONSerialization.data(withJSONObject: ["id": id, "cmd": command, "ease": ease, "count": count])
        payload.append(10)
        // Once connected we conservatively treat any write-side error as uncertain.
        do {
            try payload.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    try ready(Int16(POLLOUT), until: deadline)
                    let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if written < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                    guard written > 0 else { throw BridgeError.uncertain("write failed") }
                    offset += written
                }
            }
            while !buffer.contains(10) {
                try ready(Int16(POLLIN), until: deadline)
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = Darwin.read(fd, &bytes, bytes.count)
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                guard count > 0 else { throw BridgeError.uncertain("connection closed before reply") }
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 65536 else { throw BridgeError.uncertain("oversized reply") }
            }
            let end = buffer.firstIndex(of: 10)!
            let line = buffer[..<end]
            guard let reply = try? JSONDecoder().decode(BridgeReply.self, from: line), reply.id == id,
                  ["none", "showAnswer", "graded", "undone"].contains(reply.did),
                  ["question", "answer", "none"].contains(reply.side),
                  reply.did != "graded" || (1...4).contains(reply.ease ?? 0) else {
                throw BridgeError.uncertain("invalid reply or request id")
            }
            buffer.removeSubrange(...end)
            guard buffer.isEmpty else { throw BridgeError.uncertain("unsolicited reply") }
            backoff = 0.1; retryAt = 0
            return reply
        } catch {
            disconnect()
            if let error = error as? BridgeError { throw error }
            throw BridgeError.uncertain(error.localizedDescription)
        }
    }
}
