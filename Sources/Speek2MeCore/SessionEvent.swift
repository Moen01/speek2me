import Foundation

/// Which tool a session belongs to.
public enum SessionSource: String, Codable, Sendable {
    case claudeCode
    case codex
}

/// What happened: the turn ended, or the session is waiting for the user.
public enum EventKind: String, Codable, Sendable {
    case turnComplete
    case needsYou
}

/// Why a session needs the user. `none` for a completed turn.
public enum AttentionReason: String, Codable, Sendable {
    case permission
    case question
    case idle
    case none
}

/// One thing worth saying out loud, normalized from a hook payload.
public struct SessionEvent: Codable, Sendable, Equatable {
    public var source: SessionSource
    public var kind: EventKind
    public var reason: AttentionReason
    /// The final assistant message, or the notification text.
    public var text: String
    public var sessionID: String
    public var cwd: String
    public var receivedAt: Date

    public init(source: SessionSource, kind: EventKind, reason: AttentionReason, text: String,
                sessionID: String, cwd: String, receivedAt: Date) {
        self.source = source
        self.kind = kind
        self.reason = reason
        self.text = text
        self.sessionID = sessionID
        self.cwd = cwd
        self.receivedAt = receivedAt
    }

    /// The name spoken before every announcement, so you know which session is talking.
    public var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return cwd.isEmpty || name.isEmpty || name == "/" ? "a session" : name
    }
}
