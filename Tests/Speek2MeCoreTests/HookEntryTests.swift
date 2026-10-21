import Foundation
import Testing
@testable import Speek2MeCore

struct HookEntryTests {
    private let stop = #"{"hook_event_name":"Stop","session_id":"x","cwd":"/Users/moen/Documents/demo","last_assistant_message":"hi"}"#

    private func inbox() -> Inbox {
        Inbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-hook-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func claudeStopLandsInInbox() throws {
        let inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        #expect(HookEntry.run(tool: "claude", input: Data(stop.utf8), environment: [:], inbox: inbox) == 0)
        let events = try inbox.drain()
        #expect(events.count == 1)
        #expect(events.first?.kind == .turnComplete)
        #expect(events.first?.text == "hi")
    }

    @Test func codexToolUsesCodexParser() throws {
        let inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"c","cwd":"/Users/moen/Documents/demo","tool_name":"shell"}"#
        #expect(HookEntry.run(tool: "codex", input: Data(json.utf8), environment: [:], inbox: inbox) == 0)
        #expect(try inbox.drain().first?.source == .codex)
    }

    @Test func suppressedEnvironmentWritesNothing() throws {
        let inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        #expect(HookEntry.run(tool: "claude", input: Data(stop.utf8), environment: ["SPEEK2ME_SUPPRESS": "1"], inbox: inbox) == 0)
        #expect(try inbox.drain().isEmpty)
    }

    @Test func unknownToolOrGarbageIsStillExitZero() throws {
        let inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        #expect(HookEntry.run(tool: "foo", input: Data(stop.utf8), environment: [:], inbox: inbox) == 0)
        #expect(HookEntry.run(tool: "codex", input: Data("nope".utf8), environment: [:], inbox: inbox) == 0)
        #expect(HookEntry.run(tool: "", input: Data(), environment: [:], inbox: inbox) == 0)
        #expect(try inbox.drain().isEmpty)
    }

    @Test func unwritableInboxIsStillExitZero() {
        let inbox = Inbox(directory: URL(fileURLWithPath: "/dev/null/speek2me"))
        #expect(HookEntry.run(tool: "claude", input: Data(stop.utf8), environment: [:], inbox: inbox) == 0)
    }
}
