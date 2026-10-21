import Foundation

/// Puts Speek2Me's Stop and Notification handlers into `~/.claude/settings.json`, and takes them out.
public enum ClaudeHooksInstaller {
    /// `SPEEK2ME_CLAUDE_SETTINGS` points the app at a scratch file while developing.
    public static var settingsURL: URL {
        if let override = ProcessInfo.processInfo.environment["SPEEK2ME_CLAUDE_SETTINGS"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Exact-string alternatives; Claude Code matches these against `notification_type`.
    public static let notificationMatcher = "permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|idle_prompt"

    public static func groups(command: String) -> [HooksJSON.Group] {
        let handler = HooksJSON.Handler(command: command)
        return [
            HooksJSON.Group(event: "Stop", matcher: nil, handler: handler),
            HooksJSON.Group(event: "Notification", matcher: notificationMatcher, handler: handler),
        ]
    }

    public static func isInstalled(at url: URL = settingsURL) -> Bool {
        (try? HooksJSON.isInstalled(ConfigFile.read(url))) ?? false
    }

    /// The whole file as it would look after install, for the "Show change" sheet.
    public static func plannedChange(command: String, at url: URL = settingsURL) throws -> String {
        try HooksJSON.pretty(try HooksJSON.install(try ConfigFile.read(url), groups: groups(command: command)))
    }

    /// Returns the backup URL when an existing file was rewritten; nil when nothing changed or
    /// the file is new.
    @discardableResult
    public static func install(command: String, at url: URL = settingsURL) throws -> URL? {
        let current = try ConfigFile.read(url)
        guard try !HooksJSON.isInstalled(current) else { return nil }
        return try ConfigFile.writeWithBackup(try HooksJSON.install(current, groups: groups(command: command)), to: url)
    }

    @discardableResult
    public static func remove(at url: URL = settingsURL) throws -> URL? {
        let current = try ConfigFile.read(url)
        guard try HooksJSON.isInstalled(current) else { return nil }
        return try ConfigFile.writeWithBackup(try HooksJSON.remove(current), to: url)
    }
}
