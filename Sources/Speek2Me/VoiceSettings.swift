import AVFoundation
import SwiftUI
import Speek2MeCore

struct VoiceSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController

    @State private var appleVoices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        Form {
            Section("Voice") {
                VoiceProviderCard(settings: settings, controller: controller)
            }
            if settings.voiceProvider != .apple {
                Section("Fallback") {
                    Picker("Apple voice when the provider fails", selection: Binding(
                        get: { settings.voice(for: .apple) },
                        set: { settings.setVoice($0, for: .apple) }
                    )) {
                        Text("System default").tag("")
                        ForEach(appleVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    }
                }
            }
            Section("Sounds") {
                Toggle("Play a short sound before each announcement", isOn: $settings.earcons)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appleVoices = AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
        }
    }
}
