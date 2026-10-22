import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var controller: AnnouncementController!
    private var statusBar: StatusBarController!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private let settingsTab = CurrentValueSubject<SettingsTab, Never>(.voice)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AnnouncementController(settings: settings)
        statusBar = StatusBarController(controller: controller, settings: settings, actions: .init(
            openSettings: { [weak self] in self?.showSettings() },
            openSessions: { [weak self] in self?.showSettings(tab: .sessions) },
            openUpdates: { [weak self] in self?.showSettings(tab: .about) },
            openSetupGuide: { [weak self] in self?.showOnboarding() },
            openAbout: { [weak self] in self?.showAbout() }
        ))
        // @Published fires before the value changes; refresh on the next run-loop turn.
        Publishers.Merge(controller.objectWillChange.map { _ in () }, settings.objectWillChange.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.statusBar.refresh() }
            .store(in: &subscriptions)
        settings.$claudePath
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in Task { await self?.controller.refreshClaudeExecutable() } }
            .store(in: &subscriptions)

        controller.start()
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    private func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab.send(tab) }
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, controller: controller, selectedTab: settingsTab)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Speek2Me Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(settings: settings, controller: controller) { [weak self] in
                self?.onboardingWindow?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Speek2Me"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                // Closing the guide counts as done; it stays available from the menu.
                MainActor.assumeIsolated { self?.settings.hasCompletedOnboarding = true }
            }
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let credits = NSAttributedString(
            string: "Speaks the final answer of each Claude Code or Codex turn, and tells you when a session needs you.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Speek2Me",
            .applicationVersion: version,
            .credits: credits,
        ])
    }
}
