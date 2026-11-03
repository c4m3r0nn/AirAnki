import AppKit

@MainActor
enum AnkiApp {
    static let bundleIdentifier = "net.ankiweb.dtop"
    static var isInstalled: Bool { applicationURL != nil }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty }
    private static var applicationURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }

    static func open() {
        if let applicationURL { NSWorkspace.shared.open(applicationURL) }
    }

    static func restart() async {
        guard !Task.isCancelled else { return }
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for application in applications {
            guard application.terminate() else { return }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while applications.contains(where: { !$0.isTerminated }) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return }
            do { try await Task.sleep(nanoseconds: 250_000_000) }
            catch { return }
        }
        if !Task.isCancelled { open() }
    }

    static var bundledAddonURL: URL? {
        let manager = FileManager.default
        func exists(_ url: URL) -> Bool {
            var directory: ObjCBool = false
            return manager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("AnkiAddon/airanki_bridge"), exists(bundled) {
            return bundled
        }
        guard var directory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() else { return nil }
        // SwiftPM and locally built app bundles live a few levels below the repo.
        for _ in 0..<6 {
            let addon = directory.appendingPathComponent("anki-addon/airanki_bridge")
            if exists(addon) { return addon }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
