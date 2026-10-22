import AppKit
import Speek2MeCore

/// The menu-bar icon and its menu.
@MainActor
final class StatusBarController: NSObject {
    struct Actions {
        var openSettings: () -> Void
        var openSessions: () -> Void
        var openUpdates: () -> Void
        var openSetupGuide: () -> Void
        var openAbout: () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: AnnouncementController
    private let settings: AppSettings
    private let actions: Actions
    private let stateLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lastLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let failureLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let muteItem = NSMenuItem(title: "Pause announcements", action: #selector(toggleMute), keyEquivalent: "m")
    private let repairItem = NSMenuItem(title: "Repair hooks…", action: #selector(openSessions), keyEquivalent: "")

    init(controller: AnnouncementController, settings: AppSettings, actions: Actions) {
        self.controller = controller
        self.settings = settings
        self.actions = actions
        super.init()

        let menu = NSMenu()
        for line in [stateLine, lastLine, failureLine] { line.isEnabled = false }
        menu.addItem(stateLine)
        menu.addItem(lastLine)
        menu.addItem(failureLine)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Replay", action: #selector(replay), key: "r"))
        menu.addItem(menuItem(title: "Stop", action: #selector(stop), key: "."))
        muteItem.target = self
        menu.addItem(muteItem)
        menu.addItem(.separator())
        repairItem.target = self
        menu.addItem(repairItem)
        menu.addItem(menuItem(title: "Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(menuItem(title: "Setup Guide…", action: #selector(showSetupGuide), key: ""))
        menu.addItem(menuItem(title: "Check for Updates…", action: #selector(showUpdates), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "About Speek2Me", action: #selector(showAbout), key: ""))
        menu.addItem(NSMenuItem(title: "Quit Speek2Me", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        refresh()
    }

    private func menuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    func refresh() {
        let (symbol, state): (String, String) = if settings.muted {
            ("pause.circle", "Paused" + (settings.pauseHotkeyEnabled ? ". \(GlobalHotkey.pauseDescription) resumes" : ""))
        } else {
            switch controller.phase {
            case .idle: ("speaker.wave.2", "Listening for sessions")
            case .condensing: ("sparkles", "Condensing with Claude…")
            case .speaking: ("speaker.wave.3.fill", "Speaking…")
            case .needsYou: ("exclamationmark.bubble", "A session needs you")
            }
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Speek2Me: \(state)")
        stateLine.title = state
        lastLine.title = "Last: \(controller.lastAnnouncement.prefix(80))"
        failureLine.title = controller.lastFailure.map { "Note: \($0.prefix(80))" } ?? ""
        failureLine.isHidden = controller.lastFailure == nil
        muteItem.state = settings.muted ? .on : .off
        muteItem.title = settings.pauseHotkeyEnabled ? "Pause announcements (\(GlobalHotkey.pauseDescription))" : "Pause announcements"
        let stale = controller.hookHealth.values.contains { $0 == false }
        repairItem.isHidden = !stale
    }

    @objc private func replay() { controller.replay() }
    @objc private func stop() { controller.stop() }
    @objc private func toggleMute() { settings.muted.toggle() }
    @objc private func openSessions() { actions.openSessions() }
    @objc private func showSettings() { actions.openSettings() }
    @objc private func showSetupGuide() { actions.openSetupGuide() }
    @objc private func showUpdates() { actions.openUpdates() }
    @objc private func showAbout() { actions.openAbout() }
}
