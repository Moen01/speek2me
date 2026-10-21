import Foundation
import Testing
@testable import Speek2MeCore

struct CodexHooksInstallerTests {
    private let command = "\"/Applications/Speek2Me.app/Contents/MacOS/speek2me-hook\" codex"

    private func tempHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func installWritesHooksAndEnablesFeature() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let hooks = home.appendingPathComponent("hooks.json")
        let config = home.appendingPathComponent("config.toml")
        try Data("model = \"gpt-5.2\"\n".utf8).write(to: config)

        let backups = try CodexHooksInstaller.install(command: command, hooksAt: hooks, configAt: config)
        #expect(backups.count == 1)
        #expect(backups.first?.lastPathComponent.hasPrefix("config.toml.bak-speek2me-") == true)
        #expect(CodexHooksInstaller.isInstalled(hooksAt: hooks))
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as? [String: Any])
        let events = try #require(root["hooks"] as? [String: Any])
        #expect(Set(events.keys) == ["Stop", "PermissionRequest"])
        #expect(try String(contentsOf: config, encoding: .utf8) == "model = \"gpt-5.2\"\n\n[features]\nhooks = true\n")

        #expect(try CodexHooksInstaller.install(command: command, hooksAt: hooks, configAt: config).isEmpty)
        let planned = try CodexHooksInstaller.plannedChange(command: command, hooksAt: hooks, configAt: config)
        #expect(planned.hooks.contains("speek2me-hook"))
        #expect(planned.config.contains("hooks = true"))
    }

    @Test func removeLeavesConfigAlone() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let hooks = home.appendingPathComponent("hooks.json")
        let config = home.appendingPathComponent("config.toml")
        try CodexHooksInstaller.install(command: command, hooksAt: hooks, configAt: config)
        let configAfterInstall = try Data(contentsOf: config)
        let backup = try #require(try CodexHooksInstaller.remove(hooksAt: hooks))
        #expect(backup.lastPathComponent.hasPrefix("hooks.json.bak-speek2me-"))
        #expect(CodexHooksInstaller.isInstalled(hooksAt: hooks) == false)
        #expect(try Data(contentsOf: config) == configAfterInstall)
        #expect(try CodexHooksInstaller.remove(hooksAt: hooks) == nil)
    }
}
