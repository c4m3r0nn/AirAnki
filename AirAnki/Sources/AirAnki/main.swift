import AppKit

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
    print("""
    AirAnki — AirPods motion flicks for Anki
      --lab       Start the remote and record motion/gesture events; Return inserts a marker.
      --lab-only  Record motion/gesture events, with no AnkiConnect calls.
      --help      Print this help without starting the app.
    """)
} else if let index = arguments.firstIndex(of: "--render-assets"), index + 1 < arguments.count {
    exit(MainActor.assumeIsolated { AssetRenderer.run(arguments[index + 1]) })
} else if let index = arguments.firstIndex(of: "--ui-preview"), index + 1 < arguments.count {
    MainActor.assumeIsolated { UIPreview.run(arguments[index + 1], appearance: arguments.dropFirst(index + 2).first) }
} else if let unknown = arguments.first(where: { !["--lab", "--lab-only"].contains($0) && !$0.hasPrefix("-psn_") }) {
    fputs("Unknown argument: \(unknown). Use --help.\n", stderr)
    exit(2)
} else {
    MainActor.assumeIsolated {
        LegacySettings.migrate()
        let app = NSApplication.shared
        let delegate = AppDelegate(arguments: arguments)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Pre-release builds used the bundle id `local.airanki.AirAnki`; carry their settings and calibration over once.
enum LegacySettings {
    static func migrate(defaults: UserDefaults = .standard) {
        let key = "migratedLegacySettings"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        guard let old = UserDefaults.standard.persistentDomain(forName: "local.airanki.AirAnki") else { return }
        for (name, value) in old where defaults.object(forKey: name) == nil { defaults.set(value, forKey: name) }
    }
}
