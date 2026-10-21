import Foundation
import Testing
@testable import Speek2MeCore

struct ConfigFileTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-config-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func writeCreatesBackupNextToExistingFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try Data("a".utf8).write(to: url)
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12, minute: 0, second: 0)))
        let backup = try #require(try ConfigFile.writeWithBackup(Data("b".utf8), to: url, now: now))
        #expect(backup.lastPathComponent == "settings.json.bak-speek2me-20261021-120000")
        #expect(try Data(contentsOf: backup) == Data("a".utf8))
        #expect(try Data(contentsOf: url) == Data("b".utf8))
    }

    @Test func writeWithoutExistingFileHasNoBackup() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/hooks.json")
        #expect(try ConfigFile.read(url) == nil)
        #expect(try ConfigFile.writeWithBackup(Data("x".utf8), to: url) == nil)
        #expect(try ConfigFile.read(url) == Data("x".utf8))
    }
}
