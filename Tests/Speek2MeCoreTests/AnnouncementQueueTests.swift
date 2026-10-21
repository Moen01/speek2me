import Foundation
import Testing
@testable import Speek2MeCore

struct AnnouncementQueueTests {
    private actor Recorder {
        var values: [String] = []
        func add(_ value: String) { values.append(value) }
    }

    /// Suspends callers until opened; opening releases everyone.
    private actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            opened = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    private func event(_ text: String, session: String) -> SessionEvent {
        SessionEvent(source: .claudeCode, kind: .turnComplete, reason: .none, text: text, sessionID: session, cwd: "/p", receivedAt: .init())
    }

    @Test func sameSessionCoalescesAndOrderIsKept() async throws {
        let gate = Gate()
        let recorder = Recorder()
        let queue = AnnouncementQueue { event in
            await recorder.add(event.text)
            if event.text == "A" { await gate.wait() }
        }
        await queue.enqueue(event("A", session: "s1"))
        try await Task.sleep(for: .milliseconds(50))
        await queue.enqueue(event("B", session: "s1"))
        await queue.enqueue(event("C", session: "s1"))
        await queue.enqueue(event("D", session: "s2"))
        #expect(await queue.pending.map(\.text) == ["C", "D"])
        await gate.open()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await recorder.values == ["A", "C", "D"])
        #expect(await queue.lastSpoken?.text == "D")
        #expect(await queue.pending.isEmpty)
    }

    @Test func stopClearsPendingAndCancelsCurrent() async throws {
        let recorder = Recorder()
        let queue = AnnouncementQueue { event in
            await recorder.add("start \(event.text)")
            do {
                try await Task.sleep(for: .seconds(5))
                await recorder.add("finished \(event.text)")
            } catch {
                await recorder.add("cancelled \(event.text)")
            }
        }
        await queue.enqueue(event("A", session: "s1"))
        await queue.enqueue(event("B", session: "s2"))
        try await Task.sleep(for: .milliseconds(50))
        await queue.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await queue.pending.isEmpty)
        #expect(await recorder.values == ["start A", "cancelled A"])
        #expect(await queue.lastSpoken == nil)
        // The queue keeps working after a stop.
        await queue.enqueue(event("C", session: "s3"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorder.values.last == "start C")
        await queue.stop()
    }
}
