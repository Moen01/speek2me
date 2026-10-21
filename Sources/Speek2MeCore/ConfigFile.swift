import Foundation

/// Reads and rewrites a user config file with a dated backup beside it.
public enum ConfigFile {
    /// nil when the file does not exist.
    public static func read(_ url: URL) throws -> Data? {
        let target = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        return try Data(contentsOf: target)
    }

    /// Writes atomically to the real file behind `url` (a dotfiles symlink stays a symlink and
    /// keeps its permissions). When the file already existed, first copies its content to
    /// `<name>.bak-speek2me-<yyyyMMdd-HHmmss>` beside it and returns that URL.
    @discardableResult
    public static func writeWithBackup(_ data: Data, to url: URL, now: Date = .init()) throws -> URL? {
        let fm = FileManager.default
        let target = url.resolvingSymlinksInPath()
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        var permissions: Any?
        if fm.fileExists(atPath: target.path) {
            let backupURL = target.appendingPathExtension("bak-speek2me-\(stamp(now))")
            try Data(contentsOf: target).write(to: backupURL, options: .atomic)
            permissions = try? fm.attributesOfItem(atPath: target.path)[.posixPermissions]
            backup = backupURL
        }
        try data.write(to: target, options: .atomic)
        if let permissions {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
        return backup
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
