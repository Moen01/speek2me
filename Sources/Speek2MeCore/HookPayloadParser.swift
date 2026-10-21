import Foundation

/// Turns the JSON a Claude Code or Codex hook receives on stdin into a `SessionEvent`, or nil
/// when there is nothing to say: subagent turns, headless runs, unknown events, malformed input.
public enum HookPayloadParser {
    /// Claude Code `notification_type` values that mean the session is waiting for the user.
    public static let claudeNotificationReasons: [String: AttentionReason] = [
        "permission_prompt": .permission,
        "elicitation_dialog": .question,
        "elicitation_url_dialog": .question,
        "agent_needs_input": .question,
        "idle_prompt": .idle,
    ]

    /// Working directories of headless `claude -p` runs, such as Talk2Me's cleanup turns.
    /// Their Stop hooks fire too, and nobody wants a dictation read back.
    public static let temporaryPrefixes: [String] = [
        NSTemporaryDirectory(), "/private/var/folders/", "/var/folders/", "/tmp/", "/private/tmp/",
    ]

    public static func parseClaude(_ data: Data, now: Date = .init()) -> SessionEvent? {
        guard let payload = object(from: data), let event = payload["hook_event_name"] as? String else { return nil }
        let cwd = payload["cwd"] as? String ?? ""
        guard !isTemporary(cwd) else { return nil }
        let sessionID = payload["session_id"] as? String ?? ""
        switch event {
        case "Stop":
            guard payload["agent_id"] == nil, let text = finalText(payload) else { return nil }
            return SessionEvent(source: .claudeCode, kind: .turnComplete, reason: .none, text: text,
                                sessionID: sessionID, cwd: cwd, receivedAt: now)
        case "Notification":
            guard let type = payload["notification_type"] as? String,
                  let reason = claudeNotificationReasons[type] else { return nil }
            return SessionEvent(source: .claudeCode, kind: .needsYou, reason: reason,
                                text: payload["message"] as? String ?? "",
                                sessionID: sessionID, cwd: cwd, receivedAt: now)
        default:
            return nil
        }
    }

    public static func parseCodex(_ data: Data, now: Date = .init()) -> SessionEvent? {
        guard let payload = object(from: data), let event = payload["hook_event_name"] as? String else { return nil }
        let cwd = payload["cwd"] as? String ?? ""
        guard !isTemporary(cwd) else { return nil }
        let sessionID = payload["session_id"] as? String ?? ""
        switch event {
        case "Stop":
            guard let text = finalText(payload) else { return nil }
            return SessionEvent(source: .codex, kind: .turnComplete, reason: .none, text: text,
                                sessionID: sessionID, cwd: cwd, receivedAt: now)
        case "PermissionRequest":
            let tool = payload["tool_name"] as? String ?? "a tool"
            let description = (payload["tool_input"] as? [String: Any])?["description"] as? String
            let text = description.map { "\(tool): \($0)" } ?? tool
            return SessionEvent(source: .codex, kind: .needsYou, reason: .permission, text: text,
                                sessionID: sessionID, cwd: cwd, receivedAt: now)
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func finalText(_ payload: [String: Any]) -> String? {
        guard let text = payload["last_assistant_message"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    static func isTemporary(_ cwd: String) -> Bool {
        temporaryPrefixes.contains { !$0.isEmpty && cwd.hasPrefix($0) }
    }
}
