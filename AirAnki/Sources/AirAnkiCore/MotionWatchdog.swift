import Foundation

/// Host-clock watchdog: reports loss once per outage, including no samples at startup.
public struct MotionWatchdog {
    public private(set) var isLost = false
    private var lastSample: Double?
    public init() {}
    public mutating func start(at time: Double) { lastSample = time; isLost = false }
    public mutating func stop() { lastSample = nil; isLost = false }
    @discardableResult public mutating func received(at time: Double) -> Bool {
        guard time.isFinite, let lastSample, time > lastSample else { return false }
        let recovered = isLost
        self.lastSample = time; isLost = false
        return recovered
    }
    @discardableResult public mutating func check(at time: Double) -> Bool {
        guard let lastSample, !isLost, time - lastSample >= 2 else { return false }
        isLost = true
        return true
    }
}

public struct AdaptationPersistence {
    private var lastSave: Double
    public init(at time: Double) { lastSave = time }
    public mutating func shouldSave(at time: Double) -> Bool {
        guard time - lastSave >= 30 else { return false }
        lastSave = time
        return true
    }
}
