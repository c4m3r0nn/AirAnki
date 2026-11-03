import AirAnkiCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var portText = ""
    @State private var portError: String?
    @State private var advanced = false

    var body: some View {
        Form {
            Section("Gestures") {
                Picker("Flick right on the answer", selection: Binding(get: { model.ease }, set: { model.owner?.setEase($0) })) {
                    Text("Easy").tag(4)
                    Text("Good").tag(3)
                }
                .pickerStyle(.segmented)
                Picker("Sensitivity", selection: Binding(get: { model.sensitivity }, set: { model.owner?.setSensitivity($0) })) {
                    Text("Low").tag(FlickSensitivity.low)
                    Text("Medium").tag(FlickSensitivity.medium)
                    Text("High").tag(FlickSensitivity.high)
                }
                .pickerStyle(.segmented)
                Toggle("Swap left and right", isOn: Binding(get: { model.reversed }, set: { model.owner?.setReversed($0) }))
                LabeledContent("Calibration") {
                    HStack {
                        Button("Recalibrate…") { model.owner?.calibrate() }
                        Button("Undo adaptation") { model.owner?.resetToCalibration() }
                            .disabled(!model.hasCalibration)
                            .help("AirAnki slowly adapts to how you flick. This returns to your original calibration.")
                    }
                }
            }
            Section {
                Toggle("Play a sound for each flick", isOn: Binding(get: { model.clickSound }, set: { model.owner?.setClickSound($0) }))
                Toggle("Keep AirPods awake", isOn: Binding(get: { model.keepAwake }, set: { model.owner?.setKeepAwake($0) }))
            } header: { Text("Feedback") } footer: {
                Text("Keeping AirPods awake plays inaudible silence so they don't disconnect while out of your ear. Anki shows a coloured pop for each action — turn it off in Anki → Tools → Add-ons → AirAnki Bridge → Config.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("General") {
                Toggle("Open AirAnki at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.owner?.setLaunchAtLogin($0) }))
                LabeledContent("Setup guide") {
                    Button("Show again") { model.owner?.showGuide() }
                }
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    LabeledContent("AnkiConnect port") {
                        TextField("8765", text: $portText)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                            .onSubmit(commitPort)
                    }
                    if let portError { Text(portError).font(.caption).foregroundStyle(Theme.again) }
                    Toggle("Use stem presses (experimental)", isOn: Binding(get: { model.stemInput }, set: { model.owner?.setStemInputEnabled($0) }))
                    Toggle("Lab mode — record motion for debugging", isOn: Binding(get: { model.labActive }, set: { _ in model.owner?.toggleLab() }))
                    if model.labActive { Text(model.labStatus).font(.caption).foregroundStyle(.secondary) }
                    LabeledContent("Lab recordings") { Button("Open folder") { model.owner?.openLabFolder() } }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnostics").font(.caption.weight(.semibold))
                        Text(model.diagnostics).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            Section {
                HStack {
                    Text("AirAnki \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    Spacer()
                    Text("Free and open source · Not affiliated with Apple or Anki").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 700)
        .onAppear { portText = String(model.port) }
    }

    private func commitPort() {
        portError = model.owner?.setPort(portText)
        if portError == nil { portText = String(model.port) }
    }
}
