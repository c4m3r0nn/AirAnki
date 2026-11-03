import Foundation

public enum FlickSensitivity: String, CaseIterable, Sendable {
    case low, medium, high
    public var scale: Double {
        switch self {
        case .low: return 1.35
        case .medium: return 1.0
        case .high: return 0.75
        }
    }
}

public struct MotionSample: Sendable {
    public let t: TimeInterval
    public let rotationRate: (x: Double, y: Double, z: Double)
    public let gravity: (x: Double, y: Double, z: Double)
    public init(t: TimeInterval, rotationRate: (x: Double, y: Double, z: Double),
                gravity: (x: Double, y: Double, z: Double)) {
        self.t = t; self.rotationRate = rotationRate; self.gravity = gravity
    }
}

public enum FlickEvent: String, Equatable, Sendable {
    case left, right, undo, ambiguous, shake
    public var csvEvent: String {
        switch self {
        case .right, .left: return "flick_" + rawValue
        case .undo, .ambiguous, .shake: return rawValue
        }
    }
    public func action(easeForRight: Int = 4) -> RemoteAction {
        switch self {
        case .left: return .showOrGrade(ease: 1)
        case .right: return .showOrGrade(ease: Mapping.validatedEase(easeForRight))
        case .undo, .shake: return .undo
        case .ambiguous: return .reveal
        }
    }
}

public struct FlickDetection: Equatable, Sendable {
    /// All times use the monotonic sensor clock.
    public let t: TimeInterval
    public let event: FlickEvent
    /// Live host time when processing emitted this event; nil in offline replay.
    public var firedAt: TimeInterval? = nil
    public var onset: TimeInterval
    public var peakTime: TimeInterval
    public var speculativeFlickAt: TimeInterval?
    public init(t: TimeInterval, event: FlickEvent, onset: TimeInterval? = nil,
                peakTime: TimeInterval? = nil, speculativeFlickAt: TimeInterval? = nil) {
        self.t = t; self.event = event; self.onset = onset ?? t
        self.peakTime = peakTime ?? t; self.speculativeFlickAt = speculativeFlickAt
    }
}

public struct FlickTrace: Sendable {
    public let t: TimeInterval
    /// nil means rejected; non-nil means an event was actually delivered.
    public let event: FlickEvent?
    public let reason: String
    public let peakYaw: Double
    public let angle: Double
    public var sR: Double? = nil
    public var sL: Double? = nil
    public var latency: Double? = nil
    public var csvEvent: String { event?.csvEvent ?? "flick_rejected" }
    public var detail: String {
        if let sR, let sL, let latency {
            return String(format: "%@; sR=%.3f; sL=%.3f; peak=%.2f rad/s; latency=%.1f ms",
                          reason, sR, sL, peakYaw, latency * 1000)
        }
        return String(format: "%@; angle=%.1f deg; peak=%.2f rad/s", locale: Locale(identifier: "en_US_POSIX"),
               reason, angle * 180 / .pi, peakYaw)
    }
}
