import Combine
import Foundation
import Speek2MeCore

/// User preferences, stored in UserDefaults. API keys live in the Keychain instead.
final class AppSettings: ObservableObject {
    private enum Key {
        static let condenser = "condenser"
        static let model = "claudeModel"
        static let timeout = "condenseTimeoutSeconds"
        static let claudePath = "claudeCodePath"
        static let codexPath = "codexPath"
        static let extraInstructions = "extraInstructions"
        static let readFull = "readFullMessage"
        static let maxSentences = "maxSentences"
        static let voiceProvider = "voiceProvider"
        static let providerVoices = "providerVoices"
        static let providerModels = "providerModels"
        static let providerRegions = "providerRegions"
        static let piperPath = "piperPath"
        static let piperModelPath = "piperModelPath"
        // Older builds stored ElevenLabs-only settings under these keys.
        static let legacyUseElevenLabs = "useElevenLabs"
        static let legacyVoiceID = "elevenLabsVoiceID"
        static let legacyModelID = "elevenLabsModelID"
        static let legacyAppleVoiceID = "appleVoiceID"
        static let earcons = "earcons"
        static let muted = "muted"
        static let pauseHotkeyEnabled = "pauseHotkeyEnabled"
        static let quietWhenTerminalFocused = "quietWhenTerminalFocused"
        static let terminalBundleIDs = "terminalBundleIDs"
        static let speakIdle = "speakIdleNudges"
        static let onboarded = "hasCompletedOnboarding"
    }

    static let defaultTerminalBundleIDs = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.cmux.app",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty",
    ]

    private let defaults: UserDefaults

    @Published var condenser: CondenserKind { didSet { defaults.set(condenser.rawValue, forKey: Key.condenser) } }
    @Published var model: ClaudeModel { didSet { defaults.set(model.rawValue, forKey: Key.model) } }
    @Published var timeoutSeconds: Double { didSet { defaults.set(timeoutSeconds, forKey: Key.timeout) } }
    @Published var claudePath: String { didSet { defaults.set(claudePath, forKey: Key.claudePath) } }
    @Published var codexPath: String { didSet { defaults.set(codexPath, forKey: Key.codexPath) } }
    @Published var extraInstructions: String { didSet { defaults.set(extraInstructions, forKey: Key.extraInstructions) } }
    /// Speak the whole final message (trimmed of markup) instead of a condensed version.
    @Published var readFull: Bool { didSet { defaults.set(readFull, forKey: Key.readFull) } }
    @Published var maxSentences: Int { didSet { defaults.set(maxSentences, forKey: Key.maxSentences) } }
    @Published var voiceProvider: VoiceProvider { didSet { defaults.set(voiceProvider.rawValue, forKey: Key.voiceProvider) } }
    /// Per provider: the voice (or voice id, or Deepgram model). Missing means the provider's default.
    @Published var providerVoices: [String: String] { didSet { defaults.set(providerVoices, forKey: Key.providerVoices) } }
    @Published var providerModels: [String: String] { didSet { defaults.set(providerModels, forKey: Key.providerModels) } }
    @Published var providerRegions: [String: String] { didSet { defaults.set(providerRegions, forKey: Key.providerRegions) } }
    @Published var piperPath: String { didSet { defaults.set(piperPath, forKey: Key.piperPath) } }
    @Published var piperModelPath: String { didSet { defaults.set(piperModelPath, forKey: Key.piperModelPath) } }
    @Published var earcons: Bool { didSet { defaults.set(earcons, forKey: Key.earcons) } }
    /// Paused: nothing is read from the inbox, condensed or spoken until resumed.
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: Key.muted) } }
    @Published var pauseHotkeyEnabled: Bool { didSet { defaults.set(pauseHotkeyEnabled, forKey: Key.pauseHotkeyEnabled) } }
    @Published var quietWhenTerminalFocused: Bool { didSet { defaults.set(quietWhenTerminalFocused, forKey: Key.quietWhenTerminalFocused) } }
    @Published var terminalBundleIDs: [String] { didSet { defaults.set(terminalBundleIDs, forKey: Key.terminalBundleIDs) } }
    @Published var speakIdle: Bool { didSet { defaults.set(speakIdle, forKey: Key.speakIdle) } }

    // MARK: - Per-provider voice settings

    func voice(for provider: VoiceProvider) -> String {
        providerVoices[provider.rawValue] ?? provider.defaultVoice
    }

    func setVoice(_ value: String, for provider: VoiceProvider) {
        providerVoices[provider.rawValue] = value
    }

    func model(for provider: VoiceProvider) -> String {
        providerModels[provider.rawValue] ?? provider.defaultModel
    }

    func setModel(_ value: String, for provider: VoiceProvider) {
        providerModels[provider.rawValue] = value
    }

    func region(for provider: VoiceProvider) -> String {
        providerRegions[provider.rawValue] ?? provider.defaultRegion
    }

    func setRegion(_ value: String, for provider: VoiceProvider) {
        providerRegions[provider.rawValue] = value
    }

    func cloudConfig(for provider: VoiceProvider) -> CloudSpeechConfig {
        CloudSpeechConfig(voice: voice(for: provider), model: model(for: provider), region: region(for: provider))
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        condenser = defaults.string(forKey: Key.condenser).flatMap(CondenserKind.init(rawValue:)) ?? .claudeCode
        model = defaults.string(forKey: Key.model).flatMap(ClaudeModel.init(rawValue:)) ?? .haiku
        timeoutSeconds = defaults.object(forKey: Key.timeout) as? Double ?? 15
        claudePath = defaults.string(forKey: Key.claudePath) ?? ""
        codexPath = defaults.string(forKey: Key.codexPath) ?? ""
        extraInstructions = defaults.string(forKey: Key.extraInstructions) ?? ""
        readFull = defaults.object(forKey: Key.readFull) as? Bool ?? false
        maxSentences = defaults.object(forKey: Key.maxSentences) as? Int ?? 3
        let legacyApple = defaults.object(forKey: Key.legacyUseElevenLabs) as? Bool == false
        voiceProvider = defaults.string(forKey: Key.voiceProvider).flatMap(VoiceProvider.init(rawValue:)) ?? (legacyApple ? .apple : .elevenLabs)
        var voices = defaults.dictionary(forKey: Key.providerVoices) as? [String: String] ?? [:]
        if let legacy = defaults.string(forKey: Key.legacyVoiceID), voices[VoiceProvider.elevenLabs.rawValue] == nil { voices[VoiceProvider.elevenLabs.rawValue] = legacy }
        if let legacy = defaults.string(forKey: Key.legacyAppleVoiceID), voices[VoiceProvider.apple.rawValue] == nil { voices[VoiceProvider.apple.rawValue] = legacy }
        providerVoices = voices
        var models = defaults.dictionary(forKey: Key.providerModels) as? [String: String] ?? [:]
        if let legacy = defaults.string(forKey: Key.legacyModelID), models[VoiceProvider.elevenLabs.rawValue] == nil { models[VoiceProvider.elevenLabs.rawValue] = legacy }
        providerModels = models
        providerRegions = defaults.dictionary(forKey: Key.providerRegions) as? [String: String] ?? [:]
        piperPath = defaults.string(forKey: Key.piperPath) ?? ""
        piperModelPath = defaults.string(forKey: Key.piperModelPath) ?? ""
        earcons = defaults.object(forKey: Key.earcons) as? Bool ?? true
        muted = defaults.object(forKey: Key.muted) as? Bool ?? false
        pauseHotkeyEnabled = defaults.object(forKey: Key.pauseHotkeyEnabled) as? Bool ?? true
        quietWhenTerminalFocused = defaults.object(forKey: Key.quietWhenTerminalFocused) as? Bool ?? false
        terminalBundleIDs = defaults.stringArray(forKey: Key.terminalBundleIDs) ?? Self.defaultTerminalBundleIDs
        speakIdle = defaults.object(forKey: Key.speakIdle) as? Bool ?? true
    }
}
