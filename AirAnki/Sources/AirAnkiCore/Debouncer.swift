import Foundation

public struct Debouncer {
    public static let threshold: TimeInterval = 0.120
    private var previous: TimeInterval?

    public init() {}

    /// Sliding quiet period: even discarded events count as the previous event.
    public mutating func accept(at time: TimeInterval) -> Bool {
        defer { previous = time }
        guard let previous else { return true }
        return time - previous >= Self.threshold
    }
}
