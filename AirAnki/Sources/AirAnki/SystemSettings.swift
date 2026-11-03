import AppKit

enum SystemSettings {
    static func openBluetooth() { open("com.apple.BluetoothSettings") }
    static func openMotionPrivacy() { open("com.apple.preference.security?Privacy_Motion") }
    static func openSoundOutput() { open("com.apple.Sound-Settings.extension") }

    private static func open(_ pane: String) {
        let workspace = NSWorkspace.shared
        if let url = URL(string: "x-apple.systempreferences:\(pane)"), workspace.open(url) { return }
        if let app = workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            workspace.open(app)
        }
    }
}
