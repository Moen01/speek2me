import Foundation
import Testing
@testable import Speek2MeCore

struct InboxTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-inbox-\(UUID().uuidString)", isDirectory: true)
    }

    private func event(_ id: String, at date: Date) -> SessionEvent {
        SessionEvent(source: .claudeCode, kind: .turnComplete, reason: .none, text: "text \(id)",
                     sessionID: id, cwd: "/p/rea", receivedAt: date)
    }

    @Test func writeThenDrainRoundTrips() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = Inbox(directory: dir)
        let now = Date()
        let first = event("a", at: now.addingTimeInterval(-2))
        let second = event("b", at: now.addingTimeInterval(-1))
        try inbox.write(second)
        try inbox.write(first)
        #expect(try inbox.drain(now: now) == [first, second])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func drainSkipsCorruptAndStaleFiles() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = Inbox(directory: dir)
        let now = Date()
        try inbox.write(event("stale", at: now.addingTimeInterval(-600)))
        let fresh = event("fresh", at: now.addingTimeInterval(-5))
        try inbox.write(fresh)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("1-x.json"))
        #expect(try inbox.drain(now: now, maxAge: 120) == [fresh])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func drainOfMissingDirectoryIsEmpty() throws {
        #expect(try Inbox(directory: tempDir()).drain().isEmpty)
    }

    @Test func watcherFiresOnNewFile() async throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = Inbox(directory: dir)
        try await confirmation(expectedCount: 1...) { fired in
            let watcher = InboxWatcher(directory: dir) { fired() }
            try watcher.start()
            try inbox.write(event("a", at: .init()))
            try await Task.sleep(for: .milliseconds(500))
            watcher.stop()
        }
    }
}
