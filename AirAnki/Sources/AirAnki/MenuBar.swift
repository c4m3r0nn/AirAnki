import AirAnkiCore
import AppKit

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var owner: AppDelegate?
    private var flashTimer: Timer?
    private let normalImage = NSImage(systemSymbolName: "airpods.pro", accessibilityDescription: "AirAnki")
        ?? NSImage(systemSymbolName: "airpodspro", accessibilityDescription: "AirAnki")

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        normalImage?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        restoreIcon()
    }

    func update() {
        guard let owner else { return }
        item.button?.toolTip = "AirAnki — \(owner.model.headline.text)"
        if flashTimer == nil { restoreIcon() }
    }

    func flash(_ feedback: ActionFeedback) {
        flashTimer?.invalidate()
        item.button?.image = nil
        item.button?.title = feedback.symbol
        let timer = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flashTimer = nil
                self?.restoreIcon()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flashTimer = timer
    }

    private func restoreIcon() {
        item.button?.image = normalImage
        item.button?.title = normalImage == nil ? "AA" : ""
        item.button?.appearsDisabled = owner?.remoteEnabled != true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let owner else { return }
        menu.removeAllItems()
        let h = owner.model.headline
        let title = NSMenuItem(title: h.text, action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: h.text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        title.isEnabled = false
        menu.addItem(title)
        if !h.detail.isEmpty { add(h.detail, to: menu) }
        menu.addItem(.separator())
        let remote = add(owner.remoteEnabled ? "Pause AirAnki" : "Resume AirAnki", action: #selector(toggleRemote), to: menu)
        remote.keyEquivalent = "p"
        add("Open AirAnki…", action: #selector(showWindow), to: menu).keyEquivalent = "o"
        add("Recalibrate Flicks…", action: #selector(calibrate), to: menu)
        add("Settings…", action: #selector(showSettings), to: menu).keyEquivalent = ","
        menu.addItem(.separator())
        let advanced = add("Advanced", to: menu)
        advanced.isEnabled = true
        let more = NSMenu(); more.autoenablesItems = false
        let lab = add("Lab Mode (Record Motion)", action: #selector(toggleLab), to: more)
        lab.state = owner.lab.isActive ? .on : .off
        if owner.lab.isActive {
            add(owner.lab.status, to: more)
            add("Insert Marker", action: #selector(insertMarker), to: more)
        }
        add("Open Lab Folder", action: #selector(openLabFolder), to: more)
        if !owner.labOnly {
            let reconnect = add("Reconnect to Anki", action: #selector(reconnect), to: more)
            reconnect.isEnabled = owner.controller?.isBusy != true
        }
        advanced.submenu = more
        menu.addItem(.separator())
        let quit = add("Quit AirAnki", action: #selector(quit), to: menu)
        quit.keyEquivalent = "q"
    }

    @discardableResult
    private func add(_ title: String, action: Selector? = nil, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = action != nil
        menu.addItem(entry)
        return entry
    }

    @objc private func calibrate() { owner?.calibrate() }
    @objc private func toggleRemote() { owner?.toggleRemote() }
    @objc private func showWindow() { owner?.showWindow() }
    @objc private func showSettings() { owner?.showSettings() }
    @objc private func toggleLab() { owner?.toggleLab() }
    @objc private func insertMarker() { owner?.lab.insertMarker() }
    @objc private func openLabFolder() { owner?.openLabFolder() }
    @objc private func reconnect() { owner?.reconnect() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
