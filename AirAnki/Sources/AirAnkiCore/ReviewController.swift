import Foundation

public enum ReviewStatus: Equatable {
    case connecting, ready(ReviewerState), error(String)

    public var title: String {
        switch self {
        case .connecting: return "Connecting to Anki…"
        case .ready(.question): return "Anki: question"
        case .ready(.answer): return "Anki: answer"
        case .ready(.reviewing): return "Anki: reviewing"
        case .ready(.notReviewing): return "Anki: open a deck to review"
        case .error(let message): return message
        }
    }
}

@MainActor
public final class ReviewController {
    public var mapping = Mapping()
    public var easeForSingle = 4
    public var onStatus: ((ReviewStatus) -> Void)?
    public var onFeedback: ((ActionFeedback) -> Void)?
    public var onBusyChange: (() -> Void)?
    public private(set) var status: ReviewStatus = .connecting {
        didSet { onStatus?(status) }
    }
    public private(set) var isBusy = false {
        didSet {
            onBusyChange?()
            if !isBusy {
                let waiters = busyWaiters; busyWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
    }
    public enum Link: String { case bridge = "Bridge (instant)", ankiConnect = "AnkiConnect (slower)", none = "none" }
    public private(set) var link: Link = .none
    public private(set) var lastLatencyMS: Double?
    public var onLatency: ((Double) -> Void)?
    public var bridgeVersion: String? { bridge?.lastVersion }
    private let bridge: BridgeServing?
    private var flickTasks: [Double: Task<GestureOutcome, Never>] = [:]
    private var flickOutcomes: [Double: GestureOutcome] = [:]
    private var compensating = false
    private var busyWaiters: [CheckedContinuation<Void, Never>] = []
    private let client: AnkiClient
    private var debouncer = Debouncer()

    public init(client: AnkiClient, bridge: BridgeServing? = nil) {
        self.client = client; self.bridge = bridge
    }

    /// Used at startup and on explicit reconnect. Shares the action lock.
    public func refresh(redetect: Bool = true) async {
        guard !isBusy, !compensating else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let bridge {
                do {
                    let reply = try await bridge.request("state", ease: 4, count: 1)
                    try apply(reply)
                    link = .bridge
                    return
                } catch BridgeError.unavailable { /* Safe to use the loopback fallback. */ }
            }
            if redetect { try await client.ping() }
            status = .ready(try await client.reviewerState())
            link = .ankiConnect
        } catch {
            link = .none
            status = .error(error.localizedDescription)
        }
    }

    private func apply(_ reply: BridgeReply) throws {
        guard reply.ok else { throw BridgeError.uncertain(reply.error ?? "command failed") }
        status = .ready(reply.reviewerState)
    }

    /// Live centroid gestures never speculate or compensate a previous action.
    public func handleFlick(_ detection: FlickDetection, easeForRight: Int = 4) async -> GestureOutcome {
        await execute(detection.event.action(easeForRight: easeForRight), at: detection.t, firedAt: detection.firedAt)
    }

    /// Only shake compensation may wait for a specific speculative action. Ordinary
    /// gestures retain the drop-while-busy rule; nothing is retried after uncertainty.
    public func handleLegacyFlick(_ detection: FlickDetection, easeForRight: Int = 4) async -> GestureOutcome {
        if detection.event == .shake {
            guard !compensating else { return .discarded("busy") }
            compensating = true
            defer { compensating = false }
            var count = 1
            if let time = detection.speculativeFlickAt {
                let outcome: GestureOutcome?
                if let task = flickTasks[time] { outcome = await task.value }
                else { outcome = flickOutcomes[time] }
                if case .completed(.graded)? = outcome { count = 2 }
                if case .failed? = outcome {
                    return .failed("Speculative action is uncertain. Inspect Anki before undoing.")
                }
            }
            if isBusy { await withCheckedContinuation { busyWaiters.append($0) } }
            return await execute(.undo, at: detection.t, undoCount: count, compensation: true, firedAt: detection.firedAt)
        }
        let task = Task { await self.execute(detection.event.action(easeForRight: easeForRight), at: detection.t, firedAt: detection.firedAt) }
        flickTasks[detection.t] = task
        let outcome = await task.value
        flickTasks[detection.t] = nil
        flickOutcomes = flickOutcomes.filter { detection.t - $0.key < 1 }
        flickOutcomes[detection.t] = outcome
        return outcome
    }

    /// Returns false for a discarded gesture. Actions are never queued or retried.
    @discardableResult
    public func handle(_ gesture: Gesture, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) async -> Bool {
        await handleWithOutcome(gesture, at: time).wasAccepted
    }

    public func handleWithOutcome(_ gesture: Gesture, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) async -> GestureOutcome {
        await handleAction(mapping[gesture], at: time)
    }

    /// Motion and experimental stems share the same quiet period and action lock.
    public func handleAction(_ action: RemoteAction, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) async -> GestureOutcome {
        await execute(action, at: time)
    }

    private func execute(_ action: RemoteAction, at time: TimeInterval, undoCount: Int = 1,
                         compensation: Bool = false, firedAt: Double? = nil) async -> GestureOutcome {
        if !compensation, !debouncer.accept(at: time) { return .discarded("debounce") }
        guard !isBusy, !compensating || compensation else { return .discarded("busy") }
        guard action != .none else { return .discarded("mapped to Do nothing") }
        isBusy = true
        let fireTime = firedAt ?? ProcessInfo.processInfo.systemUptime
        defer {
            lastLatencyMS = max(0, (ProcessInfo.processInfo.systemUptime - fireTime) * 1000)
            onLatency?(lastLatencyMS!)
            isBusy = false
        }
        let ease = Mapping.validatedEase(easeForSingle)
        var completedAction: ActionFeedback?
        do {
            if let bridge, action != .again {
                let command: String, grade: Int
                switch action {
                case .showOrGrade(let requested): command = requested == 1 ? "left" : "right"; grade = requested
                case .showOrEasy: command = "right"; grade = ease
                case .undo: command = "undo"; grade = ease
                case .reveal: command = "reveal"; grade = ease
                default: command = "state"; grade = ease
                }
                do {
                    let reply = try await bridge.request(command, ease: grade, count: undoCount)
                    link = .bridge
                    try apply(reply)
                    if action == .reveal, reply.reviewing, reply.side == "answer", reply.did == "none" {
                        onFeedback?(.unclear)
                        return .completed(.unclear)
                    }
                    guard let feedback = reply.feedback else {
                        return reply.reviewing ? .discarded("Anki made no change") : .notReviewing
                    }
                    onFeedback?(feedback)
                    return .completed(feedback)
                } catch BridgeError.unavailable { /* No write was sent. */ }
                catch {
                    status = .error(error.localizedDescription); onFeedback?(.error)
                    return .failed(error.localizedDescription)
                }
            }
            if let fast = client as? AutoDetectAnkiClient {
                link = .ankiConnect
                var feedback: ActionFeedback?, state: ReviewerState = .notReviewing
                for _ in 0..<(action == .undo ? undoCount : 1) {
                    (feedback, state) = try await fast.performFast(action, ease: ease)
                    if feedback == nil { break }
                }
                status = .ready(state)
                guard let feedback else { return .notReviewing }
                onFeedback?(feedback)
                return .completed(feedback)
            }
            let state = try await client.reviewerState()
            guard state != .notReviewing else {
                status = .ready(.notReviewing)
                return .notReviewing
            }
            var feedback = try await client.perform(action, from: state, ease: ease)
            if action == .undo, undoCount > 1 {
                for _ in 1..<undoCount { feedback = try await client.perform(.undo, from: state, ease: ease) }
            }
            completedAction = feedback
            // A failed refresh is an error, not an invitation to repeat the mutation.
            status = .ready(try await client.reviewerState())
            onFeedback?(feedback)
            return .completed(feedback)
        } catch {
            // Read-only reconciliation after an uncertain result; never retry a write.
            _ = try? await client.reviewerState()
            status = .error(error.localizedDescription)
            onFeedback?(.error)
            return .failed(error.localizedDescription, completedAction: completedAction)
        }
    }
}
