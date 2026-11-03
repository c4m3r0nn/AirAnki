import AirAnkiCore
import SwiftUI

/// First-run guide: welcome → AirPod → Anki → teach your flicks → try it.
struct GuideView: View {
    @ObservedObject var model: AppModel
    @State private var step: Step
    @State private var forward = true
    @State private var earDetectionOff = UserDefaults.standard.bool(forKey: "guideEarDetectionOff")

    enum Step: Int, CaseIterable { case welcome, airpod, anki, calibrate, tryIt }

    init(model: AppModel, step: Step = .welcome) {
        self.model = model
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.top, 34).padding(.bottom, 8)
            ZStack {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                        removal: .offset(x: forward ? -40 : 40).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            footer.padding(.horizontal, 28).padding(.vertical, 18)
        }
        .onChange(of: step) { _, value in
            if value == .calibrate, !model.hasCalibration, !model.calibrating { model.owner?.calibrate() }
            if value != .calibrate, model.calibrating, model.hasCalibration { model.owner?.cancelCalibration() }
            model.owner?.setPracticeMode(value == .tryIt)
            if value == .anki { model.owner?.refreshAddonState() }
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(.primary.opacity(0.12)))
                    .frame(width: s == step ? 28 : 14, height: 5)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome: WelcomePage(ease: model.ease)
        case .airpod: AirPodPage(model: model, earDetectionOff: $earDetectionOff)
        case .anki: AnkiPage(model: model)
        case .calibrate: CalibratePage(model: model)
        case .tryIt: TryItPage(model: model)
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(-1) }.buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
            } else if model.onboarded {
                Button("Close guide") { model.finishGuide() }.buttonStyle(QuietButtonStyle())
            }
            Spacer()
            if let skip = skipTitle {
                Button(skip) { go(1) }.buttonStyle(.plain).font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary).padding(.trailing, 10)
            }
            Button(primaryTitle) { step == .tryIt ? model.finishGuide() : go(1) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!primaryEnabled)
                .opacity(primaryEnabled ? 1 : 0.45)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .tryIt: return "Start studying"
        default: return "Continue"
        }
    }
    private var primaryEnabled: Bool {
        switch step {
        case .airpod: return airpodReady
        case .anki: if case .connected = model.anki { return true } else { return false }
        case .calibrate: return model.hasCalibration && !model.calibrating
        default: return true
        }
    }
    private var airpodReady: Bool {
        if case .receiving = model.airpods { return model.movementSeen && earDetectionOff }
        return false
    }
    private var skipTitle: String? {
        switch step {
        case .airpod: return airpodReady ? nil : "Skip for now"
        case .anki: return primaryEnabled ? nil : "Skip for now"
        case .calibrate: return model.hasCalibration && model.calibrating ? "Keep my old calibration" : nil
        default: return nil
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { step = next }
    }
}

// MARK: - Pages

private struct PageHeader: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(Theme.title(26)).multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
        }
    }
}

private struct WelcomePage: View {
    var ease: Int
    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            DemoView(ease: ease)
                .frame(width: 520, height: 230)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.primary.opacity(0.035)))
            PageHeader(title: "Review Anki with a flick",
                       subtitle: "AirAnki turns one AirPod into a wireless clicker. Hold it in your hand and flick your wrist — no keyboard, no extra gadget.")
            HStack(spacing: 8) {
                ForEach(DemoGesture.allCases) { g in GestureChip(gesture: g, style: g.style(ease: ease)) }
            }
            Text("Free · Works offline · Nothing leaves your Mac")
                .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }
}

struct GestureChip: View {
    var gesture: DemoGesture
    var style: ActionStyle
    var body: some View {
        HStack(spacing: 6) {
            Text(gesture.title).font(.system(size: 12, weight: .medium, design: .rounded))
            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Image(systemName: style.symbol).font(.system(size: 9, weight: .heavy))
                Text(style.title).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(style.color)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(style.color.opacity(0.1)))
    }
}

/// A checklist row: number or tick, title, explanation, optional trailing control.
struct StepRow<Trailing: View>: View {
    var number: Int
    var done: Bool
    var title: String
    var detail: String
    var warning = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Theme.good) : warning ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.primary.opacity(0.08)))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else if warning {
                    Image(systemName: "exclamationmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: done)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.heading(14))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 10)
    }
}

private struct AirPodPage: View {
    @ObservedObject var model: AppModel
    @Binding var earDetectionOff: Bool

    private var receiving: Bool { if case .receiving = model.airpods { return true } else { return false } }

    var body: some View {
        HStack(spacing: 36) {
            ListeningFigure(active: receiving, level: model.motionLevel, done: receiving && model.movementSeen)
                .frame(width: 180, height: 220)
            VStack(alignment: .leading, spacing: 4) {
                Text("Get your AirPod ready").font(Theme.title(24)).padding(.bottom, 10)
                if model.airpods == .denied {
                    StepRow(number: 0, done: false, title: "Allow motion access",
                            detail: "AirAnki needs Motion & Fitness permission to feel your flicks.", warning: true) {
                        Button("Open Settings") { SystemSettings.openMotionPrivacy() }.buttonStyle(QuietButtonStyle())
                    }
                    Divider()
                }
                StepRow(number: 1, done: receiving, title: "Connect your AirPods to this Mac",
                        detail: receiving ? "Hearing your \(budName)." : "Choose them in Control Center → Sound, like you would for music.") {
                    if !receiving { Button("Sound Settings") { SystemSettings.openSoundOutput() }.buttonStyle(QuietButtonStyle()) }
                }
                Divider()
                StepRow(number: 2, done: earDetectionOff, title: "Turn off Automatic Ear Detection",
                        detail: "System Settings → your AirPods. Otherwise your Mac stops listening as soon as the AirPod leaves your ear.") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button("Open Bluetooth") { SystemSettings.openBluetooth() }.buttonStyle(QuietButtonStyle())
                        Toggle("Done", isOn: $earDetectionOff).toggleStyle(.checkbox).font(.system(size: 12))
                            .onChange(of: earDetectionOff) { _, v in UserDefaults.standard.set(v, forKey: "guideEarDetectionOff") }
                    }
                }
                Divider()
                StepRow(number: 3, done: receiving && model.movementSeen, title: "Take one AirPod out and give it a wiggle",
                        detail: "Keep the other in its case. Hold it between thumb and finger, stem pointing down.") {
                    MotionMeter(level: model.motionLevel).frame(width: 72)
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private var budName: String {
        if case .receiving(let bud) = model.airpods, bud != "Unknown" { return "\(bud.lowercased()) AirPod" }
        return "AirPods"
    }
}

/// Big AirPod with a listening halo; ticks once real movement arrives.
struct ListeningFigure: View {
    var active: Bool
    var level: Double
    var done: Bool
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle().fill((done ? Theme.good : Theme.accent).opacity(0.08))
                .scaleEffect(breathe ? 1.05 : 0.92)
            Circle().strokeBorder((done ? Theme.good : Theme.accent).opacity(active ? 0.35 : 0.12), lineWidth: 2)
                .scaleEffect(1 + 0.25 * min(level, 1))
                .animation(.easeOut(duration: 0.15), value: level)
            PodFigure(tilt: 14 * sin(level * 3), size: 96, tint: .primary.opacity(active ? 0.9 : 0.35))
                .animation(.spring(response: 0.2, dampingFraction: 0.5), value: level)
            if done {
                Circle().fill(Theme.good).frame(width: 34, height: 34)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white))
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 3))
                    .offset(x: 58, y: 58)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: 170, height: 170)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: done)
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever()) { breathe = true } }
    }
}

struct MotionMeter: View {
    var level: Double
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<6) { i in
                let on = level * 6 > Double(i)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(on ? AnyShapeStyle(i < 4 ? Theme.good : Theme.accent) : AnyShapeStyle(.primary.opacity(0.1)))
                    .frame(width: 6, height: 6 + CGFloat(i) * 3)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityLabel("Motion level")
    }
}

private struct AnkiPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 36) {
            LinkFigure(connected: connected).frame(width: 180, height: 220)
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect to Anki").font(Theme.title(24)).padding(.bottom, 10)
                StepRow(number: 1, done: model.ankiInstalled, title: "Anki is on this Mac",
                        detail: model.ankiInstalled ? "Found Anki." : "AirAnki works with the free Anki desktop app.") {
                    if !model.ankiInstalled {
                        Link("Get Anki", destination: URL(string: "https://apps.ankiweb.net")!).buttonStyle(QuietButtonStyle())
                    }
                }
                Divider()
                StepRow(number: 2, done: addonReady, title: "Install the AirAnki add-on",
                        detail: model.addonMessage ?? addonDetail, warning: model.addonMessage != nil) {
                    if !addonReady {
                        Button(model.addonBusy ? "Installing…" : addonButton) { model.owner?.installAddon() }
                            .buttonStyle(QuietButtonStyle()).disabled(model.addonBusy || !model.ankiInstalled)
                    }
                }
                Divider()
                StepRow(number: 3, done: connected, title: connected ? "Connected to Anki" : model.ankiRunning ? "Restart Anki" : "Open Anki",
                        detail: connectionDetail) {
                    if !connected && model.ankiInstalled {
                        Button(model.ankiRunning ? "Restart Anki" : "Open Anki") { model.owner?.openOrRestartAnki() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private var connected: Bool { if case .connected = model.anki { return true } else { return false } }
    private var addonReady: Bool {
        switch model.addon {
        case .installed, .developmentLink: return true
        default: return false
        }
    }
    private var addonButton: String { if case .outdated = model.addon { return "Update" } else { return "Install" } }
    private var addonDetail: String {
        switch model.addon {
        case .installed(let v): return "Version \(v) installed."
        case .developmentLink: return "Developer copy linked."
        case .outdated: return "A newer version comes with this app."
        case .ankiNotFound: return "Open Anki once so it creates its add-ons folder, then install."
        default: return "A tiny add-on lets AirAnki answer cards instantly. It only talks to this app, on this Mac."
        }
    }
    private var connectionDetail: String {
        switch model.anki {
        case .connected(true, _): return "Connected — answers are instant."
        case .connected(false, _): return "Connected through AnkiConnect. Restart Anki to use the faster add-on."
        default: return model.ankiRunning ? "Anki loads add-ons when it starts." : "AirAnki connects as soon as Anki is open."
        }
    }
}

private struct LinkFigure: View {
    var connected: Bool
    @State private var flow = false
    var body: some View {
        VStack(spacing: 6) {
            PodFigure(size: 64, tint: .primary.opacity(0.85))
            ZStack {
                Capsule().fill(.primary.opacity(0.08)).frame(width: 4, height: 54)
                if connected {
                    Circle().fill(Theme.good).frame(width: 8, height: 8)
                        .offset(y: flow ? 24 : -24)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false), value: flow)
                }
            }
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 92, height: 64)
                .overlay(VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(.primary.opacity(0.55)).frame(width: 52, height: 6)
                    Capsule().fill(.primary.opacity(0.2)).frame(width: 64, height: 5)
                    Capsule().fill(.primary.opacity(0.2)).frame(width: 40, height: 5)
                })
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(connected ? Theme.good : .primary.opacity(0.1), lineWidth: connected ? 2 : 1))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .onAppear { flow = true }
    }
}

struct CalibratePage: View {
    @ObservedObject var model: AppModel

    private var current: DemoGesture {
        DemoGesture.allCases.first { $0.calibrationClass == model.calibration.step } ?? .right
    }
    private var finished: Bool { model.hasCalibration && !model.calibrating }

    var body: some View {
        HStack(spacing: 36) {
            ZStack {
                if finished {
                    VStack(spacing: 10) {
                        Circle().fill(Theme.good.gradient).frame(width: 84, height: 84)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 36, weight: .heavy)).foregroundStyle(.white))
                            .shadow(color: Theme.good.opacity(0.4), radius: 12, y: 5)
                        Text("Calibrated").font(Theme.heading(15))
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    VStack(spacing: 8) {
                        GestureLoop(gesture: current, style: current.style(ease: model.ease), size: 92, period: 1.8)
                            .id(current)
                            .transition(.opacity)
                        Text(current.title).font(Theme.title(20))
                        Text("× \(CentroidCalibrationSession.required)").font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 200, height: 240)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: finished)
            .animation(.easeInOut(duration: 0.3), value: current)

            VStack(alignment: .leading, spacing: 14) {
                Text(finished ? "AirAnki knows your flicks" : "Teach AirAnki your flicks").font(Theme.title(24))
                Text(finished
                     ? "Your gestures are saved. AirAnki keeps adapting gently as you study."
                     : "Do each gesture \(CentroidCalibrationSession.required) times, the way you would while studying — not extra hard. Pause briefly between them.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    ForEach(DemoGesture.allCases) { g in
                        CalibrationRow(gesture: g, style: g.style(ease: model.ease),
                                       count: model.calibration.counts[g.calibrationClass] ?? 0,
                                       active: model.calibrating && g == current,
                                       done: finished || (model.calibration.counts[g.calibrationClass] ?? 0) >= CentroidCalibrationSession.required)
                    }
                }
                .padding(.top, 4)
                Group {
                    if let notice = model.calibration.notice, model.calibrating {
                        Label(notice, systemImage: "hand.raised.fill").foregroundStyle(Theme.warning)
                    } else if case .receiving = model.airpods {
                        Label("Listening to your AirPod", systemImage: "waveform").foregroundStyle(.secondary)
                    } else {
                        Label("Waiting for your AirPod…", systemImage: "airpodpro.right").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .animation(.easeInOut, value: model.calibration.notice)
                if model.calibrating || finished {
                    Button(finished ? "Calibrate again" : "Start over") { model.owner?.calibrate() }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
        }
    }
}

private struct CalibrationRow: View {
    var gesture: DemoGesture
    var style: ActionStyle
    var count: Int
    var active: Bool
    var done: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(gesture.title).font(Theme.heading(13)).frame(width: 82, alignment: .leading)
                .foregroundStyle(active || done ? .primary : .secondary)
            HStack(spacing: 6) {
                ForEach(0..<CentroidCalibrationSession.required, id: \.self) { i in
                    let filled = done || i < count
                    Circle()
                        .fill(filled ? AnyShapeStyle(style.color.gradient) : AnyShapeStyle(.primary.opacity(active ? 0.12 : 0.06)))
                        .overlay(Circle().strokeBorder(active && i == count ? style.color : .clear, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .scaleEffect(filled ? 1 : 0.85)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: filled)
                }
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good).transition(.scale)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? style.color.opacity(0.08) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? style.color.opacity(0.3) : .primary.opacity(0.06)))
        .animation(.easeInOut(duration: 0.25), value: active)
    }
}

private struct TryItPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 26) {
            PageHeader(title: "Give it a go",
                       subtitle: "Try each gesture now — nothing is sent to Anki on this screen. Each one lights up when AirAnki recognises it.")
            HStack(spacing: 16) {
                ForEach(DemoGesture.allCases) { g in
                    PracticeTile(gesture: g, style: g.style(ease: model.ease), hit: model.practice.flatMap { hit(for: $0, gesture: g) })
                }
            }
            VStack(spacing: 6) {
                Label("On the question side, either flick shows the answer.", systemImage: "eye")
                Label("AirAnki lives in your menu bar. Close this window any time — it keeps working.", systemImage: "menubar.rectangle")
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func hit(for item: ActivityItem, gesture: DemoGesture) -> ActivityItem? {
        item.style == gesture.style(ease: model.ease) ? item : nil
    }
}

private struct PracticeTile: View {
    var gesture: DemoGesture
    var style: ActionStyle
    var hit: ActivityItem?
    @State private var popStart: Date?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                GestureLoop(gesture: gesture, style: style, size: 58, period: 2.4)
                if let popStart {
                    TimelineView(.animation) { ctx in
                        PopBadge(style: style, progress: ctx.date.timeIntervalSince(popStart) / 0.8, diameter: 56)
                    }
                }
            }
            .frame(height: 100)
            Text(gesture.title).font(Theme.heading(14))
            Text(style.title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(style.color)
        }
        .frame(width: 150, height: 180)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hit != nil ? style.color.opacity(0.10) : .primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(hit != nil ? style.color.opacity(0.5) : .clear, lineWidth: 1.5))
        .scaleEffect(popStart.map { Date().timeIntervalSince($0) < 0.3 } == true ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hit)
        .onChange(of: hit) { _, value in
            guard value != nil else { return }
            let start = Date()
            popStart = start
            // Stop the pop's timeline once it has faded.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if popStart == start { popStart = nil } }
        }
    }
}
