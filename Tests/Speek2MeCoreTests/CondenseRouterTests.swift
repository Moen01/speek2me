import Foundation
import Testing
@testable import Speek2MeCore

struct CondenseRouterTests {
    private struct FakeCondenser: Condenser {
        let reply: String
        func condense(_ text: String, project: String, model: ClaudeModel, instructions: String) async throws -> String { reply }
    }

    private func fakeClaude(_ body: String) throws -> (script: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, dir)
    }

    private let input = "## Done\n\nOne. Two. Three. Four."

    @Test func nilBackendUsesRaw() async {
        let outcome = await CondenseRouter.run(text: input, project: "p", backend: nil, model: .haiku, instructions: "", timeout: .seconds(1), maxSentences: 3)
        #expect(outcome.text == "Done. One. Two.")
        #expect(outcome.condensed == false)
        #expect(outcome.failure == nil)
    }

    @Test func backendReplyIsUsed() async {
        let outcome = await CondenseRouter.run(text: input, project: "p", backend: FakeCondenser(reply: "All good."), model: .haiku, instructions: "", timeout: .seconds(1), maxSentences: 3)
        #expect(outcome.text == "All good.")
        #expect(outcome.condensed == true)
    }

    @Test func emptyReplyFallsBackToRaw() async {
        let outcome = await CondenseRouter.run(text: input, project: "p", backend: FakeCondenser(reply: ""), model: .haiku, instructions: "", timeout: .seconds(1), maxSentences: 2)
        #expect(outcome.text == "Done. One.")
        #expect(outcome.condensed == false)
        #expect(outcome.failure == "Claude returned no text")
    }

    @Test func timeoutFallsBackToRaw() async throws {
        let (script, dir) = try fakeClaude("sleep 2\ntouch \"$(dirname \"$0\")/finished\"\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await CondenseRouter.run(text: input, project: "p", backend: ClaudeCodeCondenser(executable: script), model: .haiku, instructions: "", timeout: .milliseconds(300), maxSentences: 3)
        #expect(outcome.text == "Done. One. Two.")
        #expect(outcome.condensed == false)
        #expect(outcome.failure == CondenserError.timedOut.errorDescription)
        try await Task.sleep(for: .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("finished").path))
    }
}
