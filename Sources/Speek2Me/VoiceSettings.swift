import AVFoundation
import SwiftUI
import Speek2MeCore

struct VoiceSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController

    @State private var keyDraft = ""
    @State private var keySaved = KeychainStore.read(.elevenLabs) != nil
    @State private var voices: [ElevenLabsVoice] = []
    @State private var status: (ok: Bool, text: String)?
    @State private var busy = false

    private let appleVoices = AVSpeechSynthesisVoice.speechVoices().sorted {
        ($0.language, $0.name) < ($1.language, $1.name)
    }

    var body: some View {
        Form {
            Section("ElevenLabs") {
                SecureField(keySaved ? "Saved in the Keychain" : "ElevenLabs API key", text: $keyDraft)
                HStack {
                    Button("Save key") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove key", role: .destructive) {
                        KeychainStore.delete(.elevenLabs)
                        keySaved = false
                        voices = []
                        status = nil
                    }
                    .disabled(!keySaved)
                    Spacer()
                    Button(busy ? "Testing…" : "Test voice") { Task { await test() } }
                        .disabled(busy)
                }
                if keySaved {
                    Picker("Voice", selection: $settings.voiceID) {
                        if !voices.contains(where: { $0.voiceID == settings.voiceID }) {
                            Text(settings.voiceID == ElevenLabsClient.defaultVoiceID ? "Rachel (default)" : settings.voiceID)
                                .tag(settings.voiceID)
                        }
                        ForEach(voices) { voice in
                            Text(voice.category.map { "\(voice.name) (\($0))" } ?? voice.name).tag(voice.voiceID)
                        }
                    }
                    HStack {
                        TextField("Model", text: $settings.modelID)
                        Button(busy ? "Loading…" : "Load voices") { Task { await loadVoices() } }
                            .disabled(busy)
                    }
                }
                if let status {
                    Label(status.text, systemImage: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status.ok ? .green : .orange)
                        .font(.callout)
                        .lineLimit(3)
                }
                Text("Create a key at elevenlabs.io. Each announcement is billed to it. Without a key, or when ElevenLabs fails, the Apple voice below speaks instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple voice (fallback)") {
                Picker("Voice", selection: $settings.appleVoiceID) {
                    Text("System default").tag("")
                    ForEach(appleVoices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
                Text("Better voices can be downloaded in System Settings > Accessibility > Spoken Content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sounds") {
                Toggle("Play a short sound before each announcement", isOn: $settings.earcons)
            }
        }
        .formStyle(.grouped)
        .task { if keySaved, voices.isEmpty { await loadVoices() } }
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, KeychainStore.save(.elevenLabs, key) else {
            status = (false, "Could not save the key to the Keychain.")
            return
        }
        keyDraft = ""
        keySaved = true
        status = nil
        Task { await loadVoices() }
    }

    private func loadVoices() async {
        guard let key = KeychainStore.read(.elevenLabs) else { return }
        busy = true
        defer { busy = false }
        do {
            voices = try await ElevenLabsClient.listVoices(apiKey: key)
            status = (true, "Key accepted. \(voices.count) voices available.")
        } catch {
            status = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func test() async {
        busy = true
        defer { busy = false }
        if let key = KeychainStore.read(.elevenLabs) {
            do {
                try await ElevenLabsClient.verify(apiKey: key)
            } catch {
                status = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return
            }
        }
        await controller.speakSample("Speek2Me is ready. I will tell you when a session finishes or needs you.")
        status = controller.lastFailure.map { (false, $0) } ?? (true, keySaved ? "Spoken with ElevenLabs." : "Spoken with the Apple voice. Add an ElevenLabs key for a better one.")
    }
}
