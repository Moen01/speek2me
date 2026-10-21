import Foundation
import Testing
@testable import Speek2MeCore

struct HooksJSONTests {
    private let cmuxSettings = Data(#"{"permissions":{"allow":["Bash(ls:*)"]},"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/Users/moen/.claude/hooks/cmux-notify.sh"}]}],"Notification":[{"hooks":[{"type":"command","command":"/Users/moen/.claude/hooks/cmux-notify.sh"}]}]}}"#.utf8)
    private let command = "\"/Applications/Speek2Me.app/Contents/MacOS/speek2me-hook\" claude"
    private var groups: [HooksJSON.Group] { ClaudeHooksInstaller.groups(command: command) }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func eventGroups(_ data: Data, _ event: String) throws -> [[String: Any]] {
        let hooks = try #require(try object(data)["hooks"] as? [String: Any])
        return try #require(hooks[event] as? [[String: Any]])
    }

    @Test func installKeepsExistingHooksAndOtherKeys() throws {
        let out = try HooksJSON.install(cmuxSettings, groups: groups)
        let root = try object(out)
        #expect((root["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
        #expect(root["model"] as? String == "opus")
        let stop = try eventGroups(out, "Stop")
        #expect(stop.count == 1)
        let stopHandlers = try #require(stop[0]["hooks"] as? [[String: Any]])
        #expect(stopHandlers.map { $0["command"] as? String } == ["/Users/moen/.claude/hooks/cmux-notify.sh", command])
        #expect(stopHandlers[1]["async"] as? Bool == true)
        #expect(stopHandlers[1]["timeout"] as? Int == 5)
        #expect(stopHandlers[1]["type"] as? String == "command")
        let notification = try eventGroups(out, "Notification")
        #expect(notification.count == 2)
        #expect(notification[0]["matcher"] == nil)
        #expect(notification[1]["matcher"] as? String == ClaudeHooksInstaller.notificationMatcher)
        #expect((notification[1]["hooks"] as? [[String: Any]])?.first?["command"] as? String == command)
        #expect(try HooksJSON.isInstalled(out))
        #expect(try !HooksJSON.isInstalled(cmuxSettings))
        #expect(try HooksJSON.installedCommands(out) == [command, command])
        #expect(try HooksJSON.installedCommands(cmuxSettings).isEmpty)
    }

    @Test func installIsIdempotent() throws {
        let once = try HooksJSON.install(cmuxSettings, groups: groups)
        let twice = try HooksJSON.install(once, groups: groups)
        #expect(try HooksJSON.pretty(once) == HooksJSON.pretty(twice))
    }

    @Test func installCreatesStructureWhenMissing() throws {
        for input in [nil, Data("{}".utf8), Data(#"{"hooks":{"Stop":[]}}"#.utf8), Data(#"{"hooks":{}}"#.utf8)] {
            let out = try HooksJSON.install(input, groups: groups)
            #expect(try eventGroups(out, "Stop").count == 1)
            #expect(try eventGroups(out, "Notification").count == 1)
            #expect(try HooksJSON.isInstalled(out))
        }
    }

    @Test func removeRestoresShape() throws {
        let installed = try HooksJSON.install(cmuxSettings, groups: groups)
        let removed = try HooksJSON.remove(installed)
        #expect(try HooksJSON.pretty(removed) == HooksJSON.pretty(cmuxSettings))
        let bare = try HooksJSON.remove(try HooksJSON.install(nil, groups: groups))
        #expect(try object(bare)["hooks"] == nil)
    }

    @Test func invalidJSONRefuses() {
        for input in [Data("[1,2]".utf8), Data("not json".utf8)] {
            #expect(throws: HooksJSON.Error.invalidJSON) { try HooksJSON.install(input, groups: groups) }
            #expect(throws: HooksJSON.Error.invalidJSON) { try HooksJSON.isInstalled(input) }
        }
    }

    @Test func installerWritesAndRemovesAtAGivenPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-settings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        #expect(ClaudeHooksInstaller.isInstalled(at: url) == false)
        #expect(try ClaudeHooksInstaller.install(command: command, at: url) == nil)
        #expect(ClaudeHooksInstaller.isInstalled(at: url))
        #expect(try ClaudeHooksInstaller.install(command: command, at: url) == nil)
        #expect(try ClaudeHooksInstaller.plannedChange(command: command, at: url).contains("speek2me-hook"))
        let backup = try #require(try ClaudeHooksInstaller.remove(at: url))
        #expect(backup.lastPathComponent.hasPrefix("settings.json.bak-speek2me-"))
        #expect(ClaudeHooksInstaller.isInstalled(at: url) == false)
    }
}
