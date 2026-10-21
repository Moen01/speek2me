import Foundation

/// The shell command a hook runs: the bundled CLI, quoted, plus the tool name.
public enum HookCommand {
    public static func executableURL(bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/MacOS/speek2me-hook")
    }

    public static func command(bundleURL: URL, tool: String) -> String {
        "\"\(executableURL(bundleURL: bundleURL).path)\" \(tool)"
    }

    /// The executable in a command string: the first quoted token, else the first word.
    public static func executablePath(in command: String) -> String? {
        if let quoted = command.firstMatch(of: #/^"([^"]+)"/#) { return String(quoted.1) }
        return command.split(separator: " ", maxSplits: 1).first.map(String.init)
    }

    /// Whether the command still points at an executable, which it stops doing when the app moves.
    public static func isHealthy(_ command: String) -> Bool {
        guard let path = executablePath(in: command) else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}
