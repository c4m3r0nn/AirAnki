import Foundation

public enum AnkiConnectionSettings {
    public static let defaultPort = 8765
    public static let portKey = "ankiConnectPort"

    public static func isValidPort(_ port: Int) -> Bool { (1...65535).contains(port) }

    public static func port(in defaults: UserDefaults) -> Int {
        let port = defaults.integer(forKey: portKey)
        return isValidPort(port) ? port : defaultPort
    }

    public static func parsePort(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(trimmed), isValidPort(port) else { return nil }
        return port
    }
}
