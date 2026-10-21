import Foundation

/// Reads and rewrites a user config file with a dated backup beside it.
public enum ConfigFile {
    /// nil when the file does not exist.
    public static func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Writes atomically. When the file already existed, first copies it to
    /// `<name>.bak-speek2me-<yyyyMMdd-HHmmss>` and returns that URL.
    @discardableResult
    public static func writeWithBackup(_ data: Data, to url: URL, now: Date = .init()) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if fm.fileExists(atPath: url.path) {
            let target = url.appendingPathExtension("bak-speek2me-\(stamp(now))")
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: url, to: target)
            backup = target
        }
        try data.write(to: url, options: .atomic)
        return backup
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
