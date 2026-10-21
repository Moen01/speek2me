import Foundation
import Testing
@testable import Speek2MeCore

struct EarconTests {
    private func event(_ kind: EventKind, _ reason: AttentionReason) -> SessionEvent {
        SessionEvent(source: .claudeCode, kind: kind, reason: reason, text: "", sessionID: "s", cwd: "/p", receivedAt: .init())
    }

    @Test func mapsEventsToSounds() {
        #expect(Earcon.forEvent(event(.turnComplete, .none)) == .done)
        #expect(Earcon.forEvent(event(.needsYou, .permission)) == .permission)
        #expect(Earcon.forEvent(event(.needsYou, .question)) == .question)
        #expect(Earcon.forEvent(event(.needsYou, .idle)) == .idle)
        for earcon in Earcon.allCases {
            #expect(FileManager.default.fileExists(atPath: earcon.fileURL.path), "\(earcon)")
        }
    }
}
