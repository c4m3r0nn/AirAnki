import AirAnkiCore
import Combine
import CoreMotion
import Foundation

struct CalibrationSnapshot: Equatable {
    var step: CentroidClass = .right
    var counts: [CentroidClass: Int] = [:]
    var notice: String?
    var complete = false
}

struct ActivityItem: Identifiable, Equatable {
    let id = UUID()
    let style: ActionStyle
    let date: Date
}

/// Everything the SwiftUI windows show, pushed from AppDelegate. Views call back through `owner`.
@MainActor
final class AppModel: ObservableObject {
    enum AirPods: Equatable { case off, waiting, denied, receiving(bud: String), lost }
    enum Anki: Equatable { case labOnly, connecting, unreachable(String), connected(instant: Bool, state: ReviewerState) }

    weak var owner: AppDelegate?

    @Published var onboarded = UserDefaults.standard.bool(forKey: "onboardingComplete")
    @Published var showingGuide = false
    @Published var remoteEnabled = false
    @Published var airpods = AirPods.off
    @Published var motionLevel = 0.0
    @Published var movementSeen = false
    @Published var anki = Anki.connecting
    @Published var addon: AddonInstallState?
    @Published var addonBusy = false
    @Published var addonMessage: String?
    @Published var ankiInstalled = true
    @Published var ankiRunning = false
    @Published var hasCalibration = false
    @Published var calibrating = false
    @Published var calibration = CalibrationSnapshot()
    @Published var recent: [ActivityItem] = []
    @Published var practice: ActivityItem?
    @Published var latencyMS: Double?
    @Published var diagnostics = ""

    // Settings mirrors.
    @Published var ease = 4
    @Published var sensitivity = FlickSensitivity.medium
    @Published var reversed = false
    @Published var clickSound = false
    @Published var keepAwake = true
    @Published var stemInput = false
    @Published var port = 8765
    @Published var labActive = false
    @Published var labStatus = ""
    @Published var launchAtLogin = false

    var needsGuide: Bool { !onboarded || showingGuide }

    func record(_ style: ActionStyle) {
        let item = ActivityItem(style: style, date: Date())
        recent.insert(item, at: 0)
        if recent.count > 12 { recent.removeLast(recent.count - 12) }
    }

    func finishGuide() {
        onboarded = true
        showingGuide = false
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        owner?.guideFinished()
    }

    func set<T: Equatable>(_ path: ReferenceWritableKeyPath<AppModel, T>, _ value: T) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }

    var headline: (text: String, detail: String, tone: Tone) {
        if !remoteEnabled { return ("Paused", "Flicks are ignored until you resume.", .idle) }
        switch airpods {
        case .denied: return ("Motion access needed", "Allow AirAnki in Privacy & Security → Motion & Fitness.", .problem)
        case .waiting, .off: return ("Waiting for your AirPod", "Connect your AirPods and take one out.", .attention)
        case .lost: return ("Lost your AirPod", "Make sure it's connected and Ear Detection is off.", .problem)
        case .receiving: break
        }
        switch anki {
        case .labOnly: return ("Lab mode", "Gestures are recorded, not sent to Anki.", .idle)
        case .connecting: return ("Connecting to Anki…", "", .attention)
        case .unreachable: return ("Open Anki", "AirAnki will connect as soon as Anki is running.", .attention)
        case .connected(_, .notReviewing): return ("Ready", "Open a deck in Anki and start studying.", .good)
        case .connected: return ("Reviewing", "Flick away — AirAnki is answering for you.", .good)
        }
    }

    enum Tone { case good, attention, problem, idle }
}
