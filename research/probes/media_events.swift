// Untested — needs user. Passive observer; never posts or suppresses events.
// Sources and interpretation limits: README.md (accessed 2026-10-30).
import AppKit
import ApplicationServices

guard CGPreflightListenEventAccess() || AXIsProcessTrusted() else {
    print("No existing input-observation permission. Exiting without requesting it.")
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let started = ProcessInfo.processInfo.systemUptime
let names: [Int: String] = [0: "volume-up", 1: "volume-down", 7: "mute",
                          16: "play-pause", 17: "next", 18: "previous",
                          19: "fast-forward", 20: "rewind"]
func logMedia(_ event: NSEvent) {
    guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return }
    let code = (event.data1 >> 16) & 0xffff
    guard let name = names[code] else { return }
    let flags = event.data1 & 0xffff
    let phase = (flags >> 8) & 0xff
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    print(String(format: "%.3f", elapsed), name, "phase=\(phase)",
          "repeat=\(flags & 1)", "data1=\(event.data1)")
    fflush(stdout)
}

guard let global = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined,
                                                    handler: logMedia) else {
    print("Could not install a global observer.")
    exit(3)
}
let local = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
    logMedia(event)
    return event
}
print("Observing media events for 90 seconds. No Now Playing claim or audio playback.")
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
    NSEvent.removeMonitor(global)
    if let local = local { NSEvent.removeMonitor(local) }
    print("Finished.")
    app.terminate(nil)
}
app.run()
