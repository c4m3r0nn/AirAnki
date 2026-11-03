import Foundation

/// The names used in Lab CSVs match the MediaPlayer commands, without “Command”.
public enum StemCommand: String, CaseIterable, Sendable {
    case togglePlayPause, play, pause, nextTrack, previousTrack

    public func gesture(ignoreExplicitPlayPause: Bool = true) -> Gesture? {
        switch self {
        case .togglePlayPause: return .single
        case .play, .pause: return ignoreExplicitPlayPause ? nil : .single
        case .nextTrack: return .double
        case .previousTrack: return .triple
        }
    }

    public static func ignoreExplicitPlayPause(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: "ignoreExplicitPlayPause") == nil
            ? true : defaults.bool(forKey: "ignoreExplicitPlayPause")
    }
}

public struct StemEvent: Sendable {
    public let id = UUID()
    public let command: StemCommand
    public let time: TimeInterval
    public let wall: Date
    public let gesture: Gesture?
    public let detail: String

    public init(command: StemCommand, time: TimeInterval, wall: Date,
                ignoreExplicitPlayPause: Bool = true, isListening: Bool = true) {
        self.command = command
        self.time = time
        self.wall = wall
        let mapped = command.gesture(ignoreExplicitPlayPause: ignoreExplicitPlayPause)
        gesture = isListening ? mapped : nil
        detail = mapped == nil ? "ignored-ear-detection" : isListening ? "" : "ignored-remote-paused"
    }

    public var csvEvent: String { gesture.map { "stem_\($0.rawValue)" } ?? "stem_ignored" }

    public var initialOutcome: String {
        if detail == "ignored-ear-detection" { return "ignored (ear detection?)" }
        if gesture == nil { return "ignored (remote paused)" }
        return "Processing…"
    }
}

/// A completed action must not overwrite a newer raw event in the status window.
public struct LastPressStatus: Sendable {
    public private(set) var event: StemEvent?
    public private(set) var outcome = "No presses yet"

    public init() {}

    public mutating func record(_ event: StemEvent) {
        self.event = event
        outcome = event.initialOutcome
    }

    public mutating func complete(_ event: StemEvent, outcome: String) {
        guard self.event?.id == event.id else { return }
        self.outcome = outcome
    }

    public var title: String {
        guard let event else { return outcome }
        let gesture = event.gesture?.rawValue.capitalized ?? "No gesture"
        let time = event.wall.formatted(date: .omitted, time: .standard)
        return "\(gesture) · \(event.command.rawValue) · \(time) → \(outcome)"
    }
}
