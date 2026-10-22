import AppKit
import AVFoundation
import SwiftUI
import Speek2MeCore

/// The voice provider dropdown with the fields that provider needs, a key saver and a Test button.
/// Shared by Settings and the setup guide.
struct VoiceProviderCard: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController
    var onTested: ((Bool) -> Void)? = nil

    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var elevenLabsVoices: [ElevenLabsVoice] = []
    @State private var status: (ok: Bool, text: String)?
    @State private var busy = false

    @State private var appleVoices: [AVSpeechSynthesisVoice] = []

    /// Apple voices worth downloading: far better than the defaults, free, offline.
    private static let recommendedAppleVoices: [(name: String, language: String, label: String)] = [
        ("Alex", "en", "English"),
        ("Henrik", "nb", "Norwegian"),
    ]

    private var provider: VoiceProvider { settings.voiceProvider }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Voice provider", selection: $settings.voiceProvider) {
                ForEach(VoiceProvider.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            Text(provider.note).font(.caption).foregroundStyle(.secondary)

            if provider.needsKey { keyRow }
            if provider.fields.contains(.voice) { voiceRow }
            if provider.fields.contains(.model) {
                TextField("Model", text: binding(.model), prompt: Text(provider.defaultModel))
            }
            if provider.fields.contains(.region) {
                TextField("Azure region, e.g. norwayeast or westeurope", text: binding(.region))
            }
            if provider == .piper { piperRows }

            HStack {
                Button(busy ? "Speaking…" : "Test voice") { Task { await test() } }
                    .disabled(busy)
                if let status {
                    Label(status.text, systemImage: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status.ok ? .green : .orange)
                        .font(.callout)
                        .lineLimit(3)
                }
            }
        }
        .task(id: settings.voiceProvider) {
            status = nil
            keyDraft = ""
            refreshKeyState()
            refreshAppleVoices()
            if provider == .elevenLabs, keySaved, elevenLabsVoices.isEmpty { await loadElevenLabsVoices() }
        }
    }

    // MARK: Rows

    @ViewBuilder private var keyRow: some View {
        HStack {
            SecureField(keySaved ? "Key saved in the Keychain" : "\(provider.displayName) API key", text: $keyDraft)
            Button("Save") { saveKey() }
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Remove", role: .destructive) { removeKey() }
                .disabled(!keySaved)
        }
        if let url = provider.keyURL {
            Link("Get a \(provider.displayName) key", destination: url).font(.caption)
        }
    }

    @ViewBuilder private var voiceRow: some View {
        switch provider {
        case .elevenLabs:
            HStack {
                Picker("Voice", selection: binding(.voice)) {
                    let current = settings.voice(for: .elevenLabs)
                    if !elevenLabsVoices.contains(where: { $0.voiceID == current }) {
                        Text(current == VoiceProvider.elevenLabs.defaultVoice ? "Rachel (default)" : current).tag(current)
                    }
                    ForEach(elevenLabsVoices) { voice in
                        Text(voice.category.map { "\(voice.name) (\($0))" } ?? voice.name).tag(voice.voiceID)
                    }
                }
                Button(busy ? "Loading…" : "Load voices") { Task { await loadElevenLabsVoices() } }
                    .disabled(busy || !keySaved)
            }
        case .apple:
            Picker("Voice", selection: binding(.voice)) {
                Text("System default").tag("")
                ForEach(appleVoices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(voice.language))\(voice.quality == .premium ? " Premium" : voice.quality == .enhanced ? " Enhanced" : "")")
                        .tag(voice.identifier)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Recommended: Alex for English, Henrik for Norwegian. Both download once to this Mac and work offline.")
                    .font(.callout)
                ForEach(Self.recommendedAppleVoices, id: \.name) { recommended in
                    HStack {
                        if let voice = installedAppleVoice(recommended.name, language: recommended.language) {
                            Label("\(recommended.name) (\(recommended.label)) is installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            let inUse = settings.voice(for: .apple) == voice.identifier
                            Button(inUse ? "In use" : "Use \(recommended.name)") { settings.setVoice(voice.identifier, for: .apple) }
                                .disabled(inUse)
                        } else {
                            Label("\(recommended.name) (\(recommended.label)) is not downloaded yet", systemImage: "arrow.down.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("Open Spoken Content settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent")!)
                    }
                    Button("Check again") { refreshAppleVoices() }
                }
                Text("There: System Voice › Manage Voices…, search for Alex or Henrik, click the download arrow, wait for it to finish, then come back and click Use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            TextField("Voice", text: binding(.voice), prompt: Text(provider.defaultVoice))
            Text(provider.voiceHint).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var piperRows: some View {
        LabeledContent("piper command") {
            HStack {
                TextField("Leave empty to search the usual places", text: $settings.piperPath)
                Button("Choose…") { choose(files: true) { settings.piperPath = $0 } }
            }
        }
        LabeledContent("Found at", value: ToolLocator.piper(customPath: settings.piperPath)?.path ?? "not found")
        LabeledContent("Voice model (.onnx)") {
            HStack {
                TextField("Path to the .onnx voice; its .onnx.json must sit beside it", text: $settings.piperModelPath)
                Button("Choose…") { choose(files: true) { settings.piperModelPath = $0 } }
            }
        }
        Link("Piper voices", destination: URL(string: "https://huggingface.co/rhasspy/piper-voices/tree/main")!).font(.caption)
    }

    // MARK: Actions

    private func binding(_ field: VoiceProvider.Field) -> Binding<String> {
        let provider = self.provider
        switch field {
        case .voice: return Binding(get: { settings.voice(for: provider) }, set: { settings.setVoice($0, for: provider) })
        case .model: return Binding(get: { settings.model(for: provider) }, set: { settings.setModel($0, for: provider) })
        case .region: return Binding(get: { settings.region(for: provider) }, set: { settings.setRegion($0, for: provider) })
        default: return .constant("")
        }
    }

    private func refreshAppleVoices() {
        appleVoices = AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    /// The best installed copy of a named voice: Premium over Enhanced over Default.
    private func installedAppleVoice(_ name: String, language: String) -> AVSpeechSynthesisVoice? {
        appleVoices
            .filter { $0.name.hasPrefix(name) && $0.language.hasPrefix(language) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    private func refreshKeyState() {
        keySaved = KeychainStore.account(for: provider).flatMap(KeychainStore.read) != nil
    }

    private func saveKey() {
        guard let account = KeychainStore.account(for: provider) else { return }
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, KeychainStore.save(account, key) else {
            status = (false, "Could not save the key to the Keychain.")
            return
        }
        keyDraft = ""
        keySaved = true
        status = nil
        if provider == .elevenLabs { Task { await loadElevenLabsVoices() } }
    }

    private func removeKey() {
        guard let account = KeychainStore.account(for: provider) else { return }
        KeychainStore.delete(account)
        keySaved = false
        elevenLabsVoices = []
        status = nil
    }

    private func loadElevenLabsVoices() async {
        guard let key = KeychainStore.read(.elevenLabs) else { return }
        busy = true
        defer { busy = false }
        do {
            elevenLabsVoices = try await ElevenLabsClient.listVoices(apiKey: key)
            status = (true, "Key accepted. \(elevenLabsVoices.count) voices available.")
        } catch {
            status = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func test() async {
        busy = true
        defer { busy = false }
        await controller.speakSample("Hi, this is Speek2Me, speaking with \(provider.displayName). I will tell you when a session finishes, or needs you.")
        if let failure = controller.lastFailure {
            status = (false, "\(failure) Spoken with the Apple voice instead.")
            onTested?(false)
        } else {
            status = (true, "Spoken with \(provider.displayName).")
            onTested?(true)
        }
    }

    private func choose(files: Bool, _ completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = !files
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { completion(url.path) }
    }
}
