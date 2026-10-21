import Foundation

/// Puts Speek2Me's Stop and PermissionRequest handlers into `~/.codex/hooks.json` and turns the
/// hooks feature on in `~/.codex/config.toml`. Codex still asks the user to trust new hooks once.
public enum CodexHooksInstaller {
    /// `SPEEK2ME_CODEX_HOME` points the app at a scratch directory while developing.
    public static var codexHome: URL {
        if let override = ProcessInfo.processInfo.environment["SPEEK2ME_CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    public static var hooksURL: URL { codexHome.appendingPathComponent("hooks.json") }
    public static var configURL: URL { codexHome.appendingPathComponent("config.toml") }

    public static func groups(command: String) -> [HooksJSON.Group] {
        let handler = HooksJSON.Handler(command: command)
        return [
            HooksJSON.Group(event: "Stop", matcher: nil, handler: handler),
            HooksJSON.Group(event: "PermissionRequest", matcher: nil, handler: handler),
        ]
    }

    public static func isInstalled(hooksAt hooksURL: URL = hooksURL) -> Bool {
        (try? HooksJSON.isInstalled(ConfigFile.read(hooksURL))) ?? false
    }

    public static func plannedChange(command: String, hooksAt hooksURL: URL = hooksURL, configAt configURL: URL = configURL) throws -> (hooks: String, config: String) {
        let hooks = try HooksJSON.pretty(try HooksJSON.install(try ConfigFile.read(hooksURL), groups: groups(command: command)))
        let config = TOMLFeatures.enableHooks(in: try configText(configURL))
        return (hooks, config)
    }

    /// Returns the backups made; empty when nothing needed changing.
    @discardableResult
    public static func install(command: String, hooksAt hooksURL: URL = hooksURL, configAt configURL: URL = configURL) throws -> [URL] {
        var backups: [URL] = []
        let currentHooks = try ConfigFile.read(hooksURL)
        if try !HooksJSON.isInstalled(currentHooks) {
            let patched = try HooksJSON.install(currentHooks, groups: groups(command: command))
            if let backup = try ConfigFile.writeWithBackup(patched, to: hooksURL) { backups.append(backup) }
        }
        let config = try configText(configURL)
        if !TOMLFeatures.hooksEnabled(in: config) {
            let patched = Data(TOMLFeatures.enableHooks(in: config).utf8)
            if let backup = try ConfigFile.writeWithBackup(patched, to: configURL) { backups.append(backup) }
        }
        return backups
    }

    /// Takes the handlers out of hooks.json. `features.hooks` stays: it may serve other hooks.
    @discardableResult
    public static func remove(hooksAt hooksURL: URL = hooksURL) throws -> URL? {
        let current = try ConfigFile.read(hooksURL)
        guard try HooksJSON.isInstalled(current) else { return nil }
        return try ConfigFile.writeWithBackup(try HooksJSON.remove(current), to: hooksURL)
    }

    private static func configText(_ url: URL) throws -> String {
        guard let data = try ConfigFile.read(url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
