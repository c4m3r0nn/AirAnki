import Foundation

/// The requested 18 columns, followed by metadata for raw commands and markers.
public enum LabCSV {
    public static let header = "t_monotonic,wall_iso,event,sensor_location,ua_x,ua_y,ua_z,ua_mag,rr_x,rr_y,rr_z,rr_mag,grav_x,grav_y,grav_z,att_pitch,att_roll,att_yaw,raw_command,marker_id,detail\n"

    public static func row(monotonic: TimeInterval, wallISO: String, event: String,
                           location: String = "", values: [Double] = [],
                           rawCommand: String = "", marker: Int? = nil, detail: String = "") -> String {
        let numbers = (0..<14).map { index in
            index < values.count ? String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), values[index]) : ""
        }
        let fields = [String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), monotonic), wallISO, event, location]
            + numbers + [rawCommand, marker.map(String.init) ?? "", detail]
        return fields.map(escape).joined(separator: ",") + "\n"
    }

    private static func escape(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }
}
