import AirAnkiCore
import CoreMotion
import Foundation

private final class MotionHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Double?
    func record(_ time: Double?) { lock.lock(); latest = time; lock.unlock() }
    func read() -> Double? { lock.lock(); defer { lock.unlock() }; return latest }
}

/// Per-earbud stream statistics, keyed by CMDeviceMotion.sensorLocation.
/// Shows whether motion really arrives from each AirPod or from only one at a time.
private final class BudMonitor: @unchecked Sendable {
    private struct Stats { var last = -Double.infinity; var times: [Double] = []; var peakAt = -Double.infinity; var peak = 0.0; var total = 0 }
    private var envelope = 0.0
    private let lock = NSLock()
    private var stats: [String: Stats] = [:]
    private var lastLocation: String?
    private var switches = 0

    static func name(_ location: CMDeviceMotion.SensorLocation) -> String {
        switch location {
        case .headphoneLeft: return "Left"
        case .headphoneRight: return "Right"
        default: return "Unknown"
        }
    }

    func record(_ location: String, at time: Double, magnitude: Double) {
        lock.lock(); defer { lock.unlock() }
        var s = stats[location] ?? Stats()
        s.last = time; s.total += 1
        s.times.append(time)
        if s.times.count > 60 { s.times.removeFirst(s.times.count - 60) }
        if magnitude > 3.5 { s.peak = magnitude; s.peakAt = time }
        envelope = max(magnitude, envelope * 0.8)
        stats[location] = s
        if let previous = lastLocation, previous != location { switches += 1 }
        lastLocation = location
    }

    func reset() { lock.lock(); stats = [:]; lastLocation = nil; switches = 0; envelope = 0; lock.unlock() }

    /// The AirPod streaming right now, and a 0…1 motion level for meters.
    func live(now: Double) -> (bud: String?, level: Double) {
        lock.lock(); defer { lock.unlock() }
        guard let name = lastLocation, let s = stats[name], now - s.last < 1 else { return (nil, 0) }
        return (name, min(1, envelope / 9))
    }

    func summary(now: Double) -> String {
        lock.lock(); defer { lock.unlock() }
        var lines: [String] = []
        let names = ["Left", "Right"] + (stats["Unknown"] == nil ? [] : ["Unknown"])
        for name in names {
            guard let s = stats[name] else { lines.append("\(name) AirPod: no data ○ (never seen)"); continue }
            let age = now - s.last
            if age < 1 {
                let recent = s.times.filter { now - $0 <= 1 }.count
                var line = "\(name) AirPod: receiving ● \(recent)/s"
                if now - s.peakAt < 0.6 { line += String(format: " — moving %.1f rad/s", s.peak) }
                lines.append(line)
            } else {
                lines.append(String(format: "\(name) AirPod: no data ○ (last seen %.0f s ago, %d samples)", age, s.total))
            }
        }
        if switches > 0 { lines.append("Stream switched between AirPods \(switches)×") }
        return lines.joined(separator: "\n")
    }
}

/// Mutable recognition state belongs only to the dedicated serial motion queue.
private final class MotionProcessor: @unchecked Sendable {
    var generation = 0
    var detector = CentroidDetector()
    var calibrationSession: CentroidCalibrationSession?
    var lastUI = -Double.infinity
    var labEnabled = false
    var onMotion: ((CMDeviceMotion) -> Void)?
    var onTrace: ((FlickTrace) -> Void)?
    var onCalibration: ((CalibrationSnapshot, CentroidCalibration?) -> Void)?
    func calibrate() {
        calibrationSession = CentroidCalibrationSession()
        detector.reset()
    }
    func process(_ motion: CMDeviceMotion) -> [FlickDetection] {
        if labEnabled { onMotion?(motion) }
        let r = motion.rotationRate, g = motion.gravity
        let sample = MotionSample(t: motion.timestamp, rotationRate: (r.x, r.y, r.z), gravity: (g.x, g.y, g.z))
        if let session = calibrationSession {
            if session.process(sample) {
                let counts = Dictionary(uniqueKeysWithValues: CentroidClass.allCases.map { ($0, session.captured($0)) })
                onCalibration?(CalibrationSnapshot(step: session.step, counts: counts, notice: session.notice,
                                                   complete: session.calibration != nil), session.calibration)
                if session.calibration != nil { calibrationSession = nil }
            }
            return []
        }
        return detector.process(sample)
    }
}

@MainActor
final class FlickInput: NSObject, CMHeadphoneMotionManagerDelegate {
    var onMotion: ((CMDeviceMotion) -> Void)?
    var onEvent: ((FlickDetection) -> Void)?
    var onTrace: ((FlickTrace) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onChange: (() -> Void)?
    var onMotionLost: (() -> Void)?
    var onAdaptation: ((CentroidCalibration) -> Void)?
    private(set) var streamHealth = MotionWatchdog()
    var onCalibration: ((CalibrationSnapshot, CentroidCalibration?) -> Void)?
    private(set) var isRunning = false
    private(set) var activeBud: String?
    private(set) var motionLevel = 0.0
    var permissionDenied: Bool {
        let status = CMHeadphoneMotionManager.authorizationStatus()
        return status == .denied || status == .restricted
    }
    private(set) var isReceiving = false
    private(set) var diagnostic: String?
    private(set) var budStatus = "Left AirPod: no data ○ (never seen)\nRight AirPod: no data ○ (never seen)"
    private let buds = BudMonitor()
    private let manager = CMHeadphoneMotionManager()
    private let processor = MotionProcessor()
    private let heartbeat = MotionHeartbeat()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.camerondent.AirAnki.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private var watchdog: Timer?
    private var generation = 0
    private var configurationGeneration = 0
    private var calibrationGeneration = 0

    var status: String {
        if streamHealth.isLost {
            return "AirPods motion lost — check connection" + (diagnostic.map { " — " + $0 } ?? "")
        }
        let state = isReceiving ? "receiving ●" : "no data ○"
        return diagnostic.map { "\(state) — \($0)" } ?? state
    }
    override init() { super.init(); manager.delegate = self }

    func configure(calibration: CentroidCalibration?, sensitivity: FlickSensitivity, reversed: Bool) {
        let onTrace = self.onTrace
        configurationGeneration += 1
        let revision = configurationGeneration
        let onAdaptation = self.onAdaptation
        motionQueue.addOperation { [processor] in
            processor.detector = CentroidDetector(calibration: calibration, sensitivity: sensitivity, reversed: reversed)
            processor.detector.onAdaptation = { [weak self] value in
                DispatchQueue.main.async { [weak self] in
                    guard self?.configurationGeneration == revision else { return }
                    onAdaptation?(value)
                }
            }
            processor.onTrace = onTrace
            processor.detector.onTrace = processor.labEnabled ? onTrace : nil
        }
    }
    func setLabEnabled(_ enabled: Bool) {
        let onMotion = self.onMotion
        motionQueue.addOperation { [processor] in
            processor.labEnabled = enabled; processor.onMotion = onMotion
            processor.detector.onTrace = enabled ? processor.onTrace : nil
        }
    }
    func calibrate() {
        configurationGeneration += 1
        calibrationGeneration += 1
        let revision = calibrationGeneration
        let callback = onCalibration
        motionQueue.addOperation { [processor] in
            processor.calibrate()
            processor.onCalibration = { [weak self] snapshot, calibration in
                DispatchQueue.main.async { [weak self] in
                    guard self?.calibrationGeneration == revision else { return }
                    callback?(snapshot, calibration)
                }
            }
        }
    }
    func cancelCalibration() {
        calibrationGeneration += 1
        motionQueue.addOperation { [processor] in processor.calibrationSession = nil; processor.detector.reset() }
    }
    func resetGestures() { motionQueue.addOperation { [processor] in processor.detector.reset() } }
    func start() {
        guard !isRunning else { return }
        isRunning = true; generation += 1
        heartbeat.record(nil)
        streamHealth.start(at: ProcessInfo.processInfo.systemUptime)
        resetGestures()
        manager.startConnectionStatusUpdates()
        startMotionIfAvailable()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStream() }
        }
        RunLoop.main.add(timer, forMode: .common); watchdog = timer
        onChange?()
    }
    func stop() {
        guard isRunning else { return }
        isRunning = false; generation += 1
        manager.stopDeviceMotionUpdates(); manager.stopConnectionStatusUpdates()
        let token = generation
        motionQueue.addOperation { [processor] in processor.generation = token }
        watchdog?.invalidate(); watchdog = nil
        resetGestures(); isReceiving = false; diagnostic = nil
        activeBud = nil; motionLevel = 0
        heartbeat.record(nil)
        streamHealth.stop()
        onChange?()
    }
    private func startMotionIfAvailable() {
        guard isRunning else { return }
        let authorization = CMHeadphoneMotionManager.authorizationStatus()
        if authorization == .denied || authorization == .restricted {
            setDiagnostic("Motion & Fitness permission denied or restricted. Open System Settings → Privacy & Security → Motion & Fitness")
            return
        }
        guard !manager.isDeviceMotionActive else { return }
        guard manager.isDeviceMotionAvailable else { setDiagnostic("Waiting for headphones"); return }
        let token = generation
        motionQueue.addOperation { [processor] in processor.generation = token }
        manager.startDeviceMotionUpdates(to: motionQueue) { [weak self, processor, heartbeat, buds] motion, error in
            guard processor.generation == token else { return }
            if let error {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isRunning, self.generation == token else { return }
                    self.setDiagnostic(error.localizedDescription)
                }
            }
            guard let motion else { return }
            let receivedAt = ProcessInfo.processInfo.systemUptime
            heartbeat.record(receivedAt)
            let r = motion.rotationRate
            buds.record(BudMonitor.name(motion.sensorLocation), at: receivedAt,
                        magnitude: (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot())
            var events = processor.process(motion)
            let now = ProcessInfo.processInfo.systemUptime
            for i in events.indices { events[i].firedAt = now }
            let update = now - processor.lastUI >= 0.1
            if update { processor.lastUI = now }
            // No per-sample main-queue dispatch or string formatting in normal review.
            if update || !events.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isRunning, self.generation == token else { return }
                    let recovered = self.streamHealth.received(at: receivedAt)
                    var changed = recovered || !self.isReceiving || self.diagnostic != nil
                    if self.refreshBudStatus() { changed = true }
                    self.isReceiving = true; self.diagnostic = nil
                    for event in events { self.onEvent?(event) }
                    if changed { self.onChange?() }
                }
            }
        }
    }
    /// Recomputes the per-AirPod summary and live level; true when either visibly changed.
    @discardableResult
    private func refreshBudStatus() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let text = buds.summary(now: now)
        let live = buds.live(now: now)
        let changed = text != budStatus || live.bud != activeBud || abs(live.level - motionLevel) > 0.04
        budStatus = text; activeBud = live.bud; motionLevel = live.level
        return changed
    }

    private func checkStream() {
        guard isRunning else { return }
        if refreshBudStatus() { onChange?() }
        let now = ProcessInfo.processInfo.systemUptime
        if let latest = heartbeat.read(), !streamHealth.isLost || now - latest < 2 {
            let recovered = streamHealth.received(at: latest)
            if recovered { onChange?() }
        }
        if streamHealth.check(at: now) {
            isReceiving = false; resetGestures(); onMotionLost?(); onChange?()
        }
        startMotionIfAvailable()
    }
    private func setDiagnostic(_ text: String) {
        guard diagnostic != text else { return }
        diagnostic = text; onError?(text); onChange?()
    }
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.onConnection?(true); self.startMotionIfAvailable()
        }
    }
    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.generation += 1; self.manager.stopDeviceMotionUpdates()
            let token = self.generation
            self.motionQueue.addOperation { [processor = self.processor] in processor.generation = token; processor.detector.reset() }
            self.isReceiving = false
            self.onConnection?(false); self.onChange?()
        }
    }
}
