import Foundation

/// CSV reader shared by the command-line replay and the recording regression test.
/// Handles quoted commas/newlines/quotes, and locates columns by header name.
public enum LabReplay {
    public struct Row {
        public let t: TimeInterval
        public let marker: Int?
        public let motion: MotionSample?
    }
    public struct Event {
        public let detection: FlickDetection
        public let segment: Int
    }
    public struct Result {
        public let events: [Event]
        public let segments: [Int]
        public let motionCount: Int
    }

    public static func read(_ text: String) throws -> [Row] {
        let records = try parseCSV(text)
        guard let header = records.first else { throw AnkiError.message("Empty CSV.") }
        let names = ["t_monotonic", "event", "marker_id", "rr_x", "rr_y", "rr_z", "grav_x", "grav_y", "grav_z"]
        var columns: [String: Int] = [:]
        for name in names {
            guard let index = header.firstIndex(of: name) else { throw AnkiError.message("Missing CSV column: \(name)") }
            columns[name] = index
        }
        var rows: [Row] = []
        for (offset, fields) in records.dropFirst().enumerated() {
            if fields.allSatisfy({ $0.isEmpty }) { continue }
            func field(_ name: String) -> String { fields.indices.contains(columns[name]!) ? fields[columns[name]!] : "" }
            let event = field("event")
            guard event == "motion" || event == "marker" else { continue }
            func number(_ name: String) throws -> Double {
                guard let value = Double(field(name)), value.isFinite else {
                    throw AnkiError.message("Invalid \(name) in CSV record \(offset + 2).")
                }
                return value
            }
            let t = try number("t_monotonic")
            if event == "marker" {
                guard let marker = Int(field("marker_id")), marker >= 0 else {
                    throw AnkiError.message("Invalid marker in CSV record \(offset + 2).")
                }
                rows.append(Row(t: t, marker: marker, motion: nil))
            } else {
                let sample = try MotionSample(t: t, rotationRate: (number("rr_x"), number("rr_y"), number("rr_z")),
                                              gravity: (number("grav_x"), number("grav_y"), number("grav_z")))
                rows.append(Row(t: t, marker: nil, motion: sample))
            }
        }
        // Lab markers use receipt time; queued motion uses the sensor timestamp.
        // Stable chronological ordering associates events with the marker at delivery.
        return rows.enumerated().sorted { a, b in
            a.element.t == b.element.t ? a.offset < b.offset : a.element.t < b.element.t
        }.map(\.element)
    }

    public static func run(_ rows: [Row], detector: FlickDetector) -> Result {
        run(rows, process: detector.process)
    }

    public static func run(_ rows: [Row], detector: LegacyFlickDetector) -> Result {
        run(rows, process: detector.process)
    }

    private static func run(_ rows: [Row], process: (MotionSample) -> [FlickDetection]) -> Result {
        var segment = 0, segments = [0], events: [Event] = [], motionCount = 0
        for row in rows {
            if let marker = row.marker {
                segment = marker
                if !segments.contains(marker) { segments.append(marker) }
            }
            if let sample = row.motion {
                motionCount += 1
                events += process(sample).map { Event(detection: $0, segment: segment) }
            }
        }
        // No invented samples at EOF: an unfinished hold requires real later data.
        return Result(events: events, segments: segments, motionCount: motionCount)
    }

    private static func parseCSV(_ text: String) throws -> [[String]] {
        var records: [[String]] = [], fields: [String] = [], field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var next = iterator.next()
        while let c = next {
            next = iterator.next()
            if c == "\"" {
                if quoted, next == "\"" { field.append("\""); next = iterator.next() }
                else { quoted.toggle() }
            } else if c == ",", !quoted {
                fields.append(field); field = ""
            } else if (c == "\n" || c == "\r\n" || c == "\r"), !quoted {
                fields.append(field); records.append(fields); fields = []; field = ""
            } else { field.append(c) }
        }
        guard !quoted else { throw AnkiError.message("Unterminated quoted CSV field.") }
        if !field.isEmpty || !fields.isEmpty { fields.append(field); records.append(fields) }
        return records
    }
}
