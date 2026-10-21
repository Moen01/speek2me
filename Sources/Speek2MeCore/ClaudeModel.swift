import Foundation

/// The Claude models offered in the model picker.
public enum ClaudeModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        case .haiku: "Claude Haiku 5.5"
        }
    }

    /// Server-side refusal fallbacks exist for Opus 5.5 and Sonnet 5.5, not for Haiku 5.5.
    public var supportsServerFallbacks: Bool { self != .haiku }

    /// The oldest Claude Code that can run this model, when known.
    public var minimumClaudeCodeVersion: String? {
        self == .opus ? "2.1.280" : nil
    }
}

/// Where a final message goes to be condensed before it is spoken.
public enum CondenserKind: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The user's own Claude Code install, signed in with `claude auth login`.
    case claudeCode
    /// A Claude Console API key stored in the Keychain.
    case apiKey
    /// No condensing: speak the raw message, trimmed to a few sentences.
    case off

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code (your subscription)"
        case .apiKey: "Claude API key"
        case .off: "Off: speak the raw message"
        }
    }
}
