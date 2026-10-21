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
        static let useElevenLabs = "useElevenLabs"
        static let voiceID = "elevenLabsVoiceID"
        static let modelID = "elevenLabsModelID"
        static let appleVoiceID = "appleVoiceID"
        static let earcons = "earcons"
        static let muted = "muted"
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
    /// Off keeps a saved key but speaks with the Apple voice only.
    @Published var useElevenLabs: Bool { didSet { defaults.set(useElevenLabs, forKey: Key.useElevenLabs) } }
    @Published var voiceID: String { didSet { defaults.set(voiceID, forKey: Key.voiceID) } }
    @Published var modelID: String { didSet { defaults.set(modelID, forKey: Key.modelID) } }
    @Published var appleVoiceID: String { didSet { defaults.set(appleVoiceID, forKey: Key.appleVoiceID) } }
    @Published var earcons: Bool { didSet { defaults.set(earcons, forKey: Key.earcons) } }
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: Key.muted) } }
    @Published var quietWhenTerminalFocused: Bool { didSet { defaults.set(quietWhenTerminalFocused, forKey: Key.quietWhenTerminalFocused) } }
    @Published var terminalBundleIDs: [String] { didSet { defaults.set(terminalBundleIDs, forKey: Key.terminalBundleIDs) } }
    @Published var speakIdle: Bool { didSet { defaults.set(speakIdle, forKey: Key.speakIdle) } }

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
        useElevenLabs = defaults.object(forKey: Key.useElevenLabs) as? Bool ?? true
        voiceID = defaults.string(forKey: Key.voiceID) ?? ElevenLabsClient.defaultVoiceID
        modelID = defaults.string(forKey: Key.modelID) ?? ElevenLabsClient.defaultModelID
        appleVoiceID = defaults.string(forKey: Key.appleVoiceID) ?? ""
        earcons = defaults.object(forKey: Key.earcons) as? Bool ?? true
        muted = defaults.object(forKey: Key.muted) as? Bool ?? false
        quietWhenTerminalFocused = defaults.object(forKey: Key.quietWhenTerminalFocused) as? Bool ?? false
        terminalBundleIDs = defaults.stringArray(forKey: Key.terminalBundleIDs) ?? Self.defaultTerminalBundleIDs
        speakIdle = defaults.object(forKey: Key.speakIdle) as? Bool ?? true
    }
}
