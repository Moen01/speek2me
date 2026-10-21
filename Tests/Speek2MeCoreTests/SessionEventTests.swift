import Foundation
import Testing
@testable import Speek2MeCore

struct SessionEventTests {
    @Test func projectIsLastPathComponent() {
        let event = SessionEvent(source: .claudeCode, kind: .turnComplete, reason: .none, text: "t",
                                 sessionID: "s", cwd: "/Users/moen/Documents/rea", receivedAt: .init())
        #expect(event.project == "rea")
    }

    @Test func projectFallsBackWhenCwdIsRootOrEmpty() {
        for cwd in ["", "/"] {
            let event = SessionEvent(source: .codex, kind: .needsYou, reason: .permission, text: "",
                                     sessionID: "s", cwd: cwd, receivedAt: .init())
            #expect(event.project == "a session")
        }
    }

    @Test func roundTripsThroughJSON() throws {
        let event = SessionEvent(source: .codex, kind: .needsYou, reason: .question, text: "x",
                                 sessionID: "s", cwd: "/a/b", receivedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(SessionEvent.self, from: data) == event)
    }
}
