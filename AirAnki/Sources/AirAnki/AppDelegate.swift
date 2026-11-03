import AirAnkiCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let labOnly: Bool
    let stem = StemInput()
    let flick = FlickInput()
    private(set) var remoteEnabled = false
    private(set) var stemInputEnabled: Bool
    private(set) var sensitivity: FlickSensitivity
    private(set) var reversed: Bool
    private(set) var lastGesture = "None yet"
    private(set) var calibration: CentroidCalibration?
    private(set) var calibrationStatus = "Calibration needed"
    private(set) var calibrating = false
    private(set) var keepAwakeEnabled: Bool
    private let keepAwake = KeepAwakeAudio()
    private let tryAgainSound = NSSound(named: "Funk")
    private var adaptationPersistence = AdaptationPersistence(at: ProcessInfo.processInfo.systemUptime)
    private let feedbackSound = NSSound(named: "Tink")
    private var uiUpdateScheduled = false
    private var gestureSequence = 0
    let lab: MotionLab
    private(set) var client: AutoDetectAnkiClient?
    private(set) var controller: ReviewController?
    private(set) var mapping: Mapping
    private(set) var ease: Int
    private(set) var clickSound: Bool
    private(set) var port: Int
    private(set) var lastPress = LastPressStatus()
    private var menu: MenuBar?
    let model = AppModel()
    private var mainWindow: MainWindow?
    private var settingsWindow: SettingsWindow?
    private var practiceMode = false
    private var statusTimer: Timer?
    private let defaults = UserDefaults.standard
    private let startLab: Bool
    private var inputError: String?
    private var signals: [DispatchSourceSignal] = []

    var remoteStatus: String {
        "\(airPodsStatus) · \(connectionStatus)"
    }

    var airPodsStatus: String {
        let state = remoteEnabled ? "Listening" : "Paused"
        return inputError.map { "\(state) — \($0)" } ?? state
    }

    var connectionStatus: String {
        if labOnly { return "Lab only — no Anki calls" }
        guard let controller else { return "Connecting…" }
        switch controller.status {
        case .connecting: return "Connecting on port \(port)…"
        case .error(let message): return message
        case .ready(let state):
            let review: String
            switch state {
            case .notReviewing: review = "Not reviewing"
            case .reviewing: review = "Reviewing"
            case .question: review = "Reviewing (question)"
            case .answer: review = "Reviewing (answer)"
            }
            return "Connected (\(controller.link.rawValue)) — \(review)"
        }
    }

    var gestureTable: String {
        "Question side / Answer side\nRight flick: Show answer / \(ease == 3 ? "Good (3)" : "Easy (4)")\nLeft flick: Show answer / Again (1)\nUndo gesture: Undo on either side\nUnclear flick: Show answer / Try again"
    }

    init(arguments: [String]) {
        labOnly = arguments.contains("--lab-only")
        startLab = labOnly || arguments.contains("--lab")
        lab = MotionLab(terminal: startLab)
        mapping = Mapping(defaults: .standard)
        ease = Mapping.validatedEase(UserDefaults.standard.integer(forKey: "easeForRight"))
        stemInputEnabled = UserDefaults.standard.bool(forKey: "stemInputEnabled")
        sensitivity = UserDefaults.standard.string(forKey: "sensitivity").flatMap(FlickSensitivity.init) ?? .medium
        reversed = UserDefaults.standard.bool(forKey: "reverseLeftRight")
        clickSound = UserDefaults.standard.bool(forKey: "clickSound")
        port = AnkiConnectionSettings.port(in: .standard)
        calibration = CentroidCalibration.load(from: .standard)
        keepAwakeEnabled = UserDefaults.standard.object(forKey: "keepAirPodsAwake") as? Bool ?? true
        super.init()
        model.owner = self
        stem.ignoreExplicitPlayPause = StemCommand.ignoreExplicitPlayPause(in: defaults)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()
        menu = MenuBar(owner: self)
        lab.onChange = { [weak self] in self?.syncMotionCapture(); self?.updateUI() }
        flick.onMotion = { [lab] in lab.recordMotion($0) }
        flick.onTrace = { [lab] in lab.recordDecision($0) }
        flick.onCalibration = { [weak self] snapshot, calibration in
            guard let self else { return }
            self.feedbackSound?.stop(); self.feedbackSound?.play()
            self.model.calibration = snapshot
            self.calibrationStatus = calibration.map { "Flicks calibrated — \($0.quality)" } ?? snapshot.notice ?? "Calibrating"
            if let calibration {
                self.calibration = calibration; calibration.save(to: self.defaults)
                self.adaptationPersistence = AdaptationPersistence(at: ProcessInfo.processInfo.systemUptime)
                self.calibrating = false; self.configureFlicks()
                self.syncMotionCapture()
            }
            self.updateUI()
        }
        flick.onAdaptation = { [weak self] value in
            guard let self, !self.calibrating else { return }
            self.calibration = value
            if self.adaptationPersistence.shouldSave(at: ProcessInfo.processInfo.systemUptime) { value.save(to: self.defaults) }
        }
        keepAwake.onError = { [weak self] in self?.showInputError($0) }
        flick.onMotionLost = { [weak self] in
            guard let self, self.remoteEnabled else { return }
            self.tryAgainSound?.stop(); self.tryAgainSound?.play()
        }
        configureFlicks()
        flick.onConnection = { [weak self] in self?.lab.recordConnection($0) }
        flick.onError = { [weak self] in self?.lab.recordError($0) }
        flick.onChange = { [weak self] in self?.updateUI() }
        flick.onEvent = { [weak self] in self?.receive($0) }
        stem.onCommand = { [weak self] event in self?.receive(event) }
        stem.onError = { [weak self] message in self?.showInputError(message) }
        if !labOnly {
            configureConnection()
            reconnect()
        }
        toggleRemote()
        if startLab {
            toggleLab()
            // A blocking read stays off the UI thread. EOF ends only the reader.
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while readLine() != nil {
                    DispatchQueue.main.async { self?.lab.insertMarker() }
                }
            }
        }
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            signals.append(source)
        }
        showWindow()
        if let calibration { calibrationStatus = "Flicks calibrated — \(calibration.quality)" }
        else if model.onboarded { calibrate() }
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "AirAnki")
        applicationMenu.addItem(withTitle: "About AirAnki", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        applicationMenu.addItem(withTitle: "Setup Guide", action: #selector(menuGuide), keyEquivalent: "").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide AirAnki", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        applicationMenu.addItem(withTitle: "Quit AirAnki", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"),
                                     ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"),
                                     ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func menuSettings() { showSettings() }
    @objc private func menuGuide() { showGuide() }

    private func configureConnection() {
        guard !labOnly else { return }
        let client = AutoDetectAnkiClient(transport: URLSessionAnkiTransport(
            port: port, apiKey: defaults.string(forKey: "ankiConnectAPIKey")))
        self.client = client
        let controller = ReviewController(client: client, bridge: BridgeClient())
        self.controller = controller
        controller.mapping = mapping
        controller.easeForSingle = Mapping.validatedEase(defaults.integer(forKey: "easeForSingle"))
        controller.onStatus = { [weak self] _ in self?.updateUI() }
        controller.onBusyChange = { [weak self] in self?.updateUI() }
        controller.onFeedback = { [weak self] feedback in
            self?.menu?.flash(feedback)
            if let style = ActionStyle(feedback) { self?.model.record(style) }
            if feedback == .unclear { self?.tryAgainSound?.stop(); self?.tryAgainSound?.play() }
        }
        controller.onLatency = { [weak self] ms in self?.lab.recordLatency(ms); self?.updateUI() }
        updateUI()
    }

    private func receive(_ event: StemEvent) {
        lab.recordStem(event)
        lastPress.record(event)
        updateUI()
        guard let gesture = event.gesture, !calibrating else { return }
        if clickSound { feedbackSound?.stop(); feedbackSound?.play() }
        guard !labOnly, let controller else {
            lastPress.complete(event, outcome: "Recorded only (Lab only)")
            updateUI()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.stem.isActive, self.controller === controller else {
                self.lastPress.complete(event, outcome: "Ignored (remote paused or port changed)")
                self.updateUI()
                return
            }
            let outcome = await controller.handleWithOutcome(gesture, at: event.time)
            self.lastPress.complete(event, outcome: outcome.title)
            self.updateUI()
        }
    }

    private func receive(_ event: FlickDetection) {
        guard !calibrating else { return }
        // The setup guide never sends gestures to Anki; its last page lights up practice tiles instead.
        if model.needsGuide {
            guard practiceMode else { return }
            let style: ActionStyle
            switch event.event {
            case .right: style = ease == 3 ? .good : .easy
            case .left: style = .again
            case .undo, .shake: style = .undo
            case .ambiguous: style = .unclear
            }
            if clickSound { feedbackSound?.stop(); feedbackSound?.play() }
            model.practice = ActivityItem(style: style, date: Date())
            return
        }
        if remoteEnabled, clickSound, event.event != .ambiguous { feedbackSound?.stop(); feedbackSound?.play() }
        gestureSequence += 1
        let sequence = gestureSequence
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let wall = Date().addingTimeInterval(event.t - ProcessInfo.processInfo.systemUptime)
        let prefix = "\(event.event.rawValue.capitalized) at \(formatter.string(from: wall))"
        let action = event.event.action(easeForRight: ease)
        lastGesture = "\(prefix) — \(action.title) (pending)"
        updateUI()
        guard remoteEnabled else { lastGesture = "\(prefix) — Ignored (remote paused)"; updateUI(); return }
        guard !labOnly, let controller else {
            lastGesture = "\(prefix) — Recorded only (Lab only)"; updateUI(); return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.remoteEnabled, self.controller === controller else {
                if self.gestureSequence == sequence {
                    self.lastGesture = "\(prefix) — Ignored (remote paused or port changed)"
                    self.updateUI()
                }
                return
            }
            let outcome = await controller.handleFlick(event, easeForRight: self.ease)
            if self.gestureSequence == sequence { self.lastGesture = "\(prefix) — \(outcome.title)" }
            self.updateUI()
        }
    }

    func showWindow() {
        if mainWindow == nil {
            let window = MainWindow(model: model)
            window.onClose = { [weak self] in self?.windowClosed() }
            mainWindow = window
        }
        mainWindow?.show()
        if !labOnly, statusTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollConnection() }
            }
            RunLoop.main.add(timer, forMode: .common)
            statusTimer = timer
            pollConnection()
        }
        refreshAddonState()
        updateUI()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = SettingsWindow(model: model)
            window.onClose = { [weak self] in self?.windowClosed() }
            settingsWindow = window
        }
        model.launchAtLogin = LoginItem.isEnabled
        settingsWindow?.show()
    }

    func showGuide() {
        model.showingGuide = true
        showWindow()
    }

    func windowClosed() {
        // Run on the next turn: the closing window still reports itself visible here.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mainWindow?.isVisible != true, self.settingsWindow?.isVisible != true else { return }
            self.statusTimer?.invalidate()
            self.statusTimer = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func pollConnection() {
        guard !labOnly, let controller, !controller.isBusy else { return }
        // Only reads; use discovery again after a failure or restart.
        let redetect: Bool
        if case .error = controller.status { redetect = true } else { redetect = false }
        Task { @MainActor [weak self] in
            guard self?.controller === controller else { return }
            await controller.refresh(redetect: redetect)
        }
    }

    private func updateUI() {
        guard !uiUpdateScheduled else { return }
        uiUpdateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.uiUpdateScheduled = false
            self.menu?.update(); self.syncModel()
        }
    }

    private func configureFlicks() {
        flick.configure(calibration: calibration, sensitivity: sensitivity, reversed: reversed)
    }

    func calibrate() {
        calibrating = true
        calibrationStatus = "Calibrating"
        model.calibration = CalibrationSnapshot()
        flick.calibrate(); syncMotionCapture(); showWindow(); updateUI()
    }

    /// Leaves calibration, keeping the previous calibration if there was one.
    func cancelCalibration() {
        guard calibrating else { return }
        calibrating = false
        flick.cancelCalibration()
        configureFlicks(); syncMotionCapture(); updateUI()
    }

    func setPracticeMode(_ value: Bool) { practiceMode = value; model.practice = nil }

    func guideFinished() {
        practiceMode = false
        if calibration == nil { calibrate() }
        updateUI()
    }

    // MARK: Anki add-on and app

    private var addonInstaller: AddonInstaller? {
        AnkiApp.bundledAddonURL.map { AddonInstaller(bundledAddon: $0) }
    }

    func refreshAddonState() {
        model.ankiInstalled = AnkiApp.isInstalled
        model.ankiRunning = AnkiApp.isRunning
        model.addon = addonInstaller?.state()
    }

    func installAddon() {
        guard let installer = addonInstaller else {
            model.addonMessage = "This copy of AirAnki doesn't include the add-on."; return
        }
        model.addonBusy = true
        do {
            try installer.install()
            model.addonMessage = nil
        } catch {
            model.addonMessage = error.localizedDescription
        }
        model.addonBusy = false
        refreshAddonState()
    }

    func openOrRestartAnki() {
        if AnkiApp.isRunning {
            Task { @MainActor [weak self] in
                await AnkiApp.restart()
                self?.refreshAddonState(); self?.reconnect()
            }
        } else {
            AnkiApp.open()
        }
        model.ankiRunning = true
    }

    func setLaunchAtLogin(_ value: Bool) {
        do { try LoginItem.setEnabled(value) } catch { showInputError(error.localizedDescription) }
        model.launchAtLogin = LoginItem.isEnabled
    }

    private func syncModel() {
        let m = model
        m.set(\.remoteEnabled, remoteEnabled)
        let airpods: AppModel.AirPods
        if !flick.isRunning { airpods = .off }
        else if flick.permissionDenied { airpods = .denied }
        else if flick.streamHealth.isLost { airpods = .lost }
        else if flick.isReceiving, let bud = flick.activeBud { airpods = .receiving(bud: bud) }
        else { airpods = .waiting }
        m.set(\.airpods, airpods)
        m.set(\.motionLevel, flick.activeBud == nil ? 0 : flick.motionLevel)
        if case .receiving = airpods, flick.motionLevel > 0.3, !m.movementSeen { m.movementSeen = true }
        let anki: AppModel.Anki
        if labOnly { anki = .labOnly }
        else if let controller {
            switch controller.status {
            case .connecting: anki = .connecting
            case .error(let message): anki = .unreachable(message)
            case .ready(let state): anki = .connected(instant: controller.link == .bridge, state: state)
            }
        } else { anki = .connecting }
        m.set(\.anki, anki)
        if case .connected = anki, !m.ankiRunning { m.ankiRunning = true }
        m.set(\.hasCalibration, calibration != nil)
        m.set(\.calibrating, calibrating)
        m.set(\.latencyMS, controller?.lastLatencyMS)
        m.set(\.ease, ease)
        m.set(\.sensitivity, sensitivity)
        m.set(\.reversed, reversed)
        m.set(\.clickSound, clickSound)
        m.set(\.keepAwake, keepAwakeEnabled)
        m.set(\.stemInput, stemInputEnabled)
        m.set(\.port, port)
        m.set(\.labActive, lab.isActive)
        m.set(\.labStatus, lab.status)
        m.set(\.diagnostics, [
            "Motion: \(flick.status)", flick.budStatus,
            "Anki: \(connectionStatus)" + (controller?.bridgeVersion.map { " — add-on \($0)" } ?? ""), calibrationStatus,
            "Last gesture: \(lastGesture)",
        ].joined(separator: "\n"))
    }

    func resetToCalibration() {
        calibration?.resetAdaptation()
        calibration?.save(to: defaults)
        adaptationPersistence = AdaptationPersistence(at: ProcessInfo.processInfo.systemUptime)
        configureFlicks(); updateUI()
    }

    func setKeepAwake(_ value: Bool) {
        keepAwakeEnabled = value; defaults.set(value, forKey: "keepAirPodsAwake")
        syncMotionCapture(); updateUI()
    }

    func toggleRemote() {
        inputError = nil
        remoteEnabled.toggle()
        if remoteEnabled, flick.streamHealth.isLost { tryAgainSound?.stop(); tryAgainSound?.play() }
        flick.resetGestures()
        syncMotionCapture()
        syncStemCapture()
        updateUI()
    }

    private func syncMotionCapture() {
        keepAwake.setActive(keepAwakeEnabled && (remoteEnabled || lab.isActive || calibrating))
        flick.setLabEnabled(lab.isActive)
        if remoteEnabled || lab.isActive || calibrating { flick.start() } else { flick.stop() }
    }

    private func syncStemCapture() {
        if remoteEnabled && stemInputEnabled {
            do { try stem.start() }
            catch { showInputError("Could not start silent audio: \(error.localizedDescription)") }
        } else { stem.stop() }
    }

    func setStemInputEnabled(_ enabled: Bool) {
        stemInputEnabled = enabled
        defaults.set(enabled, forKey: "stemInputEnabled")
        syncStemCapture()
        updateUI()
    }

    func setSensitivity(_ value: FlickSensitivity) {
        sensitivity = value
        defaults.set(value.rawValue, forKey: "sensitivity")
        configureFlicks()
        updateUI()
    }

    func setReversed(_ value: Bool) {
        reversed = value
        defaults.set(value, forKey: "reverseLeftRight")
        configureFlicks()
        updateUI()
    }

    func toggleLab() {
        if lab.isActive { lab.stop() }
        else {
            do { try lab.start() }
            catch { showInputError("Could not start Lab: \(error.localizedDescription)") }
        }
        updateUI()
    }

    func reconnect() {
        guard !labOnly else { return }
        Task { @MainActor [weak self] in
            await self?.controller?.refresh()
            self?.updateUI()
        }
    }

    func setEase(_ value: Int) {
        ease = Mapping.validatedEase(value)
        defaults.set(ease, forKey: "easeForRight")
        updateUI()
    }

    func setMapping(_ gesture: Gesture, action: RemoteAction) {
        mapping[gesture] = action
        mapping.save(to: defaults)
        controller?.mapping = mapping
        updateUI()
    }

    func setClickSound(_ value: Bool) {
        clickSound = value
        defaults.set(value, forKey: "clickSound")
        updateUI()
    }

    func setTreatPlayPauseAsPress(_ value: Bool) {
        stem.ignoreExplicitPlayPause = !value
        defaults.set(!value, forKey: "ignoreExplicitPlayPause")
        updateUI()
    }

    /// Commit on Return or leaving the field, never probe partial port numbers while typing.
    func setPort(_ text: String) -> String? {
        guard let value = AnkiConnectionSettings.parsePort(text) else { return "Enter a port from 1 to 65535." }
        guard value != port else { return nil }
        guard controller?.isBusy != true else { return "Wait for the current action, then apply the port again." }
        port = value
        defaults.set(value, forKey: AnkiConnectionSettings.portKey)
        configureConnection()
        reconnect()
        updateUI()
        return nil
    }

    func openLabFolder() {
        do {
            try FileManager.default.createDirectory(at: MotionLab.folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(MotionLab.folder)
        } catch { showInputError(error.localizedDescription) }
    }

    private func showInputError(_ message: String) {
        inputError = message
        updateUI()
        menu?.flash(.error)
    }

    func applicationWillTerminate(_ notification: Notification) {
        remoteEnabled = false; calibrating = false
        stem.stop()
        keepAwake.setActive(false)
        lab.stop()
        flick.stop()
        statusTimer?.invalidate()
        for source in signals { source.cancel() }
    }
}
