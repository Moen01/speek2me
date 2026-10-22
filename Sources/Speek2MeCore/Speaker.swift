import Foundation

/// Says one announcement out loud.
public protocol Speaker: Sendable {
    func speak(_ text: String) async throws
    func stop() async
}

public enum SpeakerError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case invalidAPIKey(String)
    case quotaOrRateLimit(String)
    case http(status: Int, message: String)
    case timedOut
    case badAudio
    case playbackFailed(String)
    /// A local engine (Piper) is missing, misconfigured or failed.
    case engine(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No API key is saved for this voice provider."
        case .invalidAPIKey(let message): "The voice provider rejected the key: \(message)"
        case .quotaOrRateLimit(let message): "Voice provider quota or rate limit: \(message)"
        case .http(let status, let message): "Voice provider error \(status): \(message)"
        case .timedOut: "The voice provider took too long."
        case .badAudio: "The voice provider returned no playable audio."
        case .playbackFailed(let message): "Playback failed: \(message)"
        case .engine(let message): "Local voice: \(message)"
        }
    }
}

/// Stands in for a provider that is selected but not set up; speaking it reports the reason.
public struct UnavailableSpeaker: Speaker {
    public let error: SpeakerError

    public init(_ error: SpeakerError) {
        self.error = error
    }

    public func speak(_ text: String) async throws { throw error }
    public func stop() async {}
}

/// The short system sound played before an announcement, so the kind is clear before the words.
public enum Earcon: String, CaseIterable, Sendable {
    case done
    case permission
    case question
    case idle

    public var fileURL: URL {
        let name = switch self {
        case .done: "Glass"
        case .permission: "Sosumi"
        case .question: "Ping"
        case .idle: "Tink"
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
    }

    public static func forEvent(_ event: SessionEvent) -> Earcon {
        switch (event.kind, event.reason) {
        case (.turnComplete, _): .done
        case (.needsYou, .permission): .permission
        case (.needsYou, .question): .question
        case (.needsYou, .idle), (.needsYou, .none): .idle
        }
    }
}
