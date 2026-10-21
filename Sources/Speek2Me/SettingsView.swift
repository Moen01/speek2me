import Combine
import SwiftUI
import Speek2MeCore

enum SettingsTab: Hashable {
    case voice, claude, sessions, behaviour, about
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController
    let selectedTab: CurrentValueSubject<SettingsTab, Never>

    @State private var tab: SettingsTab = .voice

    var body: some View {
        TabView(selection: $tab) {
            VoiceSettings(settings: settings, controller: controller)
                .tabItem { Label("Voice", systemImage: "speaker.wave.2") }
                .tag(SettingsTab.voice)
            ClaudeSettings(settings: settings, controller: controller)
                .tabItem { Label("Claude", systemImage: "sparkles") }
                .tag(SettingsTab.claude)
            SessionsSettings(settings: settings, controller: controller)
                .tabItem { Label("Sessions", systemImage: "terminal") }
                .tag(SettingsTab.sessions)
            BehaviourSettings(settings: settings)
                .tabItem { Label("Behaviour", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.behaviour)
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        // A grouped Form scrolls and has no height of its own; give the window one.
        .frame(width: 560, height: 620)
        .onAppear { tab = selectedTab.value }
        .onReceive(selectedTab) { tab = $0 }
    }
}

private struct AboutSettings: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Hook command", value: HookCommand.executableURL(bundleURL: Bundle.main.bundleURL).path)
                LabeledContent("Inbox", value: Inbox.defaultDirectory.path)
                Link("github.com/Moen01/speek2me", destination: URL(string: "https://github.com/Moen01/speek2me")!)
            }
            Section("Privacy") {
                Text("With ElevenLabs set up, the spoken sentences are sent to ElevenLabs. With a Claude backend on, the full final message is sent to Anthropic to be condensed. With both off, nothing leaves this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
