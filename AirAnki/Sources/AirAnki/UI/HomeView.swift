import AirAnkiCore
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var showingDemo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let banner { banner }
            HStack(spacing: 14) {
                airpodPanel
                ankiPanel
            }
            gestures
            activity
            Spacer(minLength: 0)
            toolbar
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 20)
        .sheet(isPresented: $showingDemo) { DemoSheet(ease: model.ease) }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.headline.text)
    }

    // MARK: Header

    private var header: some View {
        let h = model.headline
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(toneColor(h.tone).opacity(0.14)).frame(width: 48, height: 48)
                Image(systemName: model.remoteEnabled ? "airpodpro.right" : "pause.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(toneColor(h.tone))
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(h.text).font(Theme.title(24)).contentTransition(.opacity)
                if !h.detail.isEmpty {
                    Text(h.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(isOn: Binding(get: { model.remoteEnabled }, set: { _ in model.owner?.toggleRemote() })) {
                Text(model.remoteEnabled ? "On" : "Paused").font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.large)
            .help(model.remoteEnabled ? "Pause AirAnki" : "Resume AirAnki")
        }
    }

    private func toneColor(_ tone: AppModel.Tone) -> Color {
        switch tone {
        case .good: return Theme.good
        case .attention: return Theme.accent
        case .problem: return Theme.again
        case .idle: return Theme.undo
        }
    }

    // MARK: Problem banner

    private var banner: Banner? {
        guard model.remoteEnabled else { return nil }
        switch model.addon {
        case .outdated?:
            return Banner(icon: "arrow.down.circle.fill", tint: Theme.accent, text: "A newer AirAnki add-on is ready for Anki.",
                          action: "Update") { model.owner?.installAddon() }
        default: break
        }
        if model.airpods == .denied {
            return Banner(icon: "lock.fill", tint: Theme.again, text: "AirAnki doesn't have Motion & Fitness access.",
                          action: "Open Settings") { SystemSettings.openMotionPrivacy() }
        }
        if model.airpods == .lost {
            return Banner(icon: "airpodpro.right", tint: Theme.warning,
                          text: "Can't hear your AirPod. Check it's connected and Automatic Ear Detection is off.",
                          action: "Bluetooth") { SystemSettings.openBluetooth() }
        }
        if case .unreachable = model.anki, model.ankiInstalled {
            return Banner(icon: "rectangle.on.rectangle.angled", tint: Theme.accent, text: "Anki isn't open.",
                          action: "Open Anki") { model.owner?.openOrRestartAnki() }
        }
        return nil
    }

    // MARK: Status panels

    private var airpodPanel: some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: "airpodpro.right").font(.system(size: 22)).frame(width: 30)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AirPod").font(Theme.heading(13)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        StatusDot(color: airpodColor, pulsing: isReceiving)
                        Text(airpodText).font(.system(size: 14, weight: .medium))
                    }
                }
                Spacer()
                MotionMeter(level: model.motionLevel)
            }
        }
    }
    private var isReceiving: Bool { if case .receiving = model.airpods { return true } else { return false } }
    private var airpodColor: Color {
        switch model.airpods {
        case .receiving: return Theme.good
        case .lost, .denied: return Theme.again
        default: return Theme.undo
        }
    }
    private var airpodText: String {
        switch model.airpods {
        case .off: return "Not listening"
        case .waiting: return "Waiting…"
        case .denied: return "No permission"
        case .lost: return "Signal lost"
        case .receiving(let bud): return bud == "Unknown" ? "Connected" : "\(bud) AirPod"
        }
    }

    private var ankiPanel: some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 20)).frame(width: 30)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Anki").font(Theme.heading(13)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        StatusDot(color: ankiColor)
                        Text(ankiText).font(.system(size: 14, weight: .medium))
                    }
                }
                Spacer()
                if case .connected(let instant, _) = model.anki {
                    Text(instant ? "Instant" : "AnkiConnect")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill((instant ? Theme.good : Theme.warning).opacity(0.14)))
                        .foregroundStyle(instant ? Theme.good : Theme.warning)
                        .help(instant ? "Connected through the AirAnki add-on" : "Connected through AnkiConnect — install the AirAnki add-on for faster answers")
                }
            }
        }
    }
    private var ankiColor: Color {
        switch model.anki {
        case .connected: return Theme.good
        case .unreachable: return Theme.undo
        default: return Theme.accent
        }
    }
    private var ankiText: String {
        switch model.anki {
        case .labOnly: return "Lab mode"
        case .connecting: return "Connecting…"
        case .unreachable: return "Not open"
        case .connected(_, .question): return "Question side"
        case .connected(_, .answer): return "Answer side"
        case .connected(_, .reviewing): return "Reviewing"
        case .connected(_, .notReviewing): return "Connected"
        }
    }

    // MARK: Gestures

    private var gestures: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gestures").font(Theme.heading(13)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(DemoGesture.allCases) { g in
                    let style = g.style(ease: model.ease)
                    VStack(spacing: 4) {
                        GestureLoop(gesture: g, style: style, size: 54, period: 2.6)
                            .frame(height: 84)
                        Text(g.title).font(Theme.heading(14))
                        HStack(spacing: 4) {
                            Image(systemName: style.symbol).font(.system(size: 9, weight: .heavy))
                            Text(style.title).font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(style.color)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(style.color.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(style.color.opacity(0.12)))
                }
            }
            Label("On the question side, either flick shows the answer.", systemImage: "eye")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(Theme.heading(13)).foregroundStyle(.secondary)
                Spacer()
                if let ms = model.latencyMS {
                    Text("\(Int(ms.rounded())) ms to Anki").font(.system(size: 11, design: .rounded)).foregroundStyle(.tertiary)
                        .help("Time from recognising a flick to Anki confirming it")
                }
            }
            if model.recent.isEmpty {
                Text("Your flicks will show up here.").font(.system(size: 13)).foregroundStyle(.tertiary)
                    .frame(height: 34)
            } else {
                HStack(spacing: 8) {
                    ForEach(model.recent.prefix(8)) { item in
                        HStack(spacing: 5) {
                            Image(systemName: item.style.symbol).font(.system(size: 10, weight: .heavy))
                            Text(item.style.title).font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(item.style.color.gradient))
                        .opacity(item.id == model.recent.first?.id ? 1 : 0.55)
                        .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(height: 34)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: model.recent)
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.owner?.calibrate() } label: { Label("Recalibrate", systemImage: "scope") }
            Button { showingDemo = true } label: { Label("Watch demo", systemImage: "play.circle") }
            Button { model.showingGuide = true } label: { Label("Setup guide", systemImage: "list.bullet.rectangle") }
            Spacer()
            Button { model.owner?.showSettings() } label: { Label("Settings", systemImage: "gearshape") }
                .keyboardShortcut(",", modifiers: .command)
        }
        .buttonStyle(QuietButtonStyle())
        .labelStyle(.titleAndIcon)
    }
}

struct Banner: View {
    var icon: String
    var tint: Color
    var text: String
    var action: String
    var perform: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action, action: perform).buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Calibration in progress, shown over the home screen.
struct CalibrationSheet: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            CalibratePage(model: model).padding(36)
            HStack {
                if model.calibrating {
                    Button("Cancel") { model.owner?.cancelCalibration() }.buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button("Done") { model.owner?.cancelCalibration() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.calibrating).opacity(model.calibrating ? 0.45 : 1)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .frame(width: 700, height: 440)
    }
}

struct DemoSheet: View {
    var ease: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            Text("How AirAnki works").font(Theme.title(22)).padding(.top, 24)
            DemoView(ease: ease).frame(width: 520, height: 230)
            HStack(spacing: 8) {
                ForEach(DemoGesture.allCases) { g in GestureChip(gesture: g, style: g.style(ease: ease)) }
            }
            Button("Close") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .padding(.bottom, 22)
        }
        .frame(width: 600)
    }
}
