import Foundation

/// What the `speek2me-hook` command does. Kept out of `main.swift` so tests can call it.
public enum HookEntry {
    /// Parses one hook payload for `tool` ("claude" or "codex") and drops it into the inbox.
    /// Always returns 0: a notifier must never block or fail the session it watches.
    public static func run(tool: String, input: Data, environment: [String: String], inbox: Inbox, now: Date = .init()) -> Int32 {
        // Set by the app on the `claude -p` it spawns to condense a message, so that turn's own
        // Stop hook does not come back around as a new announcement.
        guard environment["SPEEK2ME_SUPPRESS"] != "1" else { return 0 }
        let event: SessionEvent? = switch tool {
        case "claude": HookPayloadParser.parseClaude(input, now: now)
        case "codex": HookPayloadParser.parseCodex(input, now: now)
        default: nil
        }
        if let event { try? inbox.write(event) }
        return 0
    }
}
