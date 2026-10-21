import Foundation
import Testing
@testable import Speek2MeCore

struct AnnouncerTests {
    private func event(_ kind: EventKind, _ reason: AttentionReason, text: String) -> SessionEvent {
        SessionEvent(source: .claudeCode, kind: kind, reason: reason, text: text, sessionID: "s", cwd: "/Users/moen/Documents/rea", receivedAt: .init())
    }

    @Test func templates() {
        #expect(Announcer.text(for: event(.turnComplete, .none, text: "ignored"), condensed: "Done. Report ready.") == "rea: Done. Report ready.")
        #expect(Announcer.text(for: event(.needsYou, .permission, text: "Claude needs your permission to use Bash"), condensed: "") == "rea needs you: Claude needs your permission to use Bash")
        #expect(Announcer.text(for: event(.needsYou, .permission, text: ""), condensed: "") == "rea needs your approval.")
        #expect(Announcer.text(for: event(.needsYou, .question, text: "Which option? Pick one. Now."), condensed: "") == "rea has a question: Which option?")
        #expect(Announcer.text(for: event(.needsYou, .question, text: ""), condensed: "") == "rea has a question for you.")
        #expect(Announcer.text(for: event(.needsYou, .idle, text: "Claude is waiting for your input"), condensed: "") == "rea is waiting for you.")
    }
}
