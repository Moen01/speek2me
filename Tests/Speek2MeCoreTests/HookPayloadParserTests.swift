import Foundation
import Testing
@testable import Speek2MeCore

struct HookPayloadParserTests {
    private func claude(_ json: String) -> SessionEvent? { HookPayloadParser.parseClaude(Data(json.utf8)) }
    private func codex(_ json: String) -> SessionEvent? { HookPayloadParser.parseCodex(Data(json.utf8)) }

    private let stop = #"{"session_id":"abc","cwd":"/p/rea","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done. Two files changed."}"#

    @Test func claudeStopBecomesTurnComplete() throws {
        let event = try #require(claude(stop))
        #expect(event == SessionEvent(source: .claudeCode, kind: .turnComplete, reason: .none,
                                      text: "Done. Two files changed.", sessionID: "abc", cwd: "/p/rea",
                                      receivedAt: event.receivedAt))
    }

    @Test func claudeStopWithoutTextIsIgnored() {
        #expect(claude(#"{"session_id":"abc","cwd":"/p","hook_event_name":"Stop","last_assistant_message":""}"#) == nil)
        #expect(claude(#"{"session_id":"abc","cwd":"/p","hook_event_name":"Stop"}"#) == nil)
    }

    @Test func claudeSubagentStopIsIgnored() {
        let json = #"{"session_id":"abc","cwd":"/p","hook_event_name":"Stop","agent_id":"ag1","agent_type":"Explore","last_assistant_message":"x"}"#
        #expect(claude(json) == nil)
    }

    @Test func temporaryDirectoryRunsAreIgnored() {
        let talk2me = #"{"session_id":"t","cwd":"/var/folders/ab/T/talk2me-claude","hook_event_name":"Stop","last_assistant_message":"dictated words"}"#
        #expect(claude(talk2me) == nil)
        let tmp = NSTemporaryDirectory() + "x"
        #expect(claude(#"{"session_id":"t","cwd":"\#(tmp)","hook_event_name":"Stop","last_assistant_message":"y"}"#) == nil)
        #expect(codex(#"{"session_id":"t","cwd":"/private/tmp/z","hook_event_name":"Stop","last_assistant_message":"y"}"#) == nil)
    }

    @Test func claudeNotificationTypesMap() throws {
        let cases: [(String, AttentionReason)] = [
            ("permission_prompt", .permission), ("elicitation_dialog", .question),
            ("elicitation_url_dialog", .question), ("agent_needs_input", .question), ("idle_prompt", .idle),
        ]
        for (type, reason) in cases {
            let json = #"{"session_id":"abc","cwd":"/p/rea","hook_event_name":"Notification","notification_type":"\#(type)","message":"Claude needs your permission to use Bash"}"#
            let event = try #require(claude(json), "\(type)")
            #expect(event.kind == .needsYou)
            #expect(event.reason == reason)
            #expect(event.text == "Claude needs your permission to use Bash")
            #expect(event.sessionID == "abc")
        }
    }

    @Test func claudeUnknownNotificationOrEventIsIgnored() {
        #expect(claude(#"{"session_id":"a","cwd":"/p","hook_event_name":"Notification","notification_type":"auth_success","message":"m"}"#) == nil)
        #expect(claude(#"{"session_id":"a","cwd":"/p","hook_event_name":"SessionEnd"}"#) == nil)
    }

    @Test func codexStopAndPermissionRequest() throws {
        let done = try #require(codex(#"{"session_id":"c1","cwd":"/p/api","hook_event_name":"Stop","turn_id":"t","last_assistant_message":"Fixed it."}"#))
        #expect(done.source == .codex)
        #expect(done.kind == .turnComplete)
        #expect(done.text == "Fixed it.")
        #expect(done.cwd == "/p/api")
        #expect(codex(#"{"session_id":"c1","cwd":"/p","hook_event_name":"Stop","last_assistant_message":null}"#) == nil)

        let ask = try #require(codex(#"{"session_id":"c1","cwd":"/p/api","hook_event_name":"PermissionRequest","tool_name":"shell","tool_input":{"command":"git push","description":"git push"}}"#))
        #expect(ask.kind == .needsYou)
        #expect(ask.reason == .permission)
        #expect(ask.text == "shell: git push")
        let bare = try #require(codex(#"{"session_id":"c1","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"shell"}"#))
        #expect(bare.text == "shell")
        #expect(codex(#"{"session_id":"c1","cwd":"/p","hook_event_name":"SubagentStop","last_assistant_message":"x"}"#) == nil)
    }

    @Test func malformedInputIsNil() {
        for input in ["not json", "{}", "[1,2]", ""] {
            #expect(claude(input) == nil)
            #expect(codex(input) == nil)
        }
    }

    @Test func missingCwdBecomesEmpty() throws {
        let event = try #require(claude(#"{"session_id":"abc","hook_event_name":"Stop","last_assistant_message":"ok"}"#))
        #expect(event.cwd == "")
        #expect(event.project == "a session")
    }
}
