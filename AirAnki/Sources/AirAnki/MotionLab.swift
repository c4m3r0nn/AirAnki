import AirAnkiCore
import CoreMotion
import Foundation
import os

/// Immutable value snapshot; CoreMotion objects never cross into the writer queue.
private struct LabMotion: Sendable {
    let t: Double
    let location: String
    let values: [Double]
    init(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration, r = motion.rotationRate, g = motion.gravity
        let ua = sqrt(a.x*a.x+a.y*a.y+a.z*a.z), rr = sqrt(r.x*r.x+r.y*r.y+r.z*r.z)
        t = motion.timestamp
        switch motion.sensorLocation {
        case .headphoneLeft: location = "left"
        case .headphoneRight: location = "right"
        default: location = "unknown"
        }
        values = [a.x,a.y,a.z,ua,r.x,r.y,r.z,rr,g.x,g.y,g.z,motion.attitude.pitch,motion.attitude.roll,motion.attitude.yaw]
    }
}

/// Serial writer owns the formatter, CSV buffer, file and counters. The motion
/// queue only enqueues a sample; neither formatting nor disk I/O runs there.
private final class LabWriter: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.camerondent.AirAnki.lab-writer", qos: .utility)
    var file: FileHandle?
    var buffer = Data()
    let iso: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    var samples = 0, marker = 0
    var maxUA = 0.0, maxRR = 0.0, lastSample = 0.0
    var failure: String?
    func row(event: String, time: Double = ProcessInfo.processInfo.systemUptime, wall: Date = Date(),
             location: String = "", values: [Double] = [], command: String = "", marker: Int? = nil, detail: String = "") {
        guard file != nil else { return }
        buffer.append(contentsOf: LabCSV.row(monotonic: time, wallISO: iso.string(from: wall), event: event,
                         location: location, values: values, rawCommand: command, marker: marker, detail: detail).utf8)
        if buffer.count >= 65536 { flush() }
    }
    func motion(_ motion: LabMotion) {
        guard file != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        row(event: "motion", time: motion.t, wall: Date().addingTimeInterval(motion.t-now), location: motion.location, values: motion.values)
        samples += 1; maxUA = max(maxUA, motion.values[3]); maxRR = max(maxRR, motion.values[7]); lastSample = now
    }
    func flush() {
        guard let file, !buffer.isEmpty else { return }
        do { try file.write(contentsOf: buffer) }
        catch { failure = error.localizedDescription; try? file.close(); self.file = nil }
        buffer.removeAll(keepingCapacity: true)
    }
    func close() { flush(); try? file?.close(); file = nil }
}

@MainActor
final class MotionLab {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AirAnki", isDirectory: true)
    var onChange: (() -> Void)?
    private(set) var isActive = false
    private(set) var status = "Lab off"
    private(set) var fileURL: URL?
    private let terminal: Bool
    private nonisolated let writer = LabWriter()
    private var timer: Timer?
    private var generation = 0
    private var windowStart = 0.0
    private let logger = Logger(subsystem: "com.camerondent.AirAnki", category: "MotionLab")
    init(terminal: Bool) { self.terminal = terminal }
    func start() throws {
        guard !isActive else { return }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "lab-\(formatter.string(from: Date()))"
        var url = Self.folder.appendingPathComponent("\(stem).csv"), suffix = 1
        while FileManager.default.fileExists(atPath: url.path) { url = Self.folder.appendingPathComponent("\(stem)-\(suffix).csv"); suffix += 1 }
        guard FileManager.default.createFile(atPath: url.path, contents: Data(LabCSV.header.utf8)) else {
            throw AnkiError.message("Could not create the Lab CSV.")
        }
        let file = try FileHandle(forWritingTo: url); try file.seekToEnd()
        writer.queue.async { [writer] in
            writer.file = file; writer.samples = 0; writer.marker = 0; writer.maxUA = 0; writer.maxRR = 0
            writer.failure = nil; writer.lastSample = 0
        }
        generation += 1; fileURL = url; isActive = true; windowStart = ProcessInfo.processInfo.systemUptime
        status = "Lab: waiting for motion"
        if terminal { print("Lab CSV: \(url.path)\nPress Return to insert a numbered marker. Ctrl+C stops recording.") }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.summarize() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer; onChange?()
    }
    func stop() {
        isActive = false; generation += 1; timer?.invalidate(); timer = nil
        // Drain at stop/quit only. Normal recording never blocks the motion queue or UI on disk.
        writer.queue.sync { writer.close() }
        status = "Lab off"; onChange?()
    }
    func insertMarker() {
        guard isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime, wall = Date(), terminal = self.terminal
        writer.queue.async { [writer] in
            writer.marker += 1; writer.row(event: "marker", time: now, wall: wall, marker: writer.marker); writer.flush()
            if terminal { print("Marker \(writer.marker)") }
        }
    }
    func recordStem(_ event: StemEvent) {
        writer.queue.async { [writer] in writer.row(event: event.csvEvent, time: event.time, wall: event.wall, command: event.command.rawValue, detail: event.detail) }
    }
    nonisolated func recordDecision(_ trace: FlickTrace) {
        writer.queue.async { [writer] in
            guard writer.file != nil else { return }
            writer.row(event: trace.csvEvent, time: trace.t, wall: Date().addingTimeInterval(trace.t - ProcessInfo.processInfo.systemUptime), detail: trace.detail)
        }
    }
    nonisolated func recordMotion(_ motion: CMDeviceMotion) {
        let sample = LabMotion(motion)
        writer.queue.async { [writer] in writer.motion(sample) }
    }
    func recordConnection(_ connected: Bool) { record(event: connected ? "connected" : "disconnected") }
    func recordError(_ message: String) { record(event: "motion_error", detail: message) }
    func recordLatency(_ milliseconds: Double) {
        logger.info("Gesture reply latency: \(milliseconds, privacy: .public) ms")
        record(event: "action_latency", detail: String(format: "fire_to_reply=%.1f ms", milliseconds))
    }
    private func record(event: String, detail: String = "") {
        guard isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime, wall = Date()
        writer.queue.async { [writer] in writer.row(event: event, time: now, wall: wall, detail: detail) }
    }
    private func summarize() {
        guard isActive else { return }
        let token = generation, now = ProcessInfo.processInfo.systemUptime, dt = now - windowStart
        let terminal = self.terminal
        windowStart = now
        writer.queue.async { [writer, weak self] in
            let rate = Double(writer.samples) / max(0.001, dt)
            let status = now - writer.lastSample < 1.5 ? "Lab: \(Int(rate.rounded())) samples/sec" : "Lab: no motion samples"
            if terminal { print(String(format: "%.1f samples/sec | max ua_mag %.4f g | max rr_mag %.4f rad/s", rate, writer.maxUA, writer.maxRR)) }
            writer.samples = 0; writer.maxUA = 0; writer.maxRR = 0; writer.flush()
            let failure = writer.failure
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token, self.isActive else { return }
                self.status = failure.map { "Lab write failed: \($0)" } ?? status
                if failure != nil { self.isActive = false; self.timer?.invalidate(); self.timer = nil }
                self.onChange?()
            }
        }
    }
}
