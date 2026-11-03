import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    var guideStep = GuideView.Step.welcome

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            // A soft brand glow behind the title bar.
            RadialGradient(colors: [Theme.accent.opacity(0.12), .clear], center: .top, startRadius: 0, endRadius: 420)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            if model.needsGuide {
                GuideView(model: model, step: guideStep).transition(.opacity)
            } else {
                HomeView(model: model).transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 560)
        .animation(.easeInOut(duration: 0.35), value: model.needsGuide)
        .sheet(isPresented: Binding(get: { model.calibrating && !model.needsGuide },
                                    set: { if !$0 { model.owner?.cancelCalibration() } })) {
            CalibrationSheet(model: model)
        }
    }
}

@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    var onClose: (() -> Void)?

    init(model: AppModel, guideStep: GuideView.Step = .welcome) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "AirAnki"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView(model: model, guideStep: guideStep))
        window.setContentSize(NSSize(width: 760, height: 580))
        window.contentMinSize = NSSize(width: 720, height: 560)
        window.center()
        window.setFrameAutosaveName("AirAnkiMain")
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isVisible: Bool { window.isVisible }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    var onClose: (() -> Void)?

    init(model: AppModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "AirAnki Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isVisible: Bool { window.isVisible }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

/// Developer tool: `AirAnki --ui-preview <home|guide0…4|settings> [dark]` opens a screen with sample data.
@MainActor
enum UIPreview {
    static var keep: [AnyObject] = []
    static func run(_ screen: String, appearance: String?) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if appearance == "dark" { app.appearance = NSAppearance(named: .darkAqua) }
        if appearance == "light" { app.appearance = NSAppearance(named: .aqua) }
        let model = AppModel()
        model.remoteEnabled = true
        model.airpods = .receiving(bud: "Left")
        model.motionLevel = 0.55
        model.movementSeen = true
        model.anki = .connected(instant: true, state: .question)
        model.addon = .installed(version: "1.0.0")
        model.hasCalibration = screen != "guide3"
        model.calibrating = screen == "guide3"
        model.calibration = CalibrationSnapshot(step: .left, counts: [.right: 6, .left: 2], notice: nil)
        model.latencyMS = 18
        for style in [ActionStyle.easy, .reveal, .again, .reveal, .undo, .easy] { model.record(style) }
        model.diagnostics = "Motion: receiving ●\nLeft AirPod: receiving ● 25/s"
        if screen == "settings" {
            let window = SettingsWindow(model: model); keep.append(window)
            DispatchQueue.main.async { window.show() }
        } else {
            model.onboarded = screen == "home"
            let step = GuideView.Step(rawValue: Int(screen.dropFirst(5)) ?? 0) ?? .welcome
            let window = MainWindow(model: model, guideStep: step); keep.append(window); window.show()
        }
        keep.append(model)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
