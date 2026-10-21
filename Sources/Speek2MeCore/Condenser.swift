import Foundation

/// Turns one final assistant message into a few spoken sentences.
public protocol Condenser: Sendable {
    func condense(_ text: String, project: String, model: ClaudeModel, instructions: String) async throws -> String
}

public enum CondenserError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case claudeNotFound
    case invalidAPIKey(String)
    case rateLimited(String)
    case refused
    case timedOut
    case http(status: Int, message: String)
    case claudeCode(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No Claude API key is saved. Add one in Settings."
        case .claudeNotFound: "Claude Code was not found. Install it, or set its path in Settings."
        case .invalidAPIKey(let message): "The API key was rejected: \(message)"
        case .rateLimited(let message): "Rate limited: \(message)"
        case .refused: "Claude declined to condense this message."
        case .timedOut: "Condensing took too long."
        case .http(let status, let message): "Claude API error \(status): \(message)"
        case .claudeCode(let message): "Claude Code failed: \(message)"
        case .badResponse(let message): "Unexpected response: \(message)"
        }
    }
}

/// What will be spoken, and whether the raw message had to stand in.
public struct CondenseOutcome: Sendable, Equatable {
    public let text: String
    public let condensed: Bool
    public let failure: String?
    public let duration: Duration

    public init(text: String, condensed: Bool, failure: String?, duration: Duration) {
        self.text = text
        self.condensed = condensed
        self.failure = failure
        self.duration = duration
    }
}

/// Runs the selected backend under a deadline; any failure falls back to the trimmed raw
/// message, so an announcement is never lost to the network.
public enum CondenseRouter {
    public static func run(
        text: String,
        project: String,
        backend: (any Condenser)?,
        model: ClaudeModel,
        instructions: String,
        timeout: Duration,
        maxSentences: Int
    ) async -> CondenseOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        let raw = RawCondenser.condense(text, maxSentences: maxSentences)
        guard let backend else {
            return CondenseOutcome(text: raw, condensed: false, failure: nil, duration: .zero)
        }
        do {
            let reply = try await withDeadline(timeout) {
                try await backend.condense(text, project: project, model: model, instructions: instructions)
            }
            if reply.isEmpty {
                return CondenseOutcome(text: raw, condensed: false, failure: "Claude returned no text", duration: clock.now - start)
            }
            return CondenseOutcome(text: reply, condensed: true, failure: nil, duration: clock.now - start)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return CondenseOutcome(text: raw, condensed: false, failure: reason, duration: clock.now - start)
        }
    }

    /// Returns the operation's result, or throws `CondenserError.timedOut` and cancels it.
    static func withDeadline<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CondenserError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CondenserError.timedOut }
            return first
        }
    }
}
