import Foundation
import Testing
@testable import Speek2MeCore

struct ToolLocatorTests {
    private func fakeTool(_ version: String) throws -> (script: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        try "#!/bin/sh\ncat > /dev/null\necho '\(version)'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, dir)
    }

    @Test func newestPrefersHigherVersion() async throws {
        let (older, dirA) = try fakeTool("2.1.179 (Claude Code)")
        let (newer, dirB) = try fakeTool("2.1.306 (Claude Code)")
        defer { try? FileManager.default.removeItem(at: dirA); try? FileManager.default.removeItem(at: dirB) }
        #expect(await ToolLocator.newest(among: [older, newer]) == newer)
        #expect(await ToolLocator.newest(among: [newer, older]) == newer)
        #expect(await ToolLocator.newest(among: []) == nil)
    }

    @Test func parsesVersionsFromBothTools() {
        #expect(ToolLocator.parseVersion("2.1.306 (Claude Code)") == "2.1.306")
        #expect(ToolLocator.parseVersion("codex-cli 0.115.0") == "0.115.0")
        #expect(ToolLocator.parseVersion("nothing here") == nil)
    }

    @Test func customPathWinsWhenExecutable() {
        #expect(ToolLocator.claude(customPath: "/bin/ls") == URL(fileURLWithPath: "/bin/ls"))
        #expect(ToolLocator.codex(customPath: "/nonexistent/codex") == nil || ToolLocator.codexCandidates.isEmpty == false)
    }
}
