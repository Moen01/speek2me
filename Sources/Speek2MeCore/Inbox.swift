import Foundation

/// The directory the hook CLI drops events into and the app reads them from.
///
/// A directory instead of a socket: events survive the app not running, nothing listens on a
/// port, and a test can look at the files.
public struct Inbox: Sendable {
    public static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Speek2Me/inbox", isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Writes `<unix milliseconds>-<uuid>.json`. The content lands under a temporary name first and
    /// is renamed into place, so a watcher never reads a half-written file.
    @discardableResult
    public func write(_ event: SessionEvent) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(Int(event.receivedAt.timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
        let final = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent(name + ".tmp")
        try JSONEncoder().encode(event).write(to: temporary, options: .atomic)
        try FileManager.default.moveItem(at: temporary, to: final)
        return final
    }

    /// Reads and deletes every event, oldest first. Files that do not decode, events older than
    /// `maxAge`, and abandoned temporary files are deleted and skipped.
    public func drain(now: Date = .init(), maxAge: TimeInterval = 120) throws -> [SessionEvent] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        var events: [SessionEvent] = []
        for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            if file.pathExtension == "tmp" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if now.timeIntervalSince(modified) > maxAge { try? fm.removeItem(at: file) }
                continue
            }
            guard file.pathExtension == "json" else { continue }
            defer { try? fm.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let event = try? JSONDecoder().decode(SessionEvent.self, from: data),
                  now.timeIntervalSince(event.receivedAt) <= maxAge else { continue }
            events.append(event)
        }
        return events.sorted { $0.receivedAt < $1.receivedAt }
    }
}
